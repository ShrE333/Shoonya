import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_vision/flutter_vision.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:audio_session/audio_session.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

class KYCVerificationScreen extends StatefulWidget {
  final String token;
  const KYCVerificationScreen({super.key, required this.token});

  @override
  State<KYCVerificationScreen> createState() => _KYCVerificationScreenState();
}

class _KYCVerificationScreenState extends State<KYCVerificationScreen> {
  final SpeechToText _speech = SpeechToText();
  final AudioPlayer _player = AudioPlayer();
  CameraController? _cam;
  late FlutterVision _vision;
  
  bool _isSpeaking = false;
  bool _isListening = false;
  bool _isAnalyzing = false;
  bool _isScanning = false;
  bool _isModelLoaded = false;
  int _currentStep = 0;
  String _agentText = "Booting Security Core...";
  String _currentWords = "";
  final List<Map<String, String>> _transcript = [];
  List<Map<String, dynamic>> _yoloResults = [];
  
  String? _aadhaarPath;
  String? _panPath;

  final List<String> _questionBank = [
    "Welcome to Shoonya. Please stay in frame and state your full name?",
    "Identity Verification: Please show your original Aadhaar card clearly to the camera.", 
    "Aadhaar verified. Now, please align your PAN card for our AI scanner.", 
    "Thank you. Everything looks good. What is your current employment type?",
    "What is your average monthly income after tax?",
    "Do you have any existing bank loans? If so, what is the EMI?",
    "Which loan product do you need: Personal, Home, or Vehicle?",
    "What is the specific loan amount you require?",
    "Finally, over what period would you like to repay this loan?",
    "Analyzing your profile. We are generating your sanction report and notifying the admin. Please stay on screen."
  ];

  final String sarvamKey = "sk_w9w5soy4_f4o4tZcMjnW8VDDFkRV0Os1Q";
  final String groqKey = const String.fromEnvironment('GROQ_API_KEY');

  @override
  void initState() {
    super.initState();
    _vision = FlutterVision();
    _boot();
  }

  Future<void> _boot() async {
    await [Permission.microphone, Permission.camera].request();
    final cams = await availableCameras();
    _cam = CameraController(cams.firstWhere((c) => c.lensDirection == CameraLensDirection.front), ResolutionPreset.high, enableAudio: false);
    await _cam!.initialize();
    
    // Load YOLO Model (STABLE CPU MODE)
    try {
      await _vision.loadYoloModel(
        modelPath: 'assets/models/yolo_int8.tflite',
        labels: 'assets/models/labels.txt',
        modelVersion: "yolov8",
        quantization: true,
        numThreads: 2,
        useGpu: false, // Changed to false for better device compatibility
      );
    } catch (e) {
      print("VISION ERROR: $e");
    }

    await _speech.initialize();
    setState(() => _isModelLoaded = true);
    Timer(const Duration(seconds: 2), () => _nextStep());
  }

  @override
  void dispose() { 
    _vision.closeYoloModel();
    _speech.cancel(); 
    _player.dispose(); 
    _cam?.dispose(); 
    super.dispose(); 
  }

  void _nextStep() {
    if (_isAnalyzing) return;
    if (_currentStep < _questionBank.length) {
      _speak(_questionBank[_currentStep]);
    } else {
      _finish();
    }
  }

  Future<void> _speak(String text) async {
    if (!mounted) return;
    setState(() { 
      _agentText = text; 
      _isSpeaking = true; 
      _isScanning = (_currentStep == 1 || _currentStep == 2); 
      _transcript.add({"role": "officer", "text": text}); 
    });

    if (_isScanning) _startVisionStream();

    try {
      final res = await http.post(Uri.parse("https://api.sarvam.ai/text-to-speech"),
        headers: {"api-subscription-key": sarvamKey, "Content-Type": "application/json"},
        body: jsonEncode({"text": text, "target_language_code": "en-IN", "speaker": "shubh", "model": "bulbul:v3", "pace": 1.0, "speech_sample_rate": 24000}));
      
      if (res.statusCode == 200) {
        await _player.play(BytesSource(base64Decode(jsonDecode(res.body)['audios'][0])));
        _player.onPlayerComplete.first.then((_) {
          if (mounted && !_isScanning) {
            setState(() => _isSpeaking = false);
            _listen(); // FULL AUTO
          }
        });
      } else { 
        setState(() => _isSpeaking = false); 
        if (!_isScanning) _listen();
      }
    } catch (e) { setState(() => _isSpeaking = false); }
  }

  int _frameCount = 0;
  bool _isProcessing = false;

  void _onCameraImage(CameraImage image) async {
    if (!_isScanning || _isProcessing) return;
    _frameCount++;
    if (_frameCount % 4 != 0) return; // Balanced for high-stability
    
    _isProcessing = true;
    try {
      final results = await _vision.yoloOnFrame(
        bytesList: image.planes.map((p) => p.bytes).toList(),
        imageHeight: image.height,
        imageWidth: image.width,
        iouThreshold: 0.4,
        confThreshold: 0.35, 
      );

      if (mounted) {
        setState(() => _yoloResults = results);
        
        for (final res in results) {
          final tag = res['tag'];
          final conf = res['box'][4];
          
          if ((tag == 'Aadhar' || tag == 'pan-card') && conf > 0.4) {
            print("AI SIGNAL: $tag found! (Conf: $conf)");
            _autoCapture();
            break;
          }
        }
      }
    } catch (e) {
      print("AI VISION ERROR: $e");
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _startVisionStream() async {
    if (_cam == null || !_isScanning) return;
    await _cam!.startImageStream(_onCameraImage);
  }

  Future<void> _autoCapture() async {
    try {
      final XFile image = await _cam!.takePicture();
      final path = image.path;
      if (_currentStep == 1) _aadhaarPath = path;
      if (_currentStep == 2) _panPath = path;
      
      // OCR with Groq Vision
      print("OCR: Analyzing document with Groq Vision...");
      try {
        final bytes = await File(path).readAsBytes();
        final base64Image = base64Encode(bytes);
        final res = await http.post(Uri.parse("https://api.groq.com/openai/v1/chat/completions"),
          headers: {"Authorization": "Bearer $groqKey", "Content-Type": "application/json"},
          body: jsonEncode({
            "model": "llama-3.2-11b-vision-preview",
            "messages": [{
              "role": "user",
              "content": [
                {"type": "text", "text": "Extract Document ID and Name from this Indian ID card. Return JSON: {'id': '...', 'name': '...'}"},
                {"type": "image_url", "image_url": {"url": "data:image/jpeg;base64,$base64Image"}}
              ]
            }],
            "response_format": {"type": "json_object"}
          }));
        print("OCR RESULT: ${res.body}");
      } catch (e) { print("OCR LOG: $e"); }

      setState(() { _currentStep++; _isScanning = false; _yoloResults = []; });
      _nextStep();
    } catch (e) { _startVisionStream(); }
  }

  Future<void> _listen() async {
    if (!mounted || _isScanning) return;
    await _speech.stop();
    await _player.stop(); // Ensure audio is dead
    await Future.delayed(const Duration(milliseconds: 500)); // H/W Cool down

    setState(() { _isListening = true; _currentWords = ""; });
    await _speech.listen(onResult: (val) {
      if (!mounted) return;
      setState(() => _currentWords = val.recognizedWords);
      if (val.finalResult) {
        setState(() => _isListening = false);
        _transcript.add({"role": "user", "text": val.recognizedWords});
        _currentStep++;
        _nextStep();
      }
    }, localeId: "en-IN", listenMode: ListenMode.confirmation);
  }

  Future<void> _finish() async {
    if (_isAnalyzing) return;
    setState(() { _isAnalyzing = true; _agentText = "Senior Credit Officer Analyzing Profile..."; });
    
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw "No user authenticated";

      await _vision.closeYoloModel();
      
      // Analysis with High-End Multi-Option Strategy
      final transcriptText = _transcript.map((m) => "${m['role']}: ${m['text']}").join("\n");
      final prompt = """Acting as a Senior Bank Manager, analyze this interview: $transcriptText.
      Output ONLY JSON with 3 varied loan options (Economy, Standard, Platinum):
      {"options": [
        {"name": "Economy", "amount": 25000, "tenure": 12, "rate": 12.5},
        {"name": "Standard", "amount": 50000, "tenure": 24, "rate": 11.0},
        {"name": "Platinum", "amount": 100000, "tenure": 36, "rate": 9.5}
      ], "limit": 100000}""";

      Map<String, dynamic> analysis = {"options": [{"name": "Standard", "amount": 20000, "tenure": 12, "rate": 12}]};
      try {
        final groqRes = await http.post(Uri.parse("https://api.groq.com/openai/v1/chat/completions"),
          headers: {"Authorization": "Bearer $groqKey", "Content-Type": "application/json"},
          body: jsonEncode({"model": "llama-3.1-8b-instant", "messages": [{"role": "system", "content": "Return JSON only."}, {"role": "user", "content": prompt}], "response_format": {"type": "json_object"}}));
        if (groqRes.statusCode == 200) {
          analysis = jsonDecode(jsonDecode(groqRes.body)['choices'][0]['message']['content']);
        }
      } catch (e) { print("AI ERROR: $e"); }

      // Update Profile & Create Multi-Option Loan
      await Supabase.instance.client.from('profiles').update({'kyc_status': 'verified','loan_limit': (analysis['limit'] ?? 50000).toDouble()}).eq('id', user.id);
      
      await Supabase.instance.client.from('loans').insert({
        'user_id': user.id, 
        'amount_requested': (analysis['options'][0]['amount']).toDouble(), 
        'status': 'pending',
        'offers': analysis['options']
      });

      // Generate PDF Offer (Standalone Logic)
      final pdf = pw.Document();
      pdf.addPage(pw.Page(build: (pw.Context context) => pw.Center(child: pw.Text("AI CREDIT OFFER - SHOONYA\nApproved Options for User ${user.email}"))));
      final bytes = await pdf.save();
      await Supabase.instance.client.storage.from('documents').uploadBinary('${user.id}/offer_sheet.pdf', bytes, fileOptions: const FileOptions(upsert: true));

      setState(() => _agentText = "Credit Strategy Finalized. Check your Hub.");
      Timer(const Duration(seconds: 3), () => context.go('/dashboard'));
    } catch (e) {
      print("SYNC FATAL: $e");
      context.go('/dashboard');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        if (_cam?.value.isInitialized ?? false) Center(
            child: Stack(
              children: [
                Container(
                  width: 320, height: 400,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(54),
                    border: Border.all(color: Colors.white.withOpacity(0.1), width: 8),
                    boxShadow: [BoxShadow(color: const Color(0xFF10B981).withOpacity(0.2), blurRadius: 40)]
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(46),
                    child: AspectRatio(aspectRatio: 1, child: CameraPreview(_cam!)),
                  ),
                ),
                // AI DETECTION OVERLAY (CALIBRATED FOR 320x480)
                if (_yoloResults.isNotEmpty) ..._yoloResults.map((res) {
                  return Positioned(
                    left: res['box'][0] * 320,
                    top: res['box'][1] * 400,
                    width: (res['box'][2] - res['box'][0]) * 320,
                    height: (res['box'][3] - res['box'][1]) * 400,
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFF10B981), width: 3),
                        borderRadius: BorderRadius.circular(8)
                      ),
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: Container(
                          color: const Color(0xFF10B981),
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          child: Text(res['tag'], style: const TextStyle(color: Colors.black, fontSize: 8, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        
        // Fintech Overlay
        Positioned.fill(child: Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(colors: [Colors.transparent, Colors.black.withOpacity(0.9)], radius: 1.2)
          )
        )),

        SafeArea(child: Column(children: [
          const Padding(padding: EdgeInsets.all(32), child: Text("IDENTITY PROTOCOL v2", style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.w900, letterSpacing: 4, fontSize: 10))),
          if (_isScanning) Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), decoration: BoxDecoration(color: const Color(0xFF10B981), borderRadius: BorderRadius.circular(40)), child: const Text("AI SCANNING", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 8))),
          const Spacer(),
          
          GlassBox(child: Text(_agentText, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold))),

          const SizedBox(height: 24),
          Container(
            height: 100, width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(color: Color(0xFF0F172A), borderRadius: BorderRadius.vertical(top: Radius.circular(48))),
            child: Row(children: [
              Container(width: 12, height: 12, decoration: BoxDecoration(color: _isListening ? const Color(0xFF10B981) : Colors.white12, shape: BoxShape.circle)),
              const SizedBox(width: 16),
              Expanded(child: Text(_isListening ? "Listening: $_currentWords" : "AI OFFICER THINKING...", style: const TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.bold))),
            ]),
          )
        ]))
      ])
    );
  }
}

class GlassBox extends StatelessWidget {
  final Widget child;
  const GlassBox({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 32),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20)]
      ),
      child: child,
    );
  }
}
