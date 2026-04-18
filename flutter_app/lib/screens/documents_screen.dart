import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({super.key});

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  final _supabase = Supabase.instance.client;
  List<FileObject>? _files;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchFiles();
  }

  Future<void> _fetchFiles() async {
    final user = _supabase.auth.currentUser;
    if (user != null) {
      try {
        final data = await _supabase.storage.from('documents').list(path: user.id);
        setState(() {
          _files = data;
          _isLoading = false;
        });
      } catch (e) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text("SECURE CO vault", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 16)),
        backgroundColor: const Color(0xFF0F172A),
        centerTitle: true,
        elevation: 0,
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: Color(0xFF10B981)))
        : (_files == null || _files!.isEmpty)
          ? _buildEmptyState()
          : ListView.builder(
              padding: const EdgeInsets.all(24),
              itemCount: _files!.length,
              itemBuilder: (context, index) {
                final file = _files![index];
                return _buildFileTile(file);
              },
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder_off_outlined, size: 64, color: Colors.white10),
          const SizedBox(height: 16),
          const Text("VAULT IS EMPTY", style: TextStyle(color: Colors.white24, fontWeight: FontWeight.bold, letterSpacing: 1)),
          const Text("Complete KYC to generate reports", style: TextStyle(color: Colors.white10, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildFileTile(FileObject file) {
    final bool isPdf = file.name.toLowerCase().endsWith('.pdf');
    final String path = '${_supabase.auth.currentUser!.id}/${file.name}';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.05))
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: (isPdf ? Colors.redAccent : Colors.blueAccent).withOpacity(0.1), 
              borderRadius: BorderRadius.circular(16)
            ),
            child: Icon(isPdf ? Icons.picture_as_pdf : Icons.image_search_outlined, color: isPdf ? Colors.redAccent : Colors.blueAccent, size: 24),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(file.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14), overflow: TextOverflow.ellipsis),
                Text(DateFormat('dd MMM yyyy').format(DateTime.tryParse(file.updatedAt ?? file.createdAt ?? '') ?? DateTime.now()), style: const TextStyle(color: Colors.white24, fontSize: 11)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.open_in_new_rounded, color: Color(0xFF10B981)),
            onPressed: () async {
              try {
                final String url = await _supabase.storage.from('documents').createSignedUrl(path, 600);
                final Uri uri = Uri.parse(url);
                
                // FORCE LAUNCH: Some Android builds fail the canLaunch check
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Cloud access denied. Check folder: $path"), backgroundColor: Colors.redAccent));
                }
              }
            },
          )
        ],
      ),
    );
  }
}
