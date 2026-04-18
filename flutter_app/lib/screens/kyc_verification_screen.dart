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
import 'package:path_provider/path_provider.dart';
import 'package:go_router/go_router.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path/path.dart' as p;

class KYCVerificationScreen extends StatefulWidget {
  final String token;
  const KYCVerificationScreen({super.key, required this.token});

  @override
  State<KYCVerificationScreen> createState() => _KYCVerificationScreenState();
}

class _KYCVerificationScreenState extends State<KYCVerificationScreen> {
  // Voice Agent State
  final SpeechToText _speech = SpeechToText();
  final AudioPlayer _player = AudioPlayer();
  bool _isSpeaking = false;
  bool _isListening = false;
  int _currentStep = 0;
  List<int> _lastTtsBytes = [];
  String _currentWords = "";
  
  String _selectedLanguage = "en-IN";
  String _agentText = "Initializing interview...";
  final List<Map<String, String>> _transcript = [];

  // API Config
  final String sarvamApiKey = "sk_di434scs_TtfMyRDXmfeNRWoTHnFTnWvK";
  final String groqApiKey = const String.fromEnvironment('GROQ_API_KEY');

  // Camera
  CameraController? _cam;

  @override
  void initState() {
    super.initState();
    _initInterview();
  }

  Future<void> _initInterview() async {
    print("DEBUG: Initializing Native STT Interview...");
    await [Permission.microphone, Permission.camera].request();
    
    bool available = await _speech.initialize(
      onStatus: (status) => print('STT Status: $status'),
      onError: (error) => setState(() => _agentText = "Speech Error: ${error.errorMsg}"),
    );

    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.speech());
    await session.setActive(true);

    await _initCamera();
    if (available) {
      Timer(const Duration(milliseconds: 1500), () => _startFlow());
    } else {
      setState(() => _agentText = "Speech recognition not available on this device.");
    }
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    final frontCam = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.front, orElse: () => cameras.first);
    _cam = CameraController(frontCam, ResolutionPreset.high, enableAudio: false);
    await _cam!.initialize();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _speech.stop();
    _player.dispose();
    _cam?.dispose();
    super.dispose();
  }

  // --- BRAIN: THE FLOW CONTROL ---

  void _startFlow() async {
    await Future.delayed(const Duration(seconds: 2));
    _voicePrompt("Welcome to Shoonya. To get started, please tell me which language you would like to continue in? English or Hindi?");
    _currentStep = 1;
  }

  Future<void> _voicePrompt(String text) async {
    if (!mounted) return;
    setState(() {
      _agentText = text;
      _isSpeaking = true;
      _transcript.add({"role": "officer", "text": text});
    });

    try {
      print("TTS Request (Sarvam v1) for: $text");
      final response = await http.post(
        Uri.parse("https://api.sarvam.ai/v1/text-to-speech"), 
        headers: {"api-subscription-key": sarvamApiKey, "Content-Type": "application/json"},
        body: jsonEncode({
          "text": text,
          "target_language_code": _selectedLanguage,
          "speaker": _selectedLanguage == "hi-IN" ? "ritu" : "shubh",
          "model": "bulbul:v2", // Stable bulbul v2
        }),
      );

      print("TTS Response Status: ${response.statusCode}");
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final base64Audio = data['audios'][0];
        _lastTtsBytes = base64Decode(base64Audio);
        print("Received ${_lastTtsBytes.length} bytes of audio.");

        await _player.setVolume(1.0);
        await _player.play(BytesSource(Uint8List.fromList(_lastTtsBytes)));
        
        StreamSubscription<void>? sub;
        sub = _player.onPlayerComplete.listen((event) {
          sub?.cancel();
          if (mounted) {
            setState(() => _isSpeaking = false);
            _startListening();
          }
        });
      } else {
        print("TTS ERROR BODY: ${response.body}");
        setState(() => _isSpeaking = false);
        _startListening(); 
      }
    } catch (e) {
      print("TTS EXCEPTION: $e");
      setState(() => _isSpeaking = false);
      _startListening();
    }
  }

  Future<void> _startListening() async {
    setState(() {
      _isListening = true;
      _currentWords = "";
    });

    await _speech.listen(
      onResult: (result) {
        setState(() => _currentWords = result.recognizedWords);
        if (result.finalResult) {
          _onSpeechComplete(result.recognizedWords);
        }
      },
      localeId: _selectedLanguage,
      listenFor: const Duration(seconds: 15),
      pauseFor: const Duration(seconds: 5),
    );
  }

  void _onSpeechComplete(String recognizedText) {
    if (!_isListening) return;
    setState(() => _isListening = false);
    
    if (recognizedText.isEmpty) {
      _voicePrompt("I'm sorry, it seems I couldn't hear you clearly. Could you please repeat that?");
      return;
    }

    setState(() => _transcript.add({"role": "user", "text": recognizedText}));
    _decideNextStep(recognizedText);
  }

  Future<void> _decideNextStep(String userText) async {
    setState(() => _agentText = "Updating records...");
    print("Logic Input: Step $_currentStep | User: $userText");

    String systemPrompt = """
    You are a professional bank manager. 
    Interview Step: $_currentStep.
    User input: '$userText'.
    
    Goal: Advance through these steps:
    1: Language Selection
    2: Name
    3: Job/Business (Employment)
    4: Monthly Income (Salary)
    5: Loan Category (Personal/Education/Home)
    6: Required Loan Amount
    7: Repayment Duration
    8: Done (Exit)

    RULES:
    - If user says a clear answer (like '50000 rupees' for income), mark 'valid': true.
    - BE FRIENDLY. If user picked Hindi, answer in Hindi using NATURAL banking phrases.
    - ALWAYS return a FULL, POLITE professional sentence for 'next_question'.

    Return ONLY JSON:
    {
      "valid": true,
      "extracted_data": "string value",
      "next_question": "Natural professional banking sentence",
      "language": "hi-IN or en-IN" (Step 1 only)
    }
    """;

    try {
      final response = await http.post(
        Uri.parse("https://api.groq.com/openai/v1/chat/completions"),
        headers: {"Authorization": "Bearer $groqApiKey", "Content-Type": "application/json"},
        body: jsonEncode({
          "model": "llama-3.1-8b-instant",
          "response_format": {"type": "json_object"},
          "messages": [{"role": "system", "content": systemPrompt}, {"role": "user", "content": userText}]
        }),
      );

      final decoded = jsonDecode(response.body);
      final rawContent = decoded['choices'][0]['message']['content'];
      print("Groq Intelligence: $rawContent");
      
      final result = jsonDecode(rawContent);

      if (_currentStep == 1) {
        _selectedLanguage = result['language'] ?? "en-IN";
        _currentStep = 2;
        _voicePrompt(result['next_question']);
      } else {
        if (result['valid'] == true) {
          _currentStep++;
          if (_currentStep >= 8) {
            _voicePrompt("Thank you very much. Your application is officially submitted. You can now close the interview.");
            _saveToSupabase();
            Timer(const Duration(seconds: 5), () => context.go('/dashboard'));
          } else {
            _voicePrompt(result['next_question']);
          }
        } else {
          _voicePrompt("I'm sorry, I need that information specifically. Could you please clarify?");
        }
      }
    } catch (e) {
      print("Logic Exception: $e");
      _voicePrompt("I had a minor technical glitch. Let's continue. What was that again?");
    }
  }

  Future<void> _saveToSupabase() async {
    final supabase = Supabase.instance.client;
    await supabase.from('kyc').update({
      'status': 'completed',
      'interview_transcript': jsonEncode(_transcript),
      'completed_at': DateTime.now().toIso8601String(),
    }).eq('kyc_link', widget.token);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Column(
          children: [
            Container(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12), child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("AI LOAN OFFICER", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
                if (_lastTtsBytes.isNotEmpty) IconButton(onPressed: () => _player.play(BytesSource(Uint8List.fromList(_lastTtsBytes))), icon: const Icon(Icons.volume_up, color: Color(0xFF10B981))),
              ],
            )),
            Expanded(
              flex: 4,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white10)),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Stack(
                    children: [
                      if (_cam?.value.isInitialized ?? false) Positioned.fill(child: CameraPreview(_cam!)),
                      Center(child: Container(width: 200, height: 260, decoration: BoxDecoration(border: Border.all(color: _isListening ? const Color(0xFF10B981) : Colors.white24, width: 2), borderRadius: BorderRadius.circular(100)))),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Container(
                margin: const EdgeInsets.all(24),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(24)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("BANKING LINE - STEP $_currentStep/8", style: const TextStyle(fontSize: 10, color: Colors.white54, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _transcript.length,
                        itemBuilder: (context, i) {
                          final msg = _transcript[i];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: Text("${msg['role']!.toUpperCase()}: ${msg['text']}", style: TextStyle(color: msg['role'] == 'officer' ? const Color(0xFF10B981) : Colors.white70, fontSize: 13)),
                          );
                        },
                      ),
                    ),
                    if (_isListening && _currentWords.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text("HEARING: $_currentWords", style: const TextStyle(color: Color(0xFF10B981), fontSize: 12, fontStyle: FontStyle.italic)),
                      ),
                  ],
                ),
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              height: 70,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(35), color: _isListening ? const Color(0xFF10B981).withOpacity(0.1) : Colors.white.withOpacity(0.05), border: Border.all(color: _isListening ? const Color(0xFF10B981) : Colors.white10)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                   Icon(_isListening ? Icons.mic : Icons.graphic_eq, color: _isListening ? const Color(0xFF10B981) : Colors.white54),
                  const SizedBox(width: 12),
                  Text(_isListening ? "I AM LISTENING..." : (_isSpeaking ? "AGENT IS SPEAKING..." : "INITIALIZING..."), style: TextStyle(color: _isListening ? const Color(0xFF10B981) : Colors.white54, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
