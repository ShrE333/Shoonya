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
  List<dynamic> _offers = [];
  int _selectedIndex = 1; // Default to Standard
  bool _isLoading = true;
  bool _isSaving = false;
  bool _hasPendingLoan = false;

  @override
  void initState() {
    super.initState();
    _fetchOffersAndStatus();
  }

  Future<void> _fetchOffersAndStatus() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      // 1. Check for finalizealized loans (Under Review or Approved)
      final finalized = await _supabase.from('loans')
          .select()
          .eq('user_id', user.id)
          .or('status.eq.under_review,status.eq.approved');
      
      if (finalized.isNotEmpty) {
        setState(() { _hasPendingLoan = true; _isLoading = false; });
        return;
      }

      // 2. Fetch the draft loan awaiting selection
      final lastLoan = await _supabase.from('loans')
          .select('id, offers')
          .eq('user_id', user.id)
          .eq('status', 'awaiting_selection')
          .order('created_at', ascending: false)
          .limit(1)
          .single();

      setState(() {
        _offers = lastLoan['offers'] ?? [];
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _submit() async {
    if (_offers.isEmpty) return;
    setState(() => _isSaving = true);
    
    final selected = _offers[_selectedIndex];
    final user = _supabase.auth.currentUser;
    
    try {
      // Update existing pending loan with selection
      final lastLoan = await _supabase.from('loans')
          .select('id')
          .eq('user_id', user!.id)
          .eq('status', 'awaiting_selection')
          .order('created_at', ascending: false)
          .limit(1)
          .single();

      await _supabase.from('loans').update({
        'amount_requested': (selected['amount']).toDouble(),
        'tenure_months': selected['tenure'],
        'interest_rate': (selected['rate']).toDouble(),
        'status': 'under_review', 
        'selected_offer_index': _selectedIndex
      }).eq('id', lastLoan['id']);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Loan strategy sent to Admin for final sanction!"), backgroundColor: Color(0xFF10B981)));
        context.go('/dashboard');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Submission failed. Try again."), backgroundColor: Colors.redAccent));
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      appBar: AppBar(
        title: const Text("OFFER STRATEGY", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 12)),
        centerTitle: true, backgroundColor: Colors.transparent, elevation: 0,
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: Color(0xFF10B981)))
        : _hasPendingLoan
          ? _buildPendingState()
          : _offers.isEmpty 
            ? _buildNoOffersState()
            : _buildOfferSelection(),
    );
  }

  Widget _buildOfferSelection() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("AI RECOMMENDED PACKAGES", style: TextStyle(color: Color(0xFF10B981), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 2)),
          const SizedBox(height: 24),
          ..._offers.asMap().entries.map((entry) => _buildOfferCard(entry.key, entry.value)),
          const SizedBox(height: 48),
          _isSaving 
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF10B981)))
            : ElevatedButton(
                onPressed: _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.black,
                  minimumSize: const Size(double.infinity, 64),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                child: const Text("CONFIRM SELECTION", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              ),
        ],
      ),
    );
  }

  Widget _buildOfferCard(int index, dynamic offer) {
    final bool isSelected = _selectedIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedIndex = index),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF10B981).withOpacity(0.05) : Colors.white.withOpacity(0.02),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: isSelected ? const Color(0xFF10B981) : Colors.white12, width: 2),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(offer['name'].toString().toUpperCase(), style: TextStyle(color: isSelected ? const Color(0xFF10B981) : Colors.white24, fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 1)),
                  const SizedBox(height: 8),
                  Text("₹${offer['amount']}", style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text("${offer['tenure']} Months @ ${offer['rate']}% p.a.", style: const TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              ),
            ),
            if (isSelected) const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingState() {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.hourglass_empty, color: Color(0xFF10B981), size: 64),
        const SizedBox(height: 24),
        const Text("STRATEGY UNDER REVIEW", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        const SizedBox(height: 32),
        ElevatedButton(onPressed: () => context.go('/dashboard'), child: const Text("BACK TO HUB")),
      ]),
    );
  }

  Widget _buildNoOffersState() {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.security, color: Colors.white10, size: 64),
        const SizedBox(height: 24),
        const Text("NO AI OFFERS FOUND", style: TextStyle(color: Colors.white24)),
        const SizedBox(height: 12),
        const Text("Please complete KYC first", style: TextStyle(color: Colors.white10)),
        const SizedBox(height: 32),
        ElevatedButton(onPressed: () => context.go('/kyc/demo'), child: const Text("START AI KYC")),
      ]),
    );
  }
}
