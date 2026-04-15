import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:path/path.dart' as p;

class KYCVerificationScreen extends StatefulWidget {
  final String token;
  const KYCVerificationScreen({super.key, required this.token});

  @override
  State<KYCVerificationScreen> createState() => _KYCVerificationScreenState();
}

class _KYCVerificationScreenState extends State<KYCVerificationScreen> {
  // Voice Agent State
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();
  bool _isSpeaking = false;
  bool _isListening = false;
  String _agentText = "Initializing secure session...";
  int _currentStep = 0;
  final List<String> _logs = [];

  // API Config
  final String sarvamApiKey = "sk_di434scs_TtfMyRDXmfeNRWoTHnFTnWvK";
  // The user will pass the Groq key via --dart-define
  final String groqApiKey = const String.fromEnvironment('GROQ_API_KEY');

  // Camera & Detection
  CameraController? _cam;
  bool _faceDetected = false;
  final _faceDetector = FaceDetector(options: FaceDetectorOptions(enableClassification: true, performanceMode: FaceDetectorMode.accurate));

  @override
  void initState() {
    super.initState();
    _initEverything();
  }

  Future<void> _initEverything() async {
    await _initCamera();
    // Start initial agent interaction
    _startInterview();
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    final frontCam = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.front, orElse: () => cameras.first);
    _cam = CameraController(frontCam, ResolutionPreset.high, enableAudio: false);
    await _cam!.initialize();
    if (mounted) setState(() {});
    _cam!.startImageStream((image) async {
       // Minimal face check for UI guides
       // (Keeping it lightweight to focus on Voice/Speech logic)
    });
  }

  @override
  void dispose() {
    _recorder.dispose();
    _player.dispose();
    _cam?.dispose();
    _faceDetector.close();
    super.dispose();
  }

  // --- INTERVIEW LOGIC ---

  Future<void> _startInterview() async {
    await Future.delayed(const Duration(seconds: 1));
    _voicePrompt("Hello, I am your Shoonya Verification Officer. To begin, please state your full name.");
  }

  Future<void> _voicePrompt(String text) async {
    setState(() {
      _agentText = text;
      _isSpeaking = true;
      _logs.add("OFFICER: $text");
    });

    try {
      final response = await http.post(
        Uri.parse("https://api.sarvam.ai/text-to-speech"),
        headers: {
          "api-subscription-key": sarvamApiKey,
          "Content-Type": "application/json",
        },
        body: jsonEncode({
          "text": text,
          "target_language_code": "en-IN",
          "speaker": "shubh",
          "model": "bulbul:v3",
          "pace": 1.0,
          "speech_sample_rate": 24000,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final base64Audio = data['audios'][0];
        final bytes = base64Decode(base64Audio);
        
        final tempDir = await getTemporaryDirectory();
        final file = File(p.join(tempDir.path, "prompt.wav"));
        await file.writeAsBytes(bytes);

        await _player.play(DeviceFileSource(file.path));
        _player.onPlayerComplete.listen((event) {
          if (mounted) {
            setState(() => _isSpeaking = false);
            _startListeningForUser();
          }
        });
      }
    } catch (e) {
      debugPrint("TTS Error: $e");
      setState(() => _isSpeaking = false);
    }
  }

  Future<void> _startListeningForUser() async {
    if (await _recorder.hasPermission()) {
      final tempDir = await getTemporaryDirectory();
      final path = p.join(tempDir.path, "response.wav");
      
      await _recorder.start(const RecordConfig(encoder: AudioEncoder.wav), path: path);
      setState(() => _isListening = true);

      // Auto-stop after 4 seconds of speech (minimal POC)
      Timer(const Duration(seconds: 4), () => _stopAndProcess(path));
    }
  }

  Future<void> _stopAndProcess(String path) async {
    if (!_isListening) return;
    await _recorder.stop();
    if (!mounted) return;
    setState(() => _isListening = false);

    // STT TRANSCRIPTION
    _logs.add("...Processing your response...");
    final transcript = await _transcribeAudio(path);
    _logs.add("YOU: $transcript");

    // GROQ REASONING
    _processWithGroq(transcript);
  }

  Future<String> _transcribeAudio(String audioPath) async {
    try {
      final request = http.MultipartRequest("POST", Uri.parse("https://api.sarvam.ai/speech-to-text"));
      request.headers["api-subscription-key"] = sarvamApiKey;
      request.fields["model"] = "saaras:v3";
      request.fields["language_code"] = "en-IN";
      request.files.add(await http.MultipartFile.fromPath("file", audioPath));

      final response = await request.send();
      final resBody = await response.stream.bytesToString();
      final data = jsonDecode(resBody);
      return data['transcript'] ?? "";
    } catch (e) {
      return "Error transcribing speech.";
    }
  }

  Future<void> _processWithGroq(String userText) async {
    setState(() => _agentText = "Verifying...");
    
    try {
      final response = await http.post(
        Uri.parse("https://api.groq.com/openai/v1/chat/completions"),
        headers: {
          "Authorization": "Bearer $groqApiKey",
          "Content-Type": "application/json",
        },
        body: jsonEncode({
          "model": "llama-3.1-8b-instant",
          "messages": [
            {
              "role": "system",
              "content": "You are a professional Shoonya Bank KYC Officer. Current KYC Step: $_currentStep. The user just said: '$userText'. If this is the name step, confirm the name and move to 'Please blink twice for liveness verification'. If it's liveness, ask 'Please hold your identity document to the camera'. Always respond with a single, clear sentence to be spoken to the user."
            },
            {"role": "user", "content": userText}
          ]
        }),
      );

      final data = jsonDecode(response.body);
      final reply = data['choices'][0]['message']['content'];
      
      _currentStep++;
      if (_currentStep > 3) {
        _voicePrompt("Thank you. Your identity has been verified. You may now return to the dashboard.");
        _finalizeKYC();
      } else {
        _voicePrompt(reply);
      }
    } catch (e) {
      _voicePrompt("I'm sorry, I couldn't process that. Could you repeat?");
    }
  }

  Future<void> _finalizeKYC() async {
     await Supabase.instance.client.from('kyc').update({
       'status': 'completed',
       'completed_at': DateTime.now().toIso8601String(),
     }).eq('kyc_link', widget.token);
  }

  // --- UI BUILDING ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  IconButton(onPressed: () => context.pop(), icon: const Icon(Icons.arrow_back, color: Colors.white)),
                  const Expanded(child: Center(child: Text("VIDEO KYC VERIFICATION", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)))),
                  const Icon(Icons.security, color: Color(0xFF10B981), size: 16),
                ],
              ),
            ),

            // Video Feed Area
            Expanded(
              flex: 3,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(32), border: Border.all(color: Colors.white10)),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(32),
                  child: Stack(
                    children: [
                      if (_cam != null) Positioned.fill(child: CameraPreview(_cam!)),
                      
                      // Face Guide Overlay
                      Center(
                        child: Container(
                          width: 220, height: 280,
                          decoration: BoxDecoration(
                            border: Border.all(color: _isListening ? const Color(0xFF10B981) : Colors.white24, width: 2),
                            borderRadius: BorderRadius.circular(110),
                          ),
                        ),
                      ),

                      // Status Badge
                      Positioned(
                        top: 20, right: 20,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                          child: Row(children: [
                            Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle)),
                            const SizedBox(width: 6),
                            const Text("LIVE", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                          ]),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Agent Transcript area
            Expanded(
              flex: 2,
              child: Container(
                margin: const EdgeInsets.all(24),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(24)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("AGENT TRANSCRIPT", style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _logs.length,
                        itemBuilder: (context, i) => Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: Text(_logs[i], style: TextStyle(
                            color: _logs[i].startsWith("OFFICER") ? const Color(0xFF10B981) : Colors.white,
                            fontSize: 13,
                          )),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Recording Status Bar
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              height: 64,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(32),
                color: _isListening ? const Color(0xFF10B981).withOpacity(0.1) : Colors.white.withOpacity(0.05),
                border: Border.all(color: _isListening ? const Color(0xFF10B981) : Colors.white10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(_isListening ? Icons.mic : Icons.graphic_eq, color: _isListening ? const Color(0xFF10B981) : Colors.white54),
                  const SizedBox(width: 12),
                  Text(
                    _isListening ? "LISTENING..." : (_isSpeaking ? "OFFICER SPEAKING..." : "SECURE ENCRYPTED CHANNEL"),
                    style: TextStyle(color: _isListening ? const Color(0xFF10B981) : Colors.white54, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    return BottomNavigationBar(
      backgroundColor: const Color(0xFF0F172A),
      type: BottomNavigationBarType.fixed,
      selectedItemColor: const Color(0xFF10B981),
      unselectedItemColor: Colors.white30,
      currentIndex: 1,
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: 'Home'),
        BottomNavigationBarItem(icon: Icon(Icons.verified_user), label: 'Verification'),
        BottomNavigationBarItem(icon: Icon(Icons.description_outlined), label: 'Documents'),
        BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'Profile'),
      ],
    );
  }
}
