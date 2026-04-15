import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:flutter_chat_types/flutter_chat_types.dart' as types;

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<types.Message> _messages = [];
  final _user = const types.User(id: 'user');
  final _ai = const types.User(id: 'ai', firstName: 'Shoonya Assistant');
  final _supabase = Supabase.instance.client;

  // Move credentials to environment definitions
  final String groqApiKey = const String.fromEnvironment('GROQ_API_KEY');

  @override
  void initState() {
    super.initState();
    _messages.add(
      types.TextMessage(
        author: _ai,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        id: 'welcome',
        text: 'Hi there! 👋 I am your Shoonya Loan Assistant. How can I help you today?',
      ),
    );
  }

  void _addMessage(types.Message message) {
    setState(() {
      _messages.insert(0, message);
    });
  }

  Future<void> _handleSendPressed(types.PartialText message) async {
    final textMessage = types.TextMessage(
      author: _user,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      text: message.text,
    );

    _addMessage(textMessage);

    try {
      final supaUser = _supabase.auth.currentUser;
      
      // Fetch loans for context if logged in
      String loansContext = "User has no active loans.";
      if (supaUser != null) {
        final loans = await _supabase.from('loans').select().eq('user_id', supaUser.id);
        if (loans.isNotEmpty) {
           loansContext = "User's active loans: \n" + loans.map((l) => "- ${l['loan_type']}: ${l['status']}").join('\n');
        }
      }

      final response = await http.post(
        Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $groqApiKey',
        },
        body: jsonEncode({
          'model': 'llama-3.1-8b-instant',
          'messages': [
            {
              'role': 'system', 
              'content': 'You are a strict Shoonya Loan Assistant. Keep answers under 80 words. You MUST ONLY answer queries regarding loans, EMI, banking, and the Shoonya platform. If the user asks ANYTHING unrelated to loans or finance (like coding, general knowledge, jokes, etc), YOU MUST politely refuse to answer and redirect them back to loan topics.\nContext: $loansContext'
            },
            {'role': 'user', 'content': message.text},
          ],
          'temperature': 0.7,
        }),
      );

      final data = jsonDecode(response.body);
      
      if (response.statusCode != 200) {
        throw Exception(data['error']?['message'] ?? 'Groq API failed');
      }

      final reply = data['choices'][0]['message']['content'];

      _addMessage(
        types.TextMessage(
          author: _ai,
          createdAt: DateTime.now().millisecondsSinceEpoch,
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          text: reply,
        ),
      );
    } catch (e) {
      _addMessage(
        types.TextMessage(
          author: _ai,
          createdAt: DateTime.now().millisecondsSinceEpoch,
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          text: "I'm sorry, I'm having trouble connecting to my brain! Ensure your Groq API Key is configured. \n\nError: $e",
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Shoonya AI Assistant'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Chat(
        messages: _messages,
        onSendPressed: _handleSendPressed,
        user: _user,
        theme: const DarkChatTheme(
          primaryColor: Colors.deepPurpleAccent,
          backgroundColor: Color(0xFF0F172A),
        ),
      ),
    );
  }
}
