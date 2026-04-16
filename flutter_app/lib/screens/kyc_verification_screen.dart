import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
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
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();
  bool _isSpeaking = false;
  bool _isListening = false;
  int _currentStep = 0; // 0: Init, 1: Language...
  String _lastRecordingPath = "";
  
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
    await [Permission.microphone, Permission.camera].request();
    await _initCamera();
    _startFlow();
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
    _recorder.dispose();
    _player.dispose();
    _cam?.dispose();
    super.dispose();
  }

  // --- BRAIN: THE FLOW CONTROL ---

  void _startFlow() async {
    await Future.delayed(const Duration(seconds: 2));
    _voicePrompt("Welcome to Shoonya. Please tell me which language you would like to continue in? English or Hindi?");
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
      debugPrint("TTS Request for: $text");
      final response = await http.post(
        Uri.parse("https://api.sarvam.ai/text-to-speech"), 
        headers: {"api-subscription-key": sarvamApiKey, "Content-Type": "application/json"},
        body: jsonEncode({
          "text": text,
          "target_language_code": _selectedLanguage,
          "speaker": _selectedLanguage == "hi-IN" ? "ritu" : "shubh",
          "model": "bulbul:v3",
        }),
      );

      debugPrint("TTS Status: ${response.statusCode}");
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final base64Audio = data['audios'][0];
        final bytes = base64Decode(base64Audio);
        final tempDir = await getTemporaryDirectory();
        final file = File(p.join(tempDir.path, "prompt_${DateTime.now().millisecondsSinceEpoch}.wav"));
        await file.writeAsBytes(bytes);

        await _player.play(DeviceFileSource(file.path));
        _player.onPlayerComplete.listen((event) {
          if (mounted) {
            setState(() => _isSpeaking = false);
            _startListening();
          }
        });
      } else {
        debugPrint("TTS ERROR BODY: ${response.body}");
        setState(() => _isSpeaking = false);
        _startListening();
      }
    } catch (e) {
      debugPrint("TTS EXCEPTION: $e");
      setState(() => _isSpeaking = false);
      _startListening();
    }
  }

  Future<void> _startListening() async {
    if (await _recorder.hasPermission()) {
      final tempDir = await getTemporaryDirectory();
      final path = p.join(tempDir.path, "user_res_${DateTime.now().millisecondsSinceEpoch}.m4a");
      _lastRecordingPath = path;
      
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc), 
        path: path
      );
      setState(() => _isListening = true);
      
      // Auto-stop after 10 seconds
      Timer(const Duration(seconds: 10), () {
        if (_isListening) _processUserResponse(path);
      });
    }
  }

  Future<void> _processUserResponse(String path) async {
    if (!_isListening) return;
    await _recorder.stop();
    if (!mounted) return;
    setState(() => _isListening = false);

    final file = File(path);
    if (await file.exists()) {
      debugPrint("Audio captured! Size: ${await file.length()} bytes");
    }

    final transcript = await _stt(path);
    if (!mounted) return;
    setState(() => _transcript.add({"role": "user", "text": transcript}));
    _decideNextStep(transcript);
  }

  Future<String> _stt(String audioPath) async {
    try {
      debugPrint("STT Request for: $audioPath");
      final request = http.MultipartRequest("POST", Uri.parse("https://api.sarvam.ai/speech-to-text"));
      request.headers["api-subscription-key"] = sarvamApiKey;
      
      request.fields["model"] = "saaras:v3";
      request.fields["language_code"] = _currentStep <= 1 ? "unknown" : _selectedLanguage; 
      request.fields["mode"] = "transcribe";

      request.files.add(await http.MultipartFile.fromPath(
        "file", 
        audioPath,
        contentType: MediaType("audio", "aac"),
      ));

      final response = await request.send();
      final resBody = await response.stream.bytesToString();
      debugPrint("STT RAW RESPONSE: $resBody");
      
      final data = jsonDecode(resBody);
      return data['transcript'] ?? "";
    } catch (e) { 
      debugPrint("STT ERROR LOG: $e");
      return ""; 
    }
  }

  Future<void> _decideNextStep(String userText) async {
    setState(() => _agentText = "Processing...");

    String prompt = "";
    if (_currentStep == 1) {
      prompt = "Detect if the user wants English or Hindi. Return ONLY the JSON: {'language': 'hi-IN' or 'en-IN', 'next_question': 'Thank you. Please tell me your full name.'}";
    } else {
      prompt = "You are verifying a loan interview answer. Question was Step $_currentStep. User said: '$userText'. Identify the next question. Next questions are: 3:Work details (Job/Business), 4:Salary, 5:Loan Type, 6:Amount, 7:Timeline, 8:Done. Return JSON: {'valid': true, 'data': 'extracted value', 'next_question': 'The next question text'}";
    }

    try {
      final response = await http.post(
        Uri.parse("https://api.groq.com/openai/v1/chat/completions"),
        headers: {"Authorization": "Bearer $groqApiKey", "Content-Type": "application/json"},
        body: jsonEncode({
          "model": "llama-3.1-8b-instant",
          "response_format": {"type": "json_object"},
          "messages": [{"role": "system", "content": prompt}, {"role": "user", "content": userText}]
        }),
      );

      final result = jsonDecode(jsonDecode(response.body)['choices'][0]['message']['content']);

      if (_currentStep == 1) {
        _selectedLanguage = result['language'];
        _currentStep = 2;
        _voicePrompt(result['next_question']);
      } else {
        if (result['valid'] == true) {
          _currentStep++;
          if (_currentStep >= 8) {
            _voicePrompt("Thank you for your time. Your loan application is now under review. Goodbye.");
            _saveToSupabase();
            Timer(const Duration(seconds: 5), () => context.go('/dashboard'));
          } else {
            _voicePrompt(result['next_question']);
          }
        } else {
          _voicePrompt("I'm sorry, I didn't quite catch that. Could you please repeat?");
        }
      }
    } catch (e) {
      _voicePrompt("Technology glitch. Let's try that again.");
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
            Container(padding: const EdgeInsets.all(24), child: const Center(child: Text("AI LOAN INTERVIEW OFFICER", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)))),
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
                    Text("ACTIVE TRANSCRIPT - STEP $_currentStep/8", style: const TextStyle(fontSize: 10, color: Colors.white54, fontWeight: FontWeight.bold)),
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
                  ],
                ),
              ),
            ),
            GestureDetector(
              onTap: () { if (_isListening) _processUserResponse(_lastRecordingPath); },
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                height: 70,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(35), color: _isListening ? const Color(0xFF10B981).withOpacity(0.1) : Colors.white.withOpacity(0.05), border: Border.all(color: _isListening ? const Color(0xFF10B981) : Colors.white10)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(_isListening ? Icons.mic : Icons.graphic_eq, color: _isListening ? const Color(0xFF10B981) : Colors.white54),
                    const SizedBox(width: 12),
                    Text(_isListening ? "LISTENING (TAP TO SUBMIT)" : (_isSpeaking ? "OFFICER SPEAKING..." : "SECURE LINE ACTIVE"), style: TextStyle(color: _isListening ? const Color(0xFF10B981) : Colors.white54, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
