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
  bool _isAnalyzing = false; // Strictly prevents repetition
  int _currentStep = 0;
  String _agentText = "Initializing Secure Environment...";
  String _currentWords = "";
  final List<Map<String, String>> _transcript = [];
  String _dobForPassword = "";

  final List<String> _questionBank = [
    "Welcome to Shoonya. I'm your AI bank officer. May I know your full name for the record?",
    "Thank you. To lock your profile, please clearly state your date of birth?",
    "Perfect. What is your current employment type? Salaried, or Business owner?",
    "Next, what is your average monthly income after all taxes?",
    "Which loan product are you interested in today? Personal, Home, or Vehicle?",
    "What is the specific loan amount you are applying for in Rupees?",
    "Finally, over what period would you like to repay this loan? For example, 3 years or 5 years?",
    "I have captured all the necessary data. I am now analyzing your response to generate your sanction report. Please remain on screen for a moment."
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
    _cam = CameraController(cams.firstWhere((c) => c.lensDirection == CameraLensDirection.front), ResolutionPreset.medium);
    await _cam!.initialize();
    await _speech.initialize();
    if (mounted) setState(() {});
    Timer(const Duration(seconds: 2), () => _step());
  }

  @override
  void dispose() {
    _speech.cancel();
    _player.dispose();
    _cam?.dispose();
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
    setState(() {
      _agentText = text;
      _isSpeaking = true;
      _transcript.add({"role": "officer", "text": text});
    });

    try {
      final res = await http.post(
        Uri.parse("https://api.sarvam.ai/text-to-speech"),
        headers: {"api-subscription-key": sarvamKey, "Content-Type": "application/json"},
        body: jsonEncode({
          "text": text,
          "target_language_code": "en-IN",
          "speaker": "shubh",
          "model": "bulbul:v3",
          "pace": 1.0,
          "speech_sample_rate": 24000
        }),
      );

      if (res.statusCode == 200) {
        await _player.play(BytesSource(base64Decode(jsonDecode(res.body)['audios'][0])));
        _player.onPlayerComplete.first.then((_) {
          if (mounted) {
            setState(() => _isSpeaking = false);
            // ONLY listen if it's NOT the final "Processing" line!
            if (_currentStep < _questionBank.length - 1) {
              _listen();
            } else {
              _finalize(); // Move directly to analysis if it was the last line
            }
          }
        });
      } else {
        setState(() => _isSpeaking = false);
        if (_currentStep < _questionBank.length - 1) _listen();
      }
    } catch (e) {
      setState(() => _isSpeaking = false);
    }
  }

  Future<void> _listen() async {
    if (!mounted) return;
    await _speech.stop();
    setState(() { _isListening = true; _currentWords = ""; });
    await _speech.listen(
      onResult: (val) {
        setState(() => _currentWords = val.recognizedWords);
        if (val.finalResult) {
          setState(() => _isListening = false);
          _transcript.add({"role": "user", "text": val.recognizedWords});
          if (_currentStep == 1) _dobForPassword = val.recognizedWords.replaceAll(RegExp(r'[^0-9]'), '');
          _currentStep++;
          _step();
        }
      },
      localeId: "en-IN",
      listenFor: const Duration(seconds: 10),
    );
  }

  Future<void> _finalize() async {
    if (_isAnalyzing) return;
    setState(() { 
      _isAnalyzing = true; 
      _agentText = "Generating Final Audit...";
    });

    final prompt = """Analyze and return LOAN JSON: ${_transcript.map((m) => "${m['role']}: ${m['text']}").join("\n")}
    JSON: {"status":"Approved/Rejected","loan_amount":0,"interest_rate":0,"tenure":0,"emi":0,"risk":"Low/Med/High","reason":"string"}""";

    try {
      final res = await http.post(
        Uri.parse("https://api.groq.com/openai/v1/chat/completions"),
        headers: {"Authorization": "Bearer $groqKey", "Content-Type": "application/json"},
        body: jsonEncode({
          "model": "llama-3.1-8b-instant",
          "messages": [{"role": "system", "content": "Return Loan Analysis JSON only."}, {"role": "user", "content": prompt}],
          "response_format": {"type": "json_object"}
        }),
      );

      final analysis = jsonDecode(jsonDecode(res.body)['choices'][0]['message']['content']);
      
      // Save to Database
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        await Supabase.instance.client.from('profiles').update({
          'loan_limit': analysis['loan_amount'],
          'kyc_status': 'verified',
          'last_kyc_data': analysis
        }).eq('id', user.id);
      }

      await _createPDF(analysis);
      
      Timer(const Duration(seconds: 4), () => context.go('/dashboard'));
    } catch (e) {
      context.go('/dashboard');
    }
  }

  Future<void> _createPDF(Map<String, dynamic> data) async {
    final pdf = pw.Document();
    pdf.addPage(pw.Page(build: (c) => pw.Center(child: pw.Text("Shoonya Loan Sanction: ${data['status']} - Approved Limit: ₹${data['loan_amount']}"))));
    final dir = await getApplicationDocumentsDirectory();
    final file = File("${dir.path}/report.pdf");
    await file.writeAsBytes(await pdf.save());
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
       await Supabase.instance.client.storage.from('documents').upload('${user.id}/sanction_report.pdf', file, fileOptions: const FileOptions(upsert: true));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Stack(
        children: [
          // Background Camera (Glass Effect)
          if (_cam?.value.isInitialized ?? false) Positioned.fill(child: CameraPreview(_cam!)),
          Positioned.fill(child: Container(decoration: BoxDecoration(color: Colors.black.withOpacity(0.5)))),
          
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("SHOONYA AI", style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, letterSpacing: 2, fontSize: 10)),
                          const Text("VERIFICATION LOOP", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
                        ],
                      ),
                      Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.security, color: Colors.white54, size: 20)),
                    ],
                  ),
                ),
                const Spacer(),
                
                // GLASS BUBBLE
                Container(
                  margin: const EdgeInsets.all(24),
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(40),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                    boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 40, offset: const Offset(0, 10))]
                  ),
                  child: Column(
                    children: [
                      if (_isAnalyzing) const Padding(padding: EdgeInsets.only(bottom: 20), child: LinearProgressIndicator(backgroundColor: Colors.white10, color: Color(0xFF10B981))),
                      Text(_agentText, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w600, height: 1.5, letterSpacing: -0.5)),
                    ],
                  ),
                ),

                // CAPTIONING
                if (_currentWords.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(horizontal: 40), child: Text(_currentWords, textAlign: TextAlign.center, style: TextStyle(color: const Color(0xFF10B981).withOpacity(0.8), fontSize: 16, fontWeight: FontWeight.w500, fontStyle: FontStyle.italic))),
                const SizedBox(height: 32),

                // FOOTER STATUS
                Container(
                  height: 100,
                  width: double.infinity,
                  decoration: const BoxDecoration(color: Color(0xFF020617), borderRadius: BorderRadius.vertical(top: Radius.circular(50))),
                  child: Center(
                    child: Container(
                      height: 60,
                      width: 250,
                      decoration: BoxDecoration(
                        color: _isListening ? const Color(0xFF10B981).withOpacity(0.1) : Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: _isListening ? const Color(0xFF10B981) : Colors.white10, width: 2)
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(_isListening ? Icons.mic : Icons.speaker_notes, color: _isListening ? const Color(0xFF10B981) : Colors.white30),
                          const SizedBox(width: 12),
                          Text(_isListening ? "LISTENING..." : "OFFICER SPEAKING", style: TextStyle(color: _isListening ? const Color(0xFF10B981) : Colors.white38, fontWeight: FontWeight.w800, fontSize: 14)),
                        ],
                      ),
                    ),
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
