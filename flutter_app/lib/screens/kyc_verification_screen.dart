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
  int _currentStep = 0;
  String _agentText = "Initializng Bank Security...";
  String _currentWords = "";
  final List<Map<String, String>> _transcript = [];
  String _dobForPassword = "";

  // BANK SCRIPT 2.0 (Including external debt check)
  final List<String> _questionBank = [
    "Welcome to Shoonya. I'm your AI bank officer. May I know your full name starting with your first name?",
    "Thank you. Please tell me your date of birth?",
    "Perfect. What is your current employment type? Salaried, or Business owner?",
    "To calculate your limit, what is your average monthly income after tax?",
    "Do you have any existing loans from other banks? If yes, what is the monthly EMI amount?", // NEW QUESTION
    "Which loan product are you applying for? Personal, Home, or Vehicle?",
    "What is the specific loan amount you require?",
    "Over what period would you like to repay this loan? (e.g., 2 years)",
    "I have all your details. I am now creating your loan application and generating your audit report. Please wait."
  ];

  final String sarvamKey = "sk_w9w5soy4_f4o4tZcMjnW8VDDFkRV0Os1Q";
  final String groqKey = const String.fromEnvironment('GROQ_API_KEY');

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    await [Permission.microphone, Permission.camera].request();
    _cam = CameraController((await availableCameras()).firstWhere((c) => c.lensDirection == CameraLensDirection.front), ResolutionPreset.medium);
    await _cam!.initialize();
    await _speech.initialize();
    if (mounted) setState(() {});
    Timer(const Duration(seconds: 2), () => _step());
  }

  @override
  void dispose() {
    _speech.cancel(); _player.dispose(); _cam?.dispose();
    super.dispose();
  }

  void _step() {
    if (_isAnalyzing) return;
    if (_currentStep < _questionBank.length) {
      _speak(_questionBank[_currentStep]);
    } else {
      _finalize();
    }
  }

  Future<void> _speak(String text) async {
    if (!mounted) return;
    setState(() { _agentText = text; _isSpeaking = true; _transcript.add({"role": "officer", "text": text}); });
    try {
      final res = await http.post(Uri.parse("https://api.sarvam.ai/text-to-speech"),
        headers: {"api-subscription-key": sarvamKey, "Content-Type": "application/json"},
        body: jsonEncode({"text": text, "target_language_code": "en-IN", "speaker": "shubh", "model": "bulbul:v3", "pace": 1.0, "speech_sample_rate": 24000}));
      if (res.statusCode == 200) {
        await _player.play(BytesSource(base64Decode(jsonDecode(res.body)['audios'][0])));
        _player.onPlayerComplete.first.then((_) {
          if (mounted) {
            setState(() => _isSpeaking = false);
            if (_currentStep < _questionBank.length - 1) _listen();
            else _finalize();
          }
        });
      } else { setState(() => _isSpeaking = false); if (_currentStep < _questionBank.length - 1) _listen(); }
    } catch (e) { setState(() => _isSpeaking = false); }
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
        if (_currentStep == 1) _dobForPassword = val.recognizedWords.replaceAll(RegExp(r'[^0-9]'), '');
        _currentStep++;
        _step();
      }
    }, localeId: "en-IN");
  }

  Future<void> _finalize() async {
    if (_isAnalyzing) return;
    setState(() { _isAnalyzing = true; _agentText = "Submitting Loan Application..."; });

    final transcriptText = _transcript.map((m) => "${m['role']}: ${m['text']}").join("\n");
    final prompt = """Analyze and return LOAN JSON: $transcriptText. JSON: {"status":"Approved/Rejected","loan_amount":0,"type":"Personal","interest_rate":0,"tenure":0,"emi":0,"risk":"Low/Med/High","reason":"string"}""";

    try {
      final res = await http.post(Uri.parse("https://api.groq.com/openai/v1/chat/completions"),
        headers: {"Authorization": "Bearer $groqKey", "Content-Type": "application/json"},
        body: jsonEncode({"model": "llama-3.1-8b-instant", "messages": [{"role": "system", "content": "Return Loan JSON only."}, {"role": "user", "content": prompt}], "response_format": {"type": "json_object"}}));

      final analysis = jsonDecode(jsonDecode(res.body)['choices'][0]['message']['content']);
      final user = Supabase.instance.client.auth.currentUser;

      if (user != null) {
        // 1. Update Profile (KYC Verified)
        await Supabase.instance.client.from('profiles').update({'loan_limit': analysis['loan_amount'], 'kyc_status': 'verified'}).eq('id', user.id);
        
        // 2. CREATE AUTOMATIC LOAN RECORD (As requested!)
        await Supabase.instance.client.from('loans').insert({
          'user_id': user.id,
          'amount_requested': analysis['loan_amount'],
          'loan_type': analysis['type'],
          'status': 'pending', // Will be approved by admin
          'analysis_data': analysis
        });

        await _createAuditPDF(analysis, user.id);
      }
      Timer(const Duration(seconds: 4), () => context.go('/dashboard'));
    } catch (e) { context.go('/dashboard'); }
  }

  Future<void> _createAuditPDF(Map<String, dynamic> data, String userId) async {
    final pdf = pw.Document();
    pdf.addPage(pw.Page(build: (c) => pw.Center(child: pw.Text("Shoonya Loan Report: ${data['type']} - Amount: ₹${data['loan_amount']} - Status: ${data['status']}"))));
    final file = File("${(await getApplicationDocumentsDirectory()).path}/report.pdf");
    await file.writeAsBytes(await pdf.save());
    await Supabase.instance.client.storage.from('documents').upload('$userId/report.pdf', file, fileOptions: const FileOptions(upsert: true));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      body: Stack(children: [
        if (_cam?.value.isInitialized ?? false) Positioned.fill(child: CameraPreview(_cam!)),
        Positioned.fill(child: Container(color: Colors.black54)),
        SafeArea(child: Column(children: [
          Padding(padding: const EdgeInsets.all(24), child: const Text("SHOONYA AI OFFICER", style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, letterSpacing: 2))),
          const Spacer(),
          Container(margin: const EdgeInsets.all(24), padding: const EdgeInsets.all(32), decoration: BoxDecoration(color: const Color(0xFF1E293B).withOpacity(0.9), borderRadius: BorderRadius.circular(32)), child: Text(_agentText, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600))),
          if (_currentWords.isNotEmpty) Text(_currentWords, style: const TextStyle(color: Color(0xFF10B981))),
          const SizedBox(height: 32),
          Container(height: 100, width: double.infinity, decoration: const BoxDecoration(color: Color(0xFF0F172A), borderRadius: BorderRadius.vertical(top: Radius.circular(50))), child: Center(child: Text(_isListening ? "LISTENING..." : "SPEAKING", style: const TextStyle(color: Colors.white24, fontWeight: FontWeight.bold))))
        ]))
      ])
    );
  }
}
