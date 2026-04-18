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
  String _agentText = "Starting Shoonya AI...";
  String _selectedLang = "en-IN";
  String _currentWords = "";
  final List<Map<String, String>> _history = [];
  String _errorMsg = "";

  // API Config
  final String sarvamKey = "sk_di434scs_TtfMyRDXmfeNRWoTHnFTnWvK";
  final String groqKey = const String.fromEnvironment('GROQ_API_KEY');

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      await [Permission.microphone, Permission.camera].request();
      
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.speech());
      await session.setActive(true);

      final cameras = await availableCameras();
      final front = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.front, orElse: () => cameras.first);
      _cam = CameraController(front, ResolutionPreset.medium, enableAudio: false);
      await _cam!.initialize();
      
      if (mounted) setState(() {});

      bool hasSTT = await _speech.initialize(
        onStatus: (s) => print("STT: $s"),
        onError: (e) => setState(() => _errorMsg = "STT Error: ${e.errorMsg}"),
      );

      if (hasSTT) {
        Timer(const Duration(seconds: 2), () => _run());
      } else {
        setState(() => _errorMsg = "Speech Engine Busy.");
      }
    } catch (e) {
      setState(() => _errorMsg = "Boot failed: $e");
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
    _talk("Welcome to Shoonya. I'm your AI bank officer. Which language shall we use for today's interview? English or Hindi?");
  }

  Future<void> _talk(String text) async {
    if (!mounted) return;
    setState(() {
      _agentText = text;
      _isSpeaking = true;
      _history.add({"role": "officer", "text": text});
      _errorMsg = "";
    });

    try {
      print("TTS: Calling Sarvam (bulbulv1 + meera)...");
      final res = await http.post(
        Uri.parse("https://api.sarvam.ai/text-to-speech"),
        headers: {"api-subscription-key": sarvamKey, "Content-Type": "application/json"},
        body: jsonEncode({
          "text": text,
          "target_language_code": _selectedLang,
          "speaker": _selectedLang == "hi-IN" ? "ritu" : "meera", // Meera is the most stable English voice
          "model": "bulbulv1" 
        }),
      );

      if (res.statusCode == 200) {
        final b64 = jsonDecode(res.body)['audios'][0];
        final bytes = base64Decode(b64);
        
        await _player.setVolume(1.0);
        await _player.play(BytesSource(Uint8List.fromList(bytes)));
        
        _player.onPlayerComplete.first.then((_) {
          if (mounted) {
            setState(() => _isSpeaking = false);
            _listen();
          }
        });
      } else {
        setState(() => _errorMsg = "Voice Server Error: ${res.statusCode}");
        print("SARVAM_ERR: ${res.body}");
        setState(() => _isSpeaking = false);
        _listen();
      }
    } catch (e) {
      setState(() => _errorMsg = "Connection Error");
      setState(() => _isSpeaking = false);
      _listen();
    }
  }

  Future<void> _listen() async {
    if (!mounted) return;
    // Hard reset of microphone state
    await _speech.stop();
    await Future.delayed(const Duration(milliseconds: 200));

    setState(() {
      _isListening = true;
      _currentWords = "I'm listening...";
    });

    await _speech.listen(
      onResult: (val) {
        setState(() => _currentWords = val.recognizedWords);
        if (val.finalResult) {
          _done(val.recognizedWords);
        }
      },
      localeId: _selectedLang,
      listenFor: const Duration(seconds: 8),
      pauseFor: const Duration(seconds: 4),
    );
  }

  void _done(String text) {
    if (!_isListening) return;
    setState(() {
      _isListening = false;
    });
    
    if (text.trim().isEmpty) {
      _talk("I'm sorry, I missed that. Could you repeat?");
      return;
    }

    setState(() => _history.add({"role": "user", "text": text}));
    _brain(text);
  }

  Future<void> _brain(String input) async {
    if (!mounted) return;
    setState(() => _agentText = "Checking...");
    
    final prompt = """You are a bank manager. Step: $_currentStep. 
    1: Language, 2: Name, 3: Job, 4: Salary, 5: Reason, 6: Amount, 7: Duration, 8: Exit.
    JSON: {"valid": true, "next": "Sentence", "lang": "en-IN"}""";

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

      if (_currentStep == 1) _selectedLang = data['lang'] ?? "en-IN";

      if (data['valid'] == true) {
        _currentStep++;
        if (_currentStep >= 8) {
          _talk("Your application is submitted. Thank you!");
          _save();
          Timer(const Duration(seconds: 5), () => context.go('/dashboard'));
        } else {
          _talk(data['next']);
        }
      } else {
        _talk("Please specify that again?");
      }
    } catch (e) {
       _talk("System glitch. What was that?");
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
      backgroundColor: const Color(0xFF020617),
      body: Stack(
        children: [
          // Background Camera
          if (_cam?.value.isInitialized ?? false) Positioned.fill(child: CameraPreview(_cam!)),
          // Overlay UI
          Positioned.fill(child: Container(color: Colors.black.withOpacity(0.4))),
          
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Row(
                    children: [
                      const Icon(Icons.security, color: Color(0xFF10B981)),
                      const SizedBox(width: 12),
                      const Text("SECURE AI INTERVIEW", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                    ],
                  ),
                ),
                const Spacer(),
                
                // Agent Bubble
                Container(
                  margin: const EdgeInsets.all(24),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(color: const Color(0xFF1E293B).withOpacity(0.9), borderRadius: BorderRadius.circular(32), border: Border.all(color: Colors.white10)),
                  child: Column(
                    children: [
                      if (_errorMsg.isNotEmpty) Container(padding: const EdgeInsets.all(8), margin: const EdgeInsets.only(bottom: 12), decoration: BoxDecoration(color: Colors.red.withOpacity(0.2), borderRadius: BorderRadius.circular(12)), child: Text(_errorMsg, style: const TextStyle(color: Colors.redAccent, fontSize: 12))),
                      Text(_agentText, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w600, height: 1.4)),
                    ],
                  ),
                ),

                // Status Bar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                  decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: const BorderRadius.vertical(top: Radius.circular(40))),
                  child: Column(
                    children: [
                      if (_currentWords.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 20), child: Text( _currentWords, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF10B981), fontSize: 16, fontWeight: FontWeight.w500))),
                      Container(
                        height: 80,
                        width: double.infinity,
                        decoration: BoxDecoration(color: _isListening ? const Color(0xFF10B981).withOpacity(0.1) : Colors.white10, borderRadius: BorderRadius.circular(40), border: Border.all(color: _isListening ? const Color(0xFF10B981) : Colors.white24, width: 2)),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                             Icon(_isListening ? Icons.mic : Icons.speaker_phone, color: _isListening ? const Color(0xFF10B981) : Colors.white54),
                            const SizedBox(width: 16),
                            Text(_isListening ? "I AM LISTENING..." : (_isSpeaking ? "OFFICER IS SPEAKING..." : "SYSTEM READY"), style: TextStyle(color: _isListening ? const Color(0xFF10B981) : Colors.white54, fontWeight: FontWeight.bold, fontSize: 16)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
