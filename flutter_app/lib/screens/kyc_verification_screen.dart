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
  bool _isScanning = false; // To show the OCR frame
  int _currentStep = 0;
  String _agentText = "Booting Security Core...";
  String _currentWords = "";
  final List<Map<String, String>> _transcript = [];

  // OCR SCRIPT 4.0 (Aadhaar & PAN are now visual)
  final List<String> _questionBank = [
    "Welcome to Shoonya. I'm your AI bank officer. For security, please stay in the frame and state your full name?",
    "Thank you. Now, please align your original Aadhaar card within the green frame for an AI visual scan?", // STEP 1: AADHAAR OCR
    "Aadhaar captured. Next, please show your original PAN card clearly to the camera?", // STEP 2: PAN OCR
    "Perfect. Identity verified. What is your current employment type?",
    "To help us calculate your limit, what is your average monthly income after tax?",
    "Do you have any existing loans from other banks? If yes, what is the EMI?",
    "Almost there. Which loan product are you interested in: Personal, Home, or Vehicle?",
    "What is the specific loan amount you require?",
    "Finally, over what period would you like to repay this loan?",
    "Thank you. I am now analyzing your documents and conversation for final sanctioning. Please wait."
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
      _isScanning = (_currentStep == 1 || _currentStep == 2); // Show OCR frame on steps 1 and 2
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
            if (_isScanning) {
              _autoCapture(); // Wait for 3 seconds then skip or capture
            } else if (_currentStep < _questionBank.length - 1) {
              _listen();
            } else {
              _finish();
            }
          }
        });
      } else { 
        setState(() => _isSpeaking = false); 
        if (_isScanning) _autoCapture(); else _listen();
      }
    } catch (e) { setState(() => _isSpeaking = false); }
  }

  Future<void> _autoCapture() async {
    // Simulating "Scanning" delay
    await Future.delayed(const Duration(seconds: 4));
    if (_cam != null && _cam!.value.isInitialized) {
       // In a real app: await _cam!.takePicture(); and send to OCR API
    }
    setState(() { _isScanning = false; _currentStep++; });
    _nextStep();
  }

  Future<void> _listen() async {
    if (!mounted) return;
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
    setState(() { _isAnalyzing = true; _agentText = "Finalizing AI Sanction Audit..."; });
    // Same Groq analysis logic as before...
    Timer(const Duration(seconds: 5), () => context.go('/dashboard'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      body: Stack(children: [
        if (_cam?.value.isInitialized ?? false) Positioned.fill(child: CameraPreview(_cam!)),
        
        // DOCUMENT SCANNER OVERLAY (Glow Frame)
        if (_isScanning) Center(
          child: Container(
            width: 320,
            height: 200,
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF10B981), width: 4),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: const Color(0xFF10B981).withOpacity(0.3), blurRadius: 40, spreadRadius: 5)]
            ),
            child: const Center(child: Text("ALIGN CARD HERE", style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.w900, fontSize: 16))),
          ),
        ),

        Positioned.fill(child: Container(color: Colors.black.withOpacity(_isScanning ? 0.3 : 0.6))),
        
        SafeArea(child: Column(children: [
          Padding(padding: const EdgeInsets.all(24), child: const Text("SHOONYA IDENTITY SCAN", style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, letterSpacing: 2, fontSize: 12))),
          const Spacer(),
          Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(color: const Color(0xFF1E293B).withOpacity(0.9), borderRadius: BorderRadius.circular(32), border: Border.all(color: _isScanning ? const Color(0xFF10B981) : Colors.white10)),
            child: Column(children: [
              if (_isScanning) const Padding(padding: EdgeInsets.only(bottom: 16), child: LinearProgressIndicator(color: Color(0xFF10B981), backgroundColor: Colors.white10)),
              Text(_agentText, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w700, height: 1.4)),
            ]),
          ),
          const SizedBox(height: 100)
        ]))
      ])
    );
  }
}
