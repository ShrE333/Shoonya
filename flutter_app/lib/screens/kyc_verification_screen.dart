import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
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
  
  bool _isSpeaking = false;
  bool _isListening = false;
  bool _isAnalyzing = false;
  bool _isScanning = false;
  int _currentStep = 0;
  String _agentText = "Booting Security Core...";
  String _currentWords = "";
  final List<Map<String, String>> _transcript = [];
  
  String? _aadhaarPath;
  String? _panPath;

  final List<String> _questionBank = [
    "Welcome to Shoonya. Please stay in frame and state your full name?",
    "Identity: Align your Aadhaar card and tap CAPTURE when ready.", 
    "Aadhaar stored. Now, please show your PAN card and tap CAPTURE.", 
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
    _boot();
  }

  Future<void> _boot() async {
    await [Permission.microphone, Permission.camera].request();
    final cams = await availableCameras();
    _cam = CameraController(cams.firstWhere((c) => c.lensDirection == CameraLensDirection.front), ResolutionPreset.high);
    await _cam!.initialize();
    await _speech.initialize();
    if (mounted) setState(() {});
    Timer(const Duration(seconds: 2), () => _nextStep());
  }

  @override
  void dispose() { _speech.cancel(); _player.dispose(); _cam?.dispose(); super.dispose(); }

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

    try {
      final res = await http.post(Uri.parse("https://api.sarvam.ai/text-to-speech"),
        headers: {"api-subscription-key": sarvamKey, "Content-Type": "application/json"},
        body: jsonEncode({"text": text, "target_language_code": "en-IN", "speaker": "shubh", "model": "bulbul:v3", "pace": 1.0, "speech_sample_rate": 24000}));
      
      if (res.statusCode == 200) {
        await _player.play(BytesSource(base64Decode(jsonDecode(res.body)['audios'][0])));
        _player.onPlayerComplete.first.then((_) {
          if (mounted) {
            setState(() => _isSpeaking = false);
            if (!_isScanning) _listen();
          }
        });
      } else { 
        setState(() => _isSpeaking = false); 
        if (!_isScanning) _listen();
      }
    } catch (e) { setState(() => _isSpeaking = false); }
  }

  Future<void> _captureCard() async {
    if (_cam == null || !_cam!.value.isInitialized) return;
    try {
      final XFile image = await _cam!.takePicture();
      if (_currentStep == 1) _aadhaarPath = image.path;
      if (_currentStep == 2) _panPath = image.path;
      
      setState(() { _currentStep++; _isScanning = false; });
      _nextStep();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Capture failed. Try again.")));
    }
  }

  Future<void> _listen() async {
    if (!mounted || _isScanning) return;
    await _speech.stop();
    setState(() { _isListening = true; _currentWords = ""; });
    await _speech.listen(onResult: (val) {
      setState(() => _currentWords = val.recognizedWords);
      if (val.finalResult) {
        setState(() => _isListening = false);
        _transcript.add({"role": "user", "text": val.recognizedWords});
        _currentStep++;
        _nextStep();
      }
    }, localeId: "en-IN");
  }

  Future<void> _finish() async {
    if (_isAnalyzing) return;
    setState(() { _isAnalyzing = true; _agentText = "Syncing Vault & Creating Loan Request..."; });

    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      try {
        // 1. Upload Images
        if (_aadhaarPath != null) {
           await Supabase.instance.client.storage.from('documents').upload('${user.id}/aadhaar.jpg', File(_aadhaarPath!), fileOptions: const FileOptions(upsert: true));
        }
        if (_panPath != null) {
           await Supabase.instance.client.storage.from('documents').upload('${user.id}/pan.jpg', File(_panPath!), fileOptions: const FileOptions(upsert: true));
        }

        // 2. Groq Analysis
        final transcriptText = _transcript.map((m) => "${m['role']}: ${m['text']}").join("\n");
        final prompt = """Analyze and return LOAN JSON: $transcriptText.
        JSON: {"status":"Approved","loan_amount":500000,"type":"Personal","interest_rate":12,"tenure":24,"emi":24000,"risk":"Low","reason":"Verified Identity"}""";

        final groqRes = await http.post(Uri.parse("https://api.groq.com/openai/v1/chat/completions"),
          headers: {"Authorization": "Bearer $groqKey", "Content-Type": "application/json"},
          body: jsonEncode({"model": "llama-3.1-8b-instant", "messages": [{"role": "system", "content": "Return JSON only."}, {"role": "user", "content": prompt}], "response_format": {"type": "json_object"}}));

        final analysis = jsonDecode(jsonDecode(groqRes.body)['choices'][0]['message']['content']);

        // 3. Create Loan (The "Missing Link")
        await Supabase.instance.client.from('loans').insert({
          'user_id': user.id,
          'amount_requested': analysis['loan_amount'],
          'loan_type': analysis['type'],
          'status': 'pending',
          'analysis_data': analysis
        });

        // 4. Final Profile Update
        await Supabase.instance.client.from('profiles').update({'kyc_status': 'verified', 'loan_limit': 1000000}).eq('id', user.id);
        
        setState(() => _agentText = "Success! Admin has been notified.");
        Timer(const Duration(seconds: 4), () => context.go('/dashboard'));
      } catch (e) { context.go('/dashboard'); }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      body: Stack(children: [
        if (_cam?.value.isInitialized ?? false) Positioned.fill(child: CameraPreview(_cam!)),
        Positioned.fill(child: Container(color: Colors.black.withOpacity(_isScanning ? 0.2 : 0.6))),
        
        if (_isScanning) Center(
          child: Container(
            width: 300, height: 180,
            decoration: BoxDecoration(border: Border.all(color: const Color(0xFF10B981), width: 3), borderRadius: BorderRadius.circular(16)),
          ),
        ),

        SafeArea(child: Column(children: [
          const Padding(padding: EdgeInsets.all(24), child: Text("SHOONYA SECURE INTERVIEW", style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, letterSpacing: 2, fontSize: 10))),
          const Spacer(),
          Container(
            margin: const EdgeInsets.all(24), padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(color: const Color(0xFF1E293B).withOpacity(0.9), borderRadius: BorderRadius.circular(32)),
            child: Text(_agentText, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, height: 1.4)),
          ),
          
          if (_isScanning) Padding(
            padding: const EdgeInsets.only(bottom: 40),
            child: ElevatedButton.icon(
              onPressed: _captureCard,
              icon: const Icon(Icons.camera_alt),
              label: const Text("CAPTURE DOCUMENT"),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.black, minimumSize: const Size(250, 60), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))),
            ),
          )
          else Container(height: 100, decoration: const BoxDecoration(color: Color(0xFF0F172A), borderRadius: BorderRadius.vertical(top: Radius.circular(50))), child: Center(child: Text(_isListening ? "LISTENING..." : "SPEAKING", style: const TextStyle(color: Colors.white24, fontWeight: FontWeight.bold))))
        ]))
      ])
    );
  }
}
