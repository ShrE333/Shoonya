import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _supabase = Supabase.instance.client;
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.chat_bubble_outline),
            onPressed: () => context.push('/chat'),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await _supabase.auth.signOut();
              if (mounted) context.go('/login');
            },
          )
        ],
      ),
      body: _supabase.auth.currentUser == null 
        ? const Center(child: Text("Please login to view loans"))
        : StreamBuilder<List<Map<String, dynamic>>>(
        stream: _supabase.from('loans').stream(primaryKey: ['id']).eq('user_id', _supabase.auth.currentUser!.id),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final loans = snapshot.data!;
          if (loans.isEmpty) {
            return const Center(child: Text("No loans found"));
          }
          return ListView.builder(
            itemCount: loans.length,
            itemBuilder: (context, index) {
              final loan = loans[index];
              return ListTile(
                title: Text(loan['loan_type']),
                subtitle: Text('Status: ${loan['status']}'),
                trailing: Text('₹${loan['amount_requested']}'),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/apply'),
        child: const Icon(Icons.add),
      ),
    );
  }
}
