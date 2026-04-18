import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _supabase = Supabase.instance.client;
  Map<String, dynamic>? _profile;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    final user = _supabase.auth.currentUser;
    if (user != null) {
      final profile = await _supabase.from('profiles').select().eq('id', user.id).single();
      setState(() {
        _profile = profile;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: Color(0xFF10B981)))
        : CustomScrollView(
            slivers: [
              _buildAppBar(),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildKYCStatusCard(),
                      const SizedBox(height: 24),
                      const Text("ACTIVE LOAN REQUESTS", style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 2)),
                      const SizedBox(height: 16),
                      _buildLoansList(),
                    ],
                  ),
                ),
              )
            ],
          ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: FloatingActionButton(
          onPressed: () => context.push('/apply'),
          backgroundColor: const Color(0xFF10B981),
          elevation: 10,
          elevation: 10,
          child: const Icon(Icons.add, color: Colors.black, size: 32),
        ),
      ),
      bottomNavigationBar: _buildBottomAppBar(context),
    );
  }

  Widget _buildBottomAppBar(BuildContext context) {
    return BottomAppBar(
      color: const Color(0xFF0F172A),
      notchMargin: 8,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          IconButton(icon: const Icon(Icons.grid_view_rounded, color: Color(0xFF10B981)), onPressed: () {}),
          IconButton(icon: const Icon(Icons.support_agent_rounded, color: Colors.white38), onPressed: () => context.push('/chat')),
          const SizedBox(width: 40), // Space for FAB
          IconButton(icon: const Icon(Icons.folder_shared_outlined, color: Colors.white38), onPressed: () => context.go('/documents')),
          IconButton(icon: const Icon(Icons.person_pin_outlined, color: Colors.white38), onPressed: () => context.go('/profile')),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      expandedHeight: 100,
      backgroundColor: const Color(0xFF020617),
      floating: true,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("WELCOME BACK,", style: TextStyle(color: Colors.white24, fontSize: 10, fontWeight: FontWeight.bold)),
          Text(_profile?['full_name']?.split(' ')[0] ?? "USER", style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white)),
        ],
      ),
      actions: [
        IconButton(icon: const Icon(Icons.support_agent_rounded, color: Color(0xFF10B981)), onPressed: () => context.push('/chat')),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildKYCStatusCard() {
    final bool isVerified = _profile?['kyc_status'] == 'verified';
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isVerified ? const Color(0xFF10B981).withOpacity(0.05) : const Color(0xFFF59E0B).withOpacity(0.05),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: isVerified ? const Color(0xFF10B981).withOpacity(0.3) : const Color(0xFFF59E0B).withOpacity(0.3))
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: isVerified ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
            child: Icon(isVerified ? Icons.check : Icons.priority_high, color: Colors.black),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(isVerified ? "IDENTITY VERIFIED" : "VERIFICATION PENDING", style: TextStyle(color: isVerified ? const Color(0xFF10B981) : const Color(0xFFF59E0B), fontWeight: FontWeight.bold)),
                Text(isVerified ? "Your AI Loan Limit is unlocked" : "Complete AI interview to unlock your limit", style: const TextStyle(color: Colors.white38, fontSize: 12)),
              ],
            ),
          ),
          if (!isVerified) IconButton(onPressed: () => context.push('/kyc/demo'), icon: const Icon(Icons.arrow_forward_ios, color: Colors.white24, size: 16))
        ],
      ),
    );
  }

  Widget _buildLoansList() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _supabase.from('loans').stream(primaryKey: ['id']).eq('user_id', _supabase.auth.currentUser!.id),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final loans = snapshot.data!;
        if (loans.isEmpty) return _buildEmptyLoans();
        
        return Column(
          children: loans.map((loan) => _buildLoanCard(loan)).toList(),
        );
      },
    );
  }

  Widget _buildLoanCard(Map<String, dynamic> loan) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.03), borderRadius: BorderRadius.circular(28), border: Border.all(color: Colors.white.withOpacity(0.05))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(loan['loan_type'] ?? "Personal Loan", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 4),
              Text("Request Status: ${loan['status']}", style: TextStyle(color: loan['status'] == 'approved' ? const Color(0xFF10B981) : Colors.orangeAccent, fontSize: 12)),
            ],
          ),
          Text("₹${loan['amount_requested']}", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF10B981))),
        ],
      ),
    );
  }

  Widget _buildEmptyLoans() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.02), borderRadius: BorderRadius.circular(30), border: Border.all(color: Colors.white.withOpacity(0.03), style: BorderStyle.none)),
      child: const Column(
        children: [
          Icon(Icons.receipt_long_outlined, color: Colors.white12, size: 48),
          SizedBox(height: 16),
          Text("NO LOAN HISTORY", style: TextStyle(color: Colors.white24, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
