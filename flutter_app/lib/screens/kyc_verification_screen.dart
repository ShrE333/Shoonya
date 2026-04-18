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

  // API Config
  final String sarvamKey = "sk_di434scs_TtfMyRDXmfeNRWoTHnFTnWvK";
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

      bool ok = await _speech.initialize(onStatus: (s) => print("STT: $s"), onError: (e) => print("STT ERR: $e"));

      if (ok) {
        Timer(const Duration(seconds: 2), () => _interviewStep());
      } else {
        setState(() => _statusMsg = "STT Initialization Failed");
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

  void _interviewStep() {
    _currentStep = 1;
    _communicate("Welcome to Shoonya. To proceed, please select your language. English or Hindi?");
  }

  Future<void> _communicate(String text) async {
    if (!mounted) return;
    setState(() {
      _agentText = text;
      _isSpeaking = true;
      _history.add({"role": "officer", "text": text});
    });

    try {
      print("TTS: Sending to Sarvam...");
      // Using bulbul:v1 (The specific naming required for v1 API)
      final res = await http.post(
        Uri.parse("https://api.sarvam.ai/v1/text-to-speech"),
        headers: {"api-subscription-key": sarvamKey, "Content-Type": "application/json"},
        body: jsonEncode({
          "text": text,
          "target_language_code": _selectedLang,
          "speaker": _selectedLang == "hi-IN" ? "ritu" : "meera",
          "model": "bulbul:v1" 
        }),
      );

      print("TTS Response: ${res.statusCode}");
      if (res.statusCode == 200) {
        final b64 = jsonDecode(res.body)['audios'][0];
        final bytes = base64Decode(b64);
        await _player.play(BytesSource(Uint8List.fromList(bytes)));
        _player.onPlayerComplete.first.then((_) {
          if (mounted) {
            setState(() => _isSpeaking = false);
            _listenMic();
          }
        });
      } else {
        setState(() => _statusMsg = "Voice Error ${res.statusCode}: Check Key/Model");
        print("SARVAM ERROR BODY: ${res.body}");
        setState(() => _isSpeaking = false);
        _listenMic();
      }
    } catch (e) {
      setState(() => _statusMsg = "Connection Timeout");
      setState(() => _isSpeaking = false);
      _listenMic();
    }
  }

  Future<void> _listenMic() async {
    if (!mounted) return;
    await _speech.stop();
    await Future.delayed(const Duration(milliseconds: 300));

    setState(() {
      _isListening = true;
      _currentWords = "";
    });

    await _speech.listen(
      onResult: (val) {
        setState(() => _currentWords = val.recognizedWords);
        if (val.finalResult) {
          _onHeard(val.recognizedWords);
        }
      },
      localeId: _selectedLang,
      listenFor: const Duration(seconds: 10),
      pauseFor: const Duration(seconds: 4),
    );
  }

  void _onHeard(String text) {
    if (!_isListening) return;
    setState(() => _isListening = false);
    
    if (text.trim().isEmpty) {
      _communicate("I'm sorry, I didn't catch that. Could you repeat?");
      return;
    }

    setState(() => _history.add({"role": "user", "text": text}));
    _processBrain(text);
  }

  Future<void> _processBrain(String input) async {
    if (!mounted) return;
    setState(() => _agentText = "Processing...");
    
    final prompt = """Bank Officer role. Step: $_currentStep. 
    Steps: 1:Lang, 2:Name, 3:Job, 4:Salary, 5:Reason, 6:Amount, 7:Time, 8:Done.
    Return JSON ONLY: {"valid": true, "next": "Polite question", "lang": "en-IN"}""";

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
          _communicate("Thank you. Your loan application is now complete. You can exit now.");
          _saveData();
          Timer(const Duration(seconds: 5), () => context.go('/dashboard'));
        } else {
          _communicate(data['next']);
        }
      } else {
        _communicate("Could you please provide that information again?");
      }
    } catch (e) {
       _communicate("Technical error. Let's try once more.");
    }
  }

  Future<void> _saveData() async {
    await Supabase.instance.client.from('kyc').update({
      'status': 'completed',
      'interview_transcript': jsonEncode(_history),
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
          
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Row(children: [
                    const Icon(Icons.verified_user, color: Color(0xFF10B981)),
                    const SizedBox(width: 8),
                    const Text("SHOONYA AI KYC", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1, fontSize: 12)),
                  ]),
                ),
                const Spacer(),
                
                if (_statusMsg.isNotEmpty) Container(margin: const EdgeInsets.symmetric(horizontal: 24), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.red.withOpacity(0.8), borderRadius: BorderRadius.circular(16)), child: Text(_statusMsg, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))),
                
                Container(
                  margin: const EdgeInsets.all(24),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(color: const Color(0xFF1E293B).withOpacity(0.95), borderRadius: BorderRadius.circular(28), border: Border.all(color: Colors.white10)),
                  child: Text(_agentText, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600, height: 1.4)),
                ),

                Container(
                  padding: const EdgeInsets.fromLTRB(24, 40, 24, 40),
                  decoration: const BoxDecoration(color: Color(0xFF020617), borderRadius: BorderRadius.vertical(top: Radius.circular(40))),
                  child: Column(
                    children: [
                      if (_currentWords.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 24), child: Text("HEARING: $_currentWords", textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF10B981), fontSize: 15, fontWeight: FontWeight.bold))),
                      Container(
                        height: 70,
                        width: double.infinity,
                        decoration: BoxDecoration(color: _isListening ? const Color(0xFF10B981).withOpacity(0.1) : Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(35), border: Border.all(color: _isListening ? const Color(0xFF10B981) : Colors.white10, width: 2)),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                             Icon(_isListening ? Icons.mic : Icons.voice_over_off, color: _isListening ? const Color(0xFF10B981) : Colors.white54),
                            const SizedBox(width: 12),
                            Text(_isListening ? "LISTENING..." : (_isSpeaking ? "AI IS SPEAKING..." : "READY"), style: TextStyle(color: _isListening ? const Color(0xFF10B981) : Colors.white54, fontWeight: FontWeight.bold)),
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
