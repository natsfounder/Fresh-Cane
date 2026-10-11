import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../state/admin_provider.dart';
import '../../../state/payment_method_provider.dart';

class AdminSettingsView extends ConsumerStatefulWidget {
  const AdminSettingsView({super.key});

  @override
  ConsumerState<AdminSettingsView> createState() => _AdminSettingsViewState();
}

class _AdminSettingsViewState extends ConsumerState<AdminSettingsView> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _gstinCtrl = TextEditingController();
  final _footerCtrl = TextEditingController();
  bool _initialized = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _gstinCtrl.dispose();
    _footerCtrl.dispose();
    super.dispose();
  }

  void _populate(Map<String, dynamic>? settings) {
    if (settings != null && !_initialized) {
      _nameCtrl.text = settings['store_name'] ?? 'Fresh Cane';
      _phoneCtrl.text = settings['phone'] ?? '';
      _addressCtrl.text = settings['address'] ?? '';
      _gstinCtrl.text = settings['gstin'] ?? '';
      _footerCtrl.text = settings['receipt_footer'] ?? 'Thank you for visiting Fresh Cane!';
      _initialized = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(adminProvider);
    final notifier = ref.read(adminProvider.notifier);

    _populate(state.storeSettings);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
          constraints: const BoxConstraints(maxWidth: 600),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: AppColors.primaryLight,
                    child: const Icon(Icons.storefront, color: AppColors.primaryGreen),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Store & Invoice Configuration',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Branding and details printed on guest receipts',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Store / Brand Name',
                  prefixIcon: Icon(Icons.business_outlined, size: 20),
                ),
              ),
              const SizedBox(height: 16),

              TextField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Store Contact Phone',
                  prefixIcon: Icon(Icons.phone_outlined, size: 20),
                ),
              ),
              const SizedBox(height: 16),

              TextField(
                controller: _addressCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Store Physical Address',
                  prefixIcon: Icon(Icons.location_on_outlined, size: 20),
                ),
              ),
              const SizedBox(height: 16),

              TextField(
                controller: _gstinCtrl,
                decoration: const InputDecoration(
                  labelText: 'GSTIN / Tax Registration Number',
                  prefixIcon: Icon(Icons.receipt_outlined, size: 20),
                ),
              ),
              const SizedBox(height: 16),

              TextField(
                controller: _footerCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Receipt Footer Message',
                  prefixIcon: Icon(Icons.notes_outlined, size: 20),
                ),
              ),
              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF266540),
                      foregroundColor: Colors.white,
                      elevation: 2,
                      shadowColor: const Color(0xFF266540).withValues(alpha: 0.3),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () {
                      notifier.updateStoreSettings({
                        'store_name': _nameCtrl.text.trim(),
                        'phone': _phoneCtrl.text.trim(),
                        'address': _addressCtrl.text.trim(),
                        'gstin': _gstinCtrl.text.trim(),
                        'receipt_footer': _footerCtrl.text.trim(),
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Store settings updated successfully!'),
                          backgroundColor: Color(0xFF266540),
                        ),
                      );
                    },
                    child: const Text(
                      'Save Configuration',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Centralized Payment Methods Card
          Container(
            constraints: const BoxConstraints(maxWidth: 600),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: const Color(0xFFE8F5E9),
                      child: const Icon(Icons.payments_rounded, color: Color(0xFF266540)),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Payment Methods Configuration',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F2E1E)),
                          ),
                          Text(
                            'Control payment options available across Billing & Expenses',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 8),

                Consumer(
                  builder: (context, ref, _) {
                    final methods = ref.watch(paymentMethodsProvider);
                    final notifier = ref.read(paymentMethodsProvider.notifier);

                    return Column(
                      children: methods.map((m) {
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: m.isEnabled ? const Color(0xFFE8F5E9) : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(m.icon, color: m.isEnabled ? const Color(0xFF266540) : Colors.grey, size: 20),
                          ),
                          title: Text(
                            m.name,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: m.isEnabled ? const Color(0xFF0F2E1E) : Colors.grey,
                            ),
                          ),
                          subtitle: Text(
                            m.isEnabled ? 'Active in Cashier POS & Expenses' : 'Disabled / Hidden',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined, size: 18, color: Colors.grey),
                                tooltip: 'Edit Display Name',
                                onPressed: () {
                                  final editCtrl = TextEditingController(text: m.name);
                                  showDialog(
                                    context: context,
                                    builder: (dCtx) => AlertDialog(
                                      title: Text('Edit ${m.id.toUpperCase()} Name'),
                                      content: TextField(
                                        controller: editCtrl,
                                        decoration: const InputDecoration(labelText: 'Display Name'),
                                      ),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('Cancel')),
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF266540)),
                                          onPressed: () {
                                            if (editCtrl.text.trim().isNotEmpty) {
                                              notifier.updateName(m.id, editCtrl.text.trim());
                                            }
                                            Navigator.pop(dCtx);
                                          },
                                          child: const Text('Save', style: TextStyle(color: Colors.white)),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                              Switch(
                                value: m.isEnabled,
                                activeThumbColor: const Color(0xFF266540),
                                activeTrackColor: const Color(0xFF266540).withValues(alpha: 0.4),
                                onChanged: (val) {
                                  notifier.toggleMethod(m.id, val);
                                },
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
              ],
            ),
          ),

          // Fresh Cane Brand Footer (Mockup Screen 12)
          const SizedBox(height: 32),
          Column(
            children: [
              Image.asset(
                'assets/images/fresh_cane_logo.png',
                height: 40,
                errorBuilder: (_, __, ___) => const Icon(Icons.eco_rounded, color: Color(0xFF266540), size: 32),
              ),
              const SizedBox(height: 6),
              const Text(
                'Fresh Cane',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Color(0xFF0F2E1E),
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'Good Food • Fresh Vibes',
                style: TextStyle(
                  fontSize: 10,
                  color: Color(0xFF7CB342),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    ),
  );
  }
}
