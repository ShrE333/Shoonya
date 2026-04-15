import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'dart:typed_data';

enum KYCStage { permissions, scanning, capturing, uploading, done }

class KYCVerificationScreen extends StatefulWidget {
  final String token;
  const KYCVerificationScreen({super.key, required this.token});

  @override
  State<KYCVerificationScreen> createState() => _KYCVerificationScreenState();
}

class _KYCVerificationScreenState extends State<KYCVerificationScreen> {
  KYCStage _stage = KYCStage.permissions;
  CameraController? _cam;
  final _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true,
      enableLandmarks: true,
      performanceMode: FaceDetectorMode.accurate,
    ),
  );
  int _blinkCount = 0;
  double? _lastLeftEye;
  bool _faceDetected = false;
  bool _isProcessing = false;
  String _userName = "Authenticating...";
  int _seconds = 135; // 02:15 mock timer

  @override
  void initState() {
    super.initState();
    _fetchUserName();
    _requestAll();
    Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() => _seconds++);
    });
  }

  Future<void> _fetchUserName() async {
    try {
      final supabase = Supabase.instance.client;
      final kyc = await supabase.from('kyc').select('profiles(full_name)').eq('kyc_link', widget.token).single();
      setState(() => _userName = (kyc['profiles']['full_name'] ?? 'USER').toUpperCase());
    } catch (e) {
      setState(() => _userName = "VERIFICATION ONGOING");
    }
  }

  @override
  void dispose() {
    _cam?.dispose();
    _faceDetector.close();
    super.dispose();
  }

  Future<void> _requestAll() async {
    final statuses = await [
      Permission.camera,
      Permission.microphone,
      Permission.location,
    ].request();

    if (statuses[Permission.camera]!.isGranted) {
      await _initCamera();
      setState(() => _stage = KYCStage.scanning);
    }
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    final frontCam = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.front, orElse: () => cameras.first);
    _cam = CameraController(frontCam, ResolutionPreset.high, enableAudio: false);
    await _cam!.initialize();
    _cam!.startImageStream(_processCameraImage);
  }

  void _processCameraImage(CameraImage image) async {
    if (_isProcessing) return;
    _isProcessing = true;
    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();
      final Size imageSize = Size(image.width.toDouble(), image.height.toDouble());
      final camera = _cam!.description;
      final imageRotation = InputImageRotationValue.fromRawValue(camera.sensorOrientation) ?? InputImageRotation.rotation0deg;
      final inputImageFormat = InputImageFormatValue.fromRawValue(image.format.raw) ?? InputImageFormat.nv21;
      
      final inputImageData = InputImageMetadata(
        size: imageSize,
        rotation: imageRotation,
        format: inputImageFormat,
        bytesPerRow: image.planes[0].bytesPerRow,
      );
      
      final inputImage = InputImage.fromBytes(bytes: bytes, metadata: inputImageData);
      final faces = await _faceDetector.processImage(inputImage);
      
      if (faces.isEmpty) {
        setState(() => _faceDetected = false);
        return;
      }

      setState(() => _faceDetected = true);
      final face = faces.first;
      final leftEye = face.leftEyeOpenProbability ?? 1.0;

      if (_lastLeftEye != null && _lastLeftEye! > 0.7 && leftEye < 0.3) {
        _blinkCount++;
      }
      _lastLeftEye = leftEye;

      if (_blinkCount >= 2) {
        _cam!.stopImageStream();
        setState(() => _stage = KYCStage.capturing);
        _captureAndUpload();
      }
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _captureAndUpload() async {
    final photo = await _cam!.takePicture();
    final bytes = await photo.readAsBytes();
    Position? pos;
    try { pos = await Geolocator.getCurrentPosition(); } catch(e){}

    final supabase = Supabase.instance.client;
    final kyc = await supabase.from('kyc').select().eq('kyc_link', widget.token).single();
    final userId = kyc['user_id'];
    final path = 'kyc-selfies/$userId/selfie.jpg';
    
    await supabase.storage.from('kyc-assets').uploadBinary(path, bytes);
    final selfieUrl = supabase.storage.from('kyc-assets').getPublicUrl(path);

    await supabase.from('kyc').update({
      'status': 'completed',
      'selfie_url': selfieUrl,
      'location_lat': pos?.latitude,
      'location_lng': pos?.longitude,
      'completed_at': DateTime.now().toIso8601String(),
    }).eq('kyc_link', widget.token);
    
    setState(() => _stage = KYCStage.done);
  }

  String _formatTimer(int s) {
    int m = s ~/ 60;
    int r = s % 60;
    return '${m.toString().padLeft(2, '0')}:${r.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('VIDEO KYC VERIFICATION', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: const Icon(Icons.arrow_back),
      ),
      body: _stage == KYCStage.done ? _buildDone() : _buildInterface(),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildInterface() {
    return Column(
      children: [
        // Progress Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            children: [
              LinearProgressIndicator(
                value: 0.75,
                backgroundColor: Colors.white10,
                color: const Color(0xFF10B981).withOpacity(0.8),
                borderRadius: BorderRadius.circular(10),
                minHeight: 8,
              ),
              const SizedBox(height: 12),
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(children: [
                    Icon(Icons.check_circle, color: const Color(0xFF10B981), size: 16),
                    SizedBox(width: 4),
                    Text('Document Upload', style: TextStyle(color: const Color(0xFF10B981), fontSize: 12)),
                  ]),
                  Text('Step 3 of 4: Video Interview', style: TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Camera Frame
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white10, width: 1),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Stack(
                children: [
                  if (_cam?.value.isInitialized ?? false) Positioned.fill(child: CameraPreview(_cam!))
                  else Container(color: Colors.black),
                  
                  // Label Overlay
                  Positioned(
                    top: 0, left: 0, right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black.withOpacity(0.6), Colors.transparent])),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('VIDEO KYC: $_userName', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white)),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: const Color(0xFF10B981).withOpacity(0.2), borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFF10B981).withOpacity(0.4))),
                            child: const Text('ONLINE & VERIFIED', style: TextStyle(color: const Color(0xFF10B981), fontSize: 8, fontWeight: FontWeight.bold)),
                          )
                        ],
                      ),
                    ),
                  ),

                  // Guides
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Face Guide
                        Container(
                          width: 180, height: 230,
                          decoration: BoxDecoration(
                            border: Border.all(color: _faceDetected ? const Color(0xFF10B981) : Colors.white24, width: 2),
                            borderRadius: BorderRadius.circular(100),
                            boxShadow: _faceDetected ? [BoxShadow(color: const Color(0xFF10B981).withOpacity(0.2), blurRadius: 20, spreadRadius: 2)] : [],
                          ),
                        ),
                        const SizedBox(height: 20),
                        // ID Card Guide
                        Container(
                          width: 200, height: 120,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white24, width: 1),
                            borderRadius: BorderRadius.circular(12),
                            color: Colors.white.withOpacity(0.05),
                          ),
                          child: const Center(child: Icon(Icons.credit_card, color: Colors.white24, size: 32)),
                        ),
                      ],
                    ),
                  ),

                  // Recording Controls
                  Positioned(
                    top: 50, left: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                      child: Row(children: [
                        Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        const Text('REC', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                      ]),
                    ),
                  ),
                  Positioned(
                    top: 50, right: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                      child: Text(_formatTimer(_seconds), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Transcription Area
        Container(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(16)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _transcriptLine('10:48 AM', 'Agent', 'Please hold your Aadhaar card clearly.'),
              const SizedBox(height: 8),
              _transcriptLine('10:49 AM', _userName.toLowerCase(), 'Yes, is this clear enough?'),
              const SizedBox(height: 8),
              _transcriptLine('10:49 AM', 'Agent', 'Perfect. Now blink twice for liveness.'),
            ],
          ),
        ),

        // Status Button
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: const Color(0xFF10B981).withOpacity(0.5)),
            color: const Color(0xFF10B981).withOpacity(0.05),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.graphic_eq, color: const Color(0xFF10B981)),
              const SizedBox(width: 12),
              Text('RECORDING INITIATED — ${_blinkCount}/2 BLINKS', style: const TextStyle(color: const Color(0xFF10B981), fontWeight: FontWeight.bold, letterSpacing: 0.5)),
            ],
          ),
        ),

        // Control Row
        Padding(
          padding: const EdgeInsets.all(24.0),
          child: Row(
            children: [
              _bottomButton(Icons.chat_outlined, 'CHAT'),
              const SizedBox(width: 12),
              _bottomButton(Icons.help_outline, 'HELP'),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  height: 50,
                  decoration: BoxDecoration(color: Colors.red.withOpacity(0.8), borderRadius: BorderRadius.circular(12)),
                  child: const Center(child: Text('END CALL', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDone() {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.check_circle, color: const Color(0xFF10B981), size: 80),
      const SizedBox(height: 24),
      const Text('KYC VERIFIED SUCCESSFULLY', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      const Text('Application redirected to dashboard', style: TextStyle(color: Colors.white54)),
      const SizedBox(height: 48),
      ElevatedButton(onPressed: () => context.go('/dashboard'), child: const Text('Go to Dashboard')),
    ]));
  }

  Widget _transcriptLine(String time, String author, String text) {
    return RichText(text: TextSpan(style: const TextStyle(fontSize: 11, color: Colors.white38), children: [
      TextSpan(text: '$time: ', style: const TextStyle(color: const Color(0xFF10B981))),
      TextSpan(text: '$author: ', style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.bold)),
      TextSpan(text: text),
    ]));
  }

  Widget _bottomButton(IconData icon, String label) {
    return Container(
      width: 90, height: 50,
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white10)),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: 16, color: Colors.white70),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
      ]),
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
