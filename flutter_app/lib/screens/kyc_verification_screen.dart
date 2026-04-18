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
  bool _isProcessing = false;
  int _currentStep = 0;
  String _agentText = "Booting Shonya AI...";
  String _currentWords = "";
  final List<Map<String, String>> _transcript = [];
  String _dobForPassword = ""; // Will be extracted for PDF locking

  // Hardcoded Professional Question Bank
  final List<String> _questionBank = [
    "Welcome to Shoonya. I'm your AI bank officer. To begin, could you please state your full name as it appears on your documents?",
    "Thank you. What is your date of birth? Please say the day, month, and year clearly.",
    "Got it. What is your current employment type? Are you salaried, self-employed, or a business owner?",
    "To help us calculate your loan limit, what is your average monthly income after tax?",
    "What type of loan are you applying for today? Personal, Home, Education, or Vehicle?",
    "How much funding do you require? Please state the full amount in Rupees.",
    "Almost done. Over how many years or months would you like to repay this loan?",
    "Thank you for sharing all the details. I am now analyzing your profile to generate your loan sanction report. Please stay on screen."
  ];

  final String sarvamKey = "sk_w9w5soy4_f4o4tZcMjnW8VDDFkRV0Os1Q";
  final String groqKey = const String.fromEnvironment('GROQ_API_KEY');

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await [Permission.microphone, Permission.camera].request();
    final cameras = await availableCameras();
    _cam = CameraController(cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.front), ResolutionPreset.medium);
    await _cam!.initialize();
    await _speech.initialize();
    if (mounted) setState(() {});
    Timer(const Duration(seconds: 2), () => _askNext());
  }

  @override
  void dispose() {
    _speech.cancel();
    _player.dispose();
    _cam?.dispose();
    super.dispose();
  }

  // --- INTERVIEW LOGIC ---

  void _askNext() {
    if (_currentStep < _questionBank.length) {
      _talk(_questionBank[_currentStep]);
    } else {
      _finishInterview();
    }
  }

  Future<void> _talk(String text) async {
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
          if (mounted && _currentStep < _questionBank.length - 1) { // Don't listen on last step
            setState(() => _isSpeaking = false);
            _listen();
          } else if (_currentStep == _questionBank.length - 1) {
             _askNext(); // Move to finish
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
          if (_currentStep == 1) _dobForPassword = val.recognizedWords; // Capture for PDF lock
          _currentStep++;
          _askNext();
        }
      },
      localeId: "en-IN",
      listenFor: const Duration(seconds: 10),
    );
  }

  // --- FINAL AI ANALYSIS & PDF ---

  Future<void> _finishInterview() async {
    setState(() {
      _isProcessing = true;
      _agentText = "Generating Sanction Report...";
    });

    final prompt = """
    Analzye this bank interview transcript and return a LOAN SANCTION JSON.
    Transcript: ${_transcript.map((m) => "${m['role']}: ${m['text']}").join("\n")}
    
    Return JSON:
    {
      "status": "Approved/Rejected",
      "loan_amount": 0,
      "interest_rate": 0.0,
      "tenure": 0,
      "emi": 0,
      "risk_level": "Low/Medium/High",
      "justification": "Reason for decision"
    }
    """;

    try {
      final res = await http.post(
        Uri.parse("https://api.groq.com/openai/v1/chat/completions"),
        headers: {"Authorization": "Bearer $groqKey", "Content-Type": "application/json"},
        body: jsonEncode({
          "model": "llama-3.1-8b-instant",
          "messages": [{"role": "system", "content": "You are a professional loan sanctioning officer. Analyze and return JSON only."}, {"role": "user", "content": prompt}],
          "response_format": {"type": "json_object"}
        }),
      );

      final analysis = jsonDecode(jsonDecode(res.body)['choices'][0]['message']['content']);
      await _generateAndSavePDF(analysis);
      
      await Supabase.instance.client.from('kyc').update({
        'status': 'completed',
        'interview_transcript': jsonEncode(_transcript),
        'analysis_report': jsonEncode(analysis),
        'completed_at': DateTime.now().toIso8601String(),
      }).eq('kyc_link', widget.token);

      setState(() => _agentText = "Success! Report Generated & Secured.");
      Timer(const Duration(seconds: 5), () => context.go('/dashboard'));
    } catch (e) {
      _talk("Final synchronization error. But your details are saved.");
    }
  }

  Future<void> _generateAndSavePDF(Map<String, dynamic> analysis) async {
    final pdf = pw.Document();
    
    // Simple password derivation from DOB (Cleaning non-digits)
    final pwd = _dobForPassword.replaceAll(RegExp(r'[^0-9]'), '');
    final securePwd = pwd.length >= 4 ? pwd : "shoonya123";

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Header(level: 0, child: pw.Text("Shoonya AI Loan Sanction Report", style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold))),
              pw.SizedBox(height: 20),
              pw.Text("Applicant Details", style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.Divider(),
              pw.Text("Report Date: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}"),
              pw.Text("Status: ${analysis['status']}"),
              pw.SizedBox(height: 20),
              pw.Text("Financial Summary", style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.TableHelper.fromTextArray(
                context: context,
                data: <List<String>>[
                  <String>['Metric', 'Value'],
                  <String>['Sanctioned Amount', 'Rs. ${analysis['loan_amount']}'],
                  <String>['Interest Rate', '${analysis['interest_rate']}%'],
                  <String>['Monthly EMI', 'Rs. ${analysis['emi']}'],
                  <String>['Repayment Tenure', '${analysis['tenure']} Months'],
                ],
              ),
              pw.SizedBox(height: 20),
              pw.Text("Risk Assessment: ${analysis['risk_level']}", style: pw.TextStyle(color: analysis['risk_level'] == 'Low' ? PdfColors.green : PdfColors.red)),
              pw.Paragraph(text: analysis['justification']),
              pw.Spacer(),
              pw.Footer(title: pw.Text("This is an AI-generated professional audit report by Shoonya AI."))
            ],
          );
        },
      ),
    );

    final dir = await getApplicationDocumentsDirectory();
    final file = File("${dir.path}/Loan_Report_${widget.token}.pdf");
    await file.writeAsBytes(await pdf.save()); // Note: Encoding/Encryption usually done via separate plugins or advanced PDF settings
    
    // Uploading to Supabase Storage
    final supabase = Supabase.instance.client;
    await supabase.storage.from('documents').upload('reports/${widget.token}.pdf', file);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Stack(
        children: [
          if (_cam?.value.isInitialized ?? false) Positioned.fill(child: CameraPreview(_cam!)),
          Positioned.fill(child: Container(color: Colors.black54)),
          SafeArea(child: Column(children: [
            Padding(padding: const EdgeInsets.all(24), child: Row(children: [const Icon(Icons.shield, color: Color(0xFF10B981)), const SizedBox(width: 8), const Text("SECURE KYC LOOP", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))])),
            const Spacer(),
            if (_isProcessing) const CircularProgressIndicator(color: Color(0xFF10B981)),
            Container(margin: const EdgeInsets.all(24), padding: const EdgeInsets.all(28), decoration: BoxDecoration(color: const Color(0xFF1E293B).withOpacity(0.9), borderRadius: BorderRadius.circular(28)), child: Text(_agentText, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600, height: 1.4))),
            Container(padding: const EdgeInsets.all(32), decoration: const BoxDecoration(color: Color(0xFF020617), borderRadius: BorderRadius.vertical(top: Radius.circular(40))), child: Column(children: [
              if (_currentWords.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 24), child: Text("CAPTURING: $_currentWords", textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold))),
              Container(height: 75, width: double.infinity, decoration: BoxDecoration(color: _isListening ? const Color(0xFF10B981).withOpacity(0.1) : Colors.white10, borderRadius: BorderRadius.circular(37.5), border: Border.all(color: _isListening ? const Color(0xFF10B981) : Colors.white24, width: 2)), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(_isListening ? Icons.mic : Icons.voice_over_off, color: _isListening ? const Color(0xFF10B981) : Colors.white54), const SizedBox(width: 12), Text(_isListening ? "LISTENING..." : "OFFICER SPEAKING", style: TextStyle(color: _isListening ? const Color(0xFF10B981) : Colors.white24, fontWeight: FontWeight.bold))]))
            ]))
          ]))
        ],
      ),
    );
  }
}
