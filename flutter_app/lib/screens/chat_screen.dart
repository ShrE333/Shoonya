import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final List<Map<String, String>> _messages = [];
  bool _isLoading = false;
  final String groqKey = const String.fromEnvironment('GROQ_API_KEY');

  @override
  void initState() {
    super.initState();
    _messages.add({
      "role": "assistant",
      "text": "Hello! I'm your Shoonya Banking Assistant. How can I help you with your loan or application today?"
    });
  }

  Future<void> _sendMessage() async {
    if (_controller.text.trim().isEmpty) return;
    final userText = _controller.text.trim();
    _controller.clear();

    setState(() {
      _messages.add({"role": "user", "text": userText});
      _isLoading = true;
    });

    try {
      final prompt = """You are the Shoonya AI Banking Expert.
      SHOONYA SOFTWARE INFO:
      - We provide AI-powered instant loan sanctioning.
      - Our verification is done via a Voice AI Interview (bulbul:v3).
      - Users can see their status in the 'Hub' and documents in the 'Vault'.
      
      BANKING PRODUCTS:
      - Personal Loans (12% interest), Home Loans (8.5%), Vehicle Loans (10%).
      - Repayment tenure from 6 months up to 20 years.
      - Documents are DOB-protected.
      
      User is asking: $userText""";

      final res = await http.post(
        Uri.parse("https://api.groq.com/openai/v1/chat/completions"),
        headers: {"Authorization": "Bearer $groqKey", "Content-Type": "application/json"},
        body: jsonEncode({
          "model": "llama-3.1-8b-instant",
          "messages": [{"role": "system", "content": prompt}, ..._messages.map((m) => {"role": m['role'], "content": m['text']})],
        }),
      );

      final aiText = jsonDecode(res.body)['choices'][0]['message']['content'];
      setState(() {
        _messages.add({"role": "assistant", "text": aiText});
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _messages.add({"role": "assistant", "text": "I'm having trouble connecting to Shoonya servers. Please try again later."});
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text("SHOONYA ASSISTANT", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 12)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final m = _messages[index];
                final isUser = m['role'] == 'user';
                return Align(
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                    decoration: BoxDecoration(
                      color: isUser ? const Color(0xFF10B981) : const Color(0xFF1E293B),
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(20),
                        topRight: const Radius.circular(20),
                        bottomLeft: Radius.circular(isUser ? 20 : 0),
                        bottomRight: Radius.circular(isUser ? 0 : 20),
                      ),
                      boxShadow: [if (isUser) BoxShadow(color: const Color(0xFF10B981).withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))]
                    ),
                    child: Text(m['text']!, style: TextStyle(color: isUser ? Colors.black : Colors.white, fontWeight: isUser ? FontWeight.w600 : FontWeight.normal)),
                  ),
                );
              },
            ),
          ),
          if (_isLoading) const Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(color: Color(0xFF10B981), strokeWidth: 2)),
          _buildInput(),
        ],
      ),
    );
  }

  Widget _buildInput() {
    return Container(
      padding: const EdgeInsets.all(20),
      color: const Color(0xFF020617),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: "Ask about your loan...",
                hintStyle: const TextStyle(color: Colors.white24),
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: _sendMessage,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle),
              child: const Icon(Icons.send_rounded, color: Colors.black, size: 24),
            ),
          )
        ],
      ),
    );
  }
}
