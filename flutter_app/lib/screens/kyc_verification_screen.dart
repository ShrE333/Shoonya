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
  // Engines
  final SpeechToText _speech = SpeechToText();
  final AudioPlayer _player = AudioPlayer();
  CameraController? _cam;
  
  // State
  bool _isSpeaking = false;
  bool _isListening = false;
  int _currentStep = 0;
  List<int> _audioBytes = [];
  String _currentWords = "";
  String _agentText = "Starting Shoonya AI...";
  String _selectedLang = "en-IN";
  final List<Map<String, String>> _history = [];

  // API Config (Strictly bulbulv2 as requested)
  final String sarvamKey = "sk_di434scs_TtfMyRDXmfeNRWoTHnFTnWvK";
  final String groqKey = const String.fromEnvironment('GROQ_API_KEY');

  @override
  void initState() {
    super.initState();
    _bootSystem();
  }

  Future<void> _bootSystem() async {
    print("BOOT: Requesting Permissions...");
    await [Permission.microphone, Permission.camera].request();

    print("BOOT: Initializing Audio Session...");
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music()); // High-quality speaker focus
    await session.setActive(true);

    print("BOOT: Initializing Camera...");
    final cameras = await availableCameras();
    final front = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.front, orElse: () => cameras.first);
    _cam = CameraController(front, ResolutionPreset.medium, enableAudio: false);
    await _cam!.initialize();
    if (mounted) setState(() {});

    print("BOOT: Initializing Speech Engine...");
    bool hasSTT = await _speech.initialize(
      onStatus: (s) => print("STT_STATUS: $s"),
      onError: (e) => print("STT_ERROR: $e"),
    );

    if (hasSTT) {
      Timer(const Duration(seconds: 1), () => _runInterview());
    } else {
      setState(() => _agentText = "Speech Engine Error. Please check permissions.");
    }
  }

  @override
  void dispose() {
    _speech.cancel();
    _player.dispose();
    _cam?.dispose();
    super.dispose();
  }

  // --- INTERVIEW FLOW ---

  void _runInterview() {
    _currentStep = 1;
    _promptAgent("Welcome to Shoonya. I'm your AI officer. Which language shall we use for today's loan interview? English or Hindi?");
  }

  Future<void> _promptAgent(String text) async {
    if (!mounted) return;
    setState(() {
      _agentText = text;
      _isSpeaking = true;
      _history.add({"role": "officer", "text": text});
    });

    try {
      print("TTS: Calling Sarvam (bulbulv2) for '$text'");
      final res = await http.post(
        Uri.parse("https://api.sarvam.ai/text-to-speech"),
        headers: {"api-subscription-key": sarvamKey, "Content-Type": "application/json"},
        body: jsonEncode({
          "text": text,
          "target_language_code": _selectedLang,
          "speaker": _selectedLang == "hi-IN" ? "ritu" : "shubh",
          "model": "bulbulv2" // STRICT: No colon as requested
        }),
      );

      if (res.statusCode == 200) {
        final b64 = jsonDecode(res.body)['audios'][0];
        _audioBytes = base64Decode(b64);
        print("TTS: Audio Ready (${_audioBytes.length} bytes)");

        await _player.play(BytesSource(Uint8List.fromList(_audioBytes)));
        
        _player.onPlayerComplete.first.then((_) {
          if (mounted) {
            setState(() => _isSpeaking = false);
            _listenUser();
          }
        });
      } else {
        print("TTS_ERROR: ${res.statusCode} -> ${res.body}");
        setState(() => _isSpeaking = false);
        _listenUser(); // Fallback to listening even if silent
      }
    } catch (e) {
      print("TTS_EXCEPTION: $e");
      setState(() => _isSpeaking = false);
      _listenUser();
    }
  }

  Future<void> _listenUser() async {
    if (_speech.isListening) return;
    
    setState(() {
      _isListening = true;
      _currentWords = "";
    });

    print("STT: Listening for result...");
    await _speech.listen(
      onResult: (val) {
        setState(() => _currentWords = val.recognizedWords);
        if (val.finalResult) {
          print("STT: Final Result: ${val.recognizedWords}");
          _handleUserResponse(val.recognizedWords);
        }
      },
      localeId: _selectedLang,
      listenFor: const Duration(seconds: 10),
      pauseFor: const Duration(seconds: 3),
    );
  }

  void _handleUserResponse(String text) {
    if (!_isListening) return;
    setState(() => _isListening = false);
    
    if (text.trim().isEmpty) {
      _promptAgent("I apologize, I didn't hear that. Could you say it again?");
      return;
    }

    setState(() => _history.add({"role": "user", "text": text}));
    _askBrain(text);
  }

  Future<void> _askBrain(String input) async {
    setState(() => _agentText = "Verifying...");
    
    final sys = """You are a bank officer. Step: $_currentStep. 
    1: Language, 2: Name, 3: Job, 4: Salary, 5: Reason, 6: Amount, 7: Duration, 8: Exit.
    Return JSON ONLY: {"valid": true, "next_question": "Full sentence", "lang": "en-IN/hi-IN"}""";

    try {
      final res = await http.post(
        Uri.parse("https://api.groq.com/openai/v1/chat/completions"),
        headers: {"Authorization": "Bearer $groqKey", "Content-Type": "application/json"},
        body: jsonEncode({
          "model": "llama-3.1-8b-instant",
          "response_format": {"type": "json_object"},
          "messages": [{"role": "system", "content": sys}, {"role": "user", "content": input}]
        }),
      );

      final data = jsonDecode(jsonDecode(res.body)['choices'][0]['message']['content']);
      print("BRAIN: Decision -> $data");

      if (_currentStep == 1) {
        _selectedLang = data['lang'] ?? "en-IN";
      }

      if (data['valid'] == true) {
        _currentStep++;
        if (_currentStep >= 8) {
          _promptAgent("Thank you. Your loan request is recorded. Goodbye.");
          _save();
          Timer(const Duration(seconds: 4), () => context.go('/dashboard'));
        } else {
          _promptAgent(data['next_question']);
        }
      } else {
        _promptAgent("Could you please specify that detail clearly?");
      }
    } catch (e) {
       _promptAgent("Minor connection issue. Let's try that again?");
    }
  }

  Future<void> _save() async {
    await Supabase.instance.client.from('kyc').update({
      'status': 'completed',
      'interview_transcript': jsonEncode(_history),
    }).eq('kyc_link', widget.token);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Column(
        children: [
          Expanded(flex: 5, child: Stack(children: [
            if (_cam?.value.isInitialized ?? false) Positioned.fill(child: CameraPreview(_cam!)),
            Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black54, Colors.transparent, Colors.black87]))),
            Positioned(top: 50, left: 24, child: Text("AI LOAN OFFICER", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 2))),
            Center(child: Container(width: 220, height: 280, decoration: BoxDecoration(border: Border.all(color: _isListening ? const Color(0xFF10B981) : Colors.white24, width: 2), borderRadius: BorderRadius.circular(110)))),
          ])),
          Expanded(flex: 4, child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
            child: Column(children: [
              Text(_agentText, textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w500)),
              const Spacer(),
              if (_currentWords.isNotEmpty) Text("YOU SAID: $_currentWords", style: TextStyle(color: const Color(0xFF10B981), fontSize: 14, fontStyle: FontStyle.italic)),
              const Spacer(),
              Container(
                height: 80,
                width: double.infinity,
                decoration: BoxDecoration(color: _isListening ? const Color(0xFF10B981).withOpacity(0.1) : Colors.white10, borderRadius: BorderRadius.circular(40), border: Border.all(color: _isListening ? const Color(0xFF10B981) : Colors.white24)),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(_isListening ? Icons.mic : Icons.graphic_eq, color: _isListening ? const Color(0xFF10B981) : Colors.white54),
                  const SizedBox(width: 12),
                  Text(_isListening ? "LISTENING..." : (_isSpeaking ? "OFFICER SPEAKING..." : "READY"), style: TextStyle(color: _isListening ? const Color(0xFF10B981) : Colors.white54, fontWeight: FontWeight.bold)),
                ]),
              )
            ]),
          ))
        ],
      ),
    );
  }
}
