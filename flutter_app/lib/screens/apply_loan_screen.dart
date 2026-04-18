import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';

class ApplyLoanScreen extends StatefulWidget {
  const ApplyLoanScreen({super.key});

  @override
  State<ApplyLoanScreen> createState() => _ApplyLoanScreenState();
}

class _ApplyLoanScreenState extends State<ApplyLoanScreen> {
  final _supabase = Supabase.instance.client;
  double _amountRequested = 10000;
  double _maxLimit = 100000;
  String _loanType = "Personal Loan";
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _fetchLimit();
  }

  Future<void> _fetchLimit() async {
    final user = _supabase.auth.currentUser;
    if (user != null) {
      final profile = await _supabase.from('profiles').select().eq('id', user.id).single();
      setState(() {
        _maxLimit = (profile['loan_limit'] ?? 10000).toDouble();
        _amountRequested = _maxLimit > 10000 ? 10000 : _maxLimit;
        _isLoading = false;
      });
    }
  }

  Future<void> _submit() async {
    setState(() => _isSaving = true);
    final user = _supabase.auth.currentUser;
    if (user != null) {
      await _supabase.from('loans').insert({
        'user_id': user.id,
        'amount_requested': _amountRequested,
        'loan_type': _loanType,
        'status': 'pending'
      });
      if (mounted) context.go('/dashboard');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text("LOAN CALCULATOR", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 14)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("SELECT AMOUNT", style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 2)),
                const SizedBox(height: 16),
                
                // DISPLAY CARD
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(40),
                  decoration: BoxDecoration(color: const Color(0xFF10B981).withOpacity(0.05), borderRadius: BorderRadius.circular(32), border: Border.all(color: const Color(0xFF10B981).withOpacity(0.2))),
                  child: Column(
                    children: [
                      Text("₹${_amountRequested.toInt()}", style: const TextStyle(color: Color(0xFF10B981), fontSize: 48, fontWeight: FontWeight.w900)),
                      Text("OF ₹${_maxLimit.toInt()} APPROVED LIMIT", style: const TextStyle(color: Colors.white24, fontSize: 10, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                
                const SizedBox(height: 40),
                Slider(
                  value: _amountRequested,
                  min: 5000,
                  max: _maxLimit < 5000 ? 5000 : _maxLimit,
                  activeColor: const Color(0xFF10B981),
                  inactiveColor: Colors.white12,
                  onChanged: (val) => setState(() => _amountRequested = val),
                ),
                
                const SizedBox(height: 48),
                const Text("LOAN PURPOSE", style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 2)),
                const SizedBox(height: 16),
                _buildTypeTile("Personal Loan", Icons.person_outline),
                _buildTypeTile("Home Loan", Icons.home_work_outlined),
                _buildTypeTile("Vehicle Loan", Icons.directions_car_filled_outlined),
                
                const SizedBox(height: 60),
                _isSaving 
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF10B981)))
                  : ElevatedButton(
                      onPressed: _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.black,
                        minimumSize: const Size(double.infinity, 64),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                        elevation: 10,
                        shadowColor: const Color(0xFF10B981).withOpacity(0.4)
                      ),
                      child: const Text("SUBMIT LOAN REQUEST", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                    ),
              ],
            ),
          ),
    );
  }

  Widget _buildTypeTile(String type, IconData icon) {
    final bool isSelected = _loanType == type;
    return GestureDetector(
      onTap: () => setState(() => _loanType = type),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF10B981).withOpacity(0.1) : Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: isSelected ? const Color(0xFF10B981) : Colors.white.withOpacity(0.05))
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? const Color(0xFF10B981) : Colors.white24),
            const SizedBox(width: 16),
            Text(type, style: TextStyle(color: isSelected ? Colors.white : Colors.white54, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
            const Spacer(),
            if (isSelected) const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 20),
          ],
        ),
      ),
    );
  }
}
