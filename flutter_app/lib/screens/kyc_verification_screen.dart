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
  int _currentStep = 0;
  String _agentText = "Booting Officer AI...";
  String _selectedLang = "en-IN";
  String _currentWords = "";
  final List<Map<String, String>> _history = [];
  String _statusMsg = "";

  final String sarvamKey = "sk_w9w5soy4_f4o4tZcMjnW8VDDFkRV0Os1Q";
  final String groqKey = const String.fromEnvironment('GROQ_API_KEY');

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      await [Permission.microphone, Permission.camera].request();
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.speech());
      await session.setActive(true);

      final cameras = await availableCameras();
      final front = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.front, orElse: () => cameras.first);
      _cam = CameraController(front, ResolutionPreset.low, enableAudio: false);
      await _cam!.initialize();
      if (mounted) setState(() {});

      bool ok = await _speech.initialize();
      if (ok) {
        Timer(const Duration(seconds: 2), () => _run());
      } else {
        setState(() => _statusMsg = "STT Init Failed");
      }
    } catch (e) {
      setState(() => _statusMsg = "Hardware Error: $e");
    }
  }

  @override
  void dispose() {
    _speech.cancel();
    _player.dispose();
    _cam?.dispose();
    super.dispose();
  }

  void _run() {
    _currentStep = 1;
    _communicate("Welcome to Shoonya. I am your personal AI loan officer. Before we begin, would you like to conduct this interview in English or Hindi?");
  }

  Future<void> _communicate(String text) async {
    if (!mounted) return;
    setState(() {
      _agentText = text;
      _isSpeaking = true;
      _history.add({"role": "officer", "text": text});
    });

    try {
      final res = await http.post(
        Uri.parse("https://api.sarvam.ai/text-to-speech"),
        headers: {"api-subscription-key": sarvamKey, "Content-Type": "application/json"},
        body: jsonEncode({
          "text": text,
          "target_language_code": _selectedLang,
          "speaker": _selectedLang == "hi-IN" ? "ritu" : "shubh",
          "model": "bulbul:v3",
          "pace": 1.0,
          "speech_sample_rate": 24000,
          "temperature": 0.6
        }),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        await _player.play(BytesSource(base64Decode(data['audios'][0])));
        _player.onPlayerComplete.first.then((_) {
          if (mounted) {
            setState(() => _isSpeaking = false);
            _listenMic();
          }
        });
      } else {
        setState(() => _isSpeaking = false);
        _listenMic();
      }
    } catch (e) {
      setState(() => _isSpeaking = false);
      _listenMic();
    }
  }

  Future<void> _listenMic() async {
    if (!mounted) return;
    await _speech.stop();
    await Future.delayed(const Duration(milliseconds: 300));
    setState(() { _isListening = true; _currentWords = ""; });
    await _speech.listen(
      onResult: (val) {
        setState(() => _currentWords = val.recognizedWords);
        if (val.finalResult) _onHeard(val.recognizedWords);
      },
      localeId: _selectedLang,
      listenFor: const Duration(seconds: 12),
      pauseFor: const Duration(seconds: 4),
    );
  }

  void _onHeard(String text) {
    if (!_isListening) return;
    setState(() => _isListening = false);
    if (text.trim().isEmpty) { 
      _communicate(_selectedLang == "hi-IN" ? "क्षमा करें, मुझे सुनाई नहीं दिया। क्या आप कृपया दोहरा सकते हैं?" : "I'm sorry, I didn't catch that. Could you please repeat that?"); 
      return; 
    }
    setState(() => _history.add({"role": "user", "text": text}));
    _processBrain(text);
  }

  Future<void> _processBrain(String input) async {
    if (!mounted) return;
    setState(() => _agentText = "Synchronizing...");
    
    final prompt = """
    YOU ARE A PROFESSIONAL BANK LOAN OFFICER INTERVIEWING A CUSTOMER.
    Current Step: $_currentStep.
    
    The interview flow is:
    1. Language selection (Completed after this turn)
    2. Full Name
    3. Employment type (Are they Salaried, Self-employed, or a Business owner?)
    4. Monthly Salary/Income
    5. Loan Purpose (Home, Personal, Vehicle, Education?)
    6. Loan Amount required
    7. Repayment tenure (How many years/months?)
    8. Done

    INSTRUCTIONS:
    - If the user provides a logical answer (e.g., 'My name is Sriram'), set 'valid': true.
    - If the user picked Hindi, yours questions MUST be in Hindi.
    - Ask ONLY ONE question at a time.
    - Be polite but professional.

    RETURN JSON ONLY:
    {
      "valid": true,
      "next_question": "Your next professional question",
      "language_code": "en-IN or hi-IN" (Step 1 only)
    }
    """;

    try {
      final res = await http.post(
        Uri.parse("https://api.groq.com/openai/v1/chat/completions"),
        headers: {"Authorization": "Bearer $groqKey", "Content-Type": "application/json"},
        body: jsonEncode({
          "model": "llama-3.1-8b-instant",
          "response_format": {"type": "json_object"},
          "messages": [{"role": "system", "content": prompt}, {"role": "user", "content": input}]
        }),
      );

      final data = jsonDecode(jsonDecode(res.body)['choices'][0]['message']['content']);
      if (_currentStep == 1) _selectedLang = data['language_code'] ?? "en-IN";

      if (data['valid'] == true) {
        _currentStep++;
        if (_currentStep >= 8) {
          _communicate(_selectedLang == "hi-IN" ? "धन्यवाद। आपका आवेदन जमा हो गया है। आपका दिन शुभ हो!" : "Thank you very much. Your loan application has been successfully submitted for review. Have a professional day!");
          _save();
          Timer(const Duration(seconds: 6), () => context.go('/dashboard'));
        } else {
          _communicate(data['next_question']);
        }
      } else {
        _communicate(_selectedLang == "hi-IN" ? "क्या आप स्पष्ट कर सकते हैं?" : "I apologize, could you clarify that for me?");
      }
    } catch (e) {
       _communicate("Systems are slightly slow. Could we try that again?");
    }
  }

  Future<void> _save() async {
    await Supabase.instance.client.from('kyc').update({
      'status': 'completed',
      'interview_transcript': jsonEncode(_history),
      'completed_at': DateTime.now().toIso8601String(),
    }).eq('kyc_link', widget.token);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Stack(
        children: [
          if (_cam?.value.isInitialized ?? false) Positioned.fill(child: CameraPreview(_cam!)),
          Positioned.fill(child: Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black54, Colors.transparent, Colors.black87])))),
          SafeArea(child: Column(children: [
            Padding(padding: const EdgeInsets.all(24), child: Row(children: [const Icon(Icons.verified, color: Color(0xFF10B981)), const SizedBox(width: 8), const Text("SHOONYA AI OFFICER", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.5))])),
            const Spacer(),
            Container(margin: const EdgeInsets.all(24), padding: const EdgeInsets.all(32), decoration: BoxDecoration(color: const Color(0xFF1E293B).withOpacity(0.9), borderRadius: BorderRadius.circular(32), border: Border.all(color: Colors.white10)), child: Text(_agentText, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600, height: 1.5))),
            Container(padding: const EdgeInsets.fromLTRB(32, 40, 32, 50), decoration: const BoxDecoration(color: Color(0xFF020617), borderRadius: BorderRadius.vertical(top: Radius.circular(40))), child: Column(children: [
              if (_currentWords.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 24), child: Text("HEARING: $_currentWords", textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 16))),
              Container(height: 75, width: double.infinity, decoration: BoxDecoration(color: _isListening ? const Color(0xFF10B981).withOpacity(0.1) : Colors.white10, borderRadius: BorderRadius.circular(37.5), border: Border.all(color: _isListening ? const Color(0xFF10B981) : Colors.white24, width: 2)), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(_isListening ? Icons.mic : Icons.graphic_eq, color: _isListening ? const Color(0xFF10B981) : Colors.white54), const SizedBox(width: 12), Text(_isListening ? "I AM LISTENING..." : "OFFICER SPEAKING", style: TextStyle(color: _isListening ? const Color(0xFF10B981) : Colors.white54, fontWeight: FontWeight.bold, fontSize: 16))]))
            ]))
          ]))
        ],
      ),
    );
  }
}
