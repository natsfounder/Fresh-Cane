import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/user_profile.dart';
import '../../../state/auth_provider.dart';

class AdminStaffView extends ConsumerStatefulWidget {
  const AdminStaffView({super.key});

  @override
  ConsumerState<AdminStaffView> createState() => _AdminStaffViewState();
}

class _AdminStaffViewState extends ConsumerState<AdminStaffView> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();

  final Set<String> _selectedRoles = {'server'};

  bool _isPasswordVisible = false;
  bool _isCreatingUser = false;
  bool _isLoadingStaff = true;
  List<UserProfile> _staffList = [];
  String? _statusMessage;
  bool _isSuccessMessage = true;

  @override
  void initState() {
    super.initState();
    _loadStaffMembers();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _loadStaffMembers() async {
    setState(() => _isLoadingStaff = true);
    try {
      final repo = ref.read(authRepositoryProvider);
      final staff = await repo.fetchAllActiveProfiles();
      if (mounted) {
        setState(() {
          _staffList = staff.where((p) => !p.isMasterSuperAdminUser).toList();
          _isLoadingStaff = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingStaff = false);
      }
    }
  }

  Future<void> _handleCreateUser() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedRoles.isEmpty) {
      setState(() {
        _isSuccessMessage = false;
        _statusMessage = 'Please select at least one access role for this staff member.';
      });
      return;
    }

    setState(() {
      _isCreatingUser = true;
      _statusMessage = null;
    });

    try {
      final repo = ref.read(authRepositoryProvider);
      final result = await repo.createStaffUser(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        fullName: _nameController.text.trim(),
        roles: _selectedRoles.toList(),
        phone: _phoneController.text.trim().isNotEmpty
            ? _phoneController.text.trim()
            : null,
      );

      if (mounted) {
        final rolesList = (_selectedRoles.map((r) {
          switch (r) {
            case 'server':
              return 'Server';
            case 'cashier':
              return 'Biller';
            case 'super_admin':
              return 'Admin';
            default:
              return r;
          }
        })).join(', ');

        final createdName = result['full_name'] ?? _nameController.text.trim();
        setState(() {
          _isSuccessMessage = true;
          _statusMessage = 'Staff account "$createdName" created with roles: $rolesList!';
          _nameController.clear();
          _emailController.clear();
          _passwordController.clear();
          _phoneController.clear();
          _selectedRoles
            ..clear()
            ..add('server');
        });
        await _loadStaffMembers();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSuccessMessage = false;
          _statusMessage = 'Failed to create user: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isCreatingUser = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStatusBanner(),

          // Form & Staff List Side-by-side or stacked
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 800;
              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 5, child: _buildCreateUserCard()),
                    const SizedBox(width: 20),
                    Expanded(flex: 5, child: _buildStaffDirectoryCard()),
                  ],
                );
              } else {
                return Column(
                  children: [
                    _buildCreateUserCard(),
                    const SizedBox(height: 20),
                    _buildStaffDirectoryCard(),
                  ],
                );
              }
            },
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildStatusBanner() {
    if (_statusMessage == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _isSuccessMessage ? Colors.green.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _isSuccessMessage ? Colors.green.shade200 : Colors.red.shade200,
        ),
      ),
      child: Row(
        children: [
          Icon(
            _isSuccessMessage ? Icons.check_circle : Icons.error_outline,
            color: _isSuccessMessage ? Colors.green.shade700 : Colors.red.shade700,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _statusMessage!,
              style: TextStyle(
                color: _isSuccessMessage ? Colors.green.shade800 : Colors.red.shade800,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => setState(() => _statusMessage = null),
          ),
        ],
      ),
    );
  }

  Widget _buildCreateUserCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.primaryLight,
                  child: const Icon(Icons.person_add_alt_1, color: AppColors.primaryGreen, size: 20),
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Create Staff Account',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Assign multiple roles (Server, Biller, Admin)',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),

            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Full Name *',
                prefixIcon: Icon(Icons.person_outline, size: 20),
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter full name' : null,
            ),
            const SizedBox(height: 14),

            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email Address *',
                prefixIcon: Icon(Icons.email_outlined, size: 20),
              ),
              validator: (v) => (v == null || !v.contains('@')) ? 'Please enter a valid email' : null,
            ),
            const SizedBox(height: 14),

            TextFormField(
              controller: _passwordController,
              obscureText: !_isPasswordVisible,
              decoration: InputDecoration(
                labelText: 'Temporary Password *',
                prefixIcon: const Icon(Icons.lock_outline, size: 20),
                suffixIcon: IconButton(
                  icon: Icon(_isPasswordVisible ? Icons.visibility_off : Icons.visibility, size: 20),
                  onPressed: () => setState(() => _isPasswordVisible = !_isPasswordVisible),
                ),
              ),
              validator: (v) => (v == null || v.length < 6) ? 'Password must be at least 6 characters' : null,
            ),
            const SizedBox(height: 14),

            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone Number (Optional)',
                prefixIcon: Icon(Icons.phone_outlined, size: 20),
              ),
            ),
            const SizedBox(height: 18),

            const Text(
              'Assign Roles & Access Permissions *',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            _buildRoleCheckbox('server', 'Server', 'Take orders and manage table carts', Icons.room_service_outlined),
            _buildRoleCheckbox('cashier', 'Biller (Cashier)', 'Generate bills and accept payments', Icons.point_of_sale_outlined),
            _buildRoleCheckbox('super_admin', 'Admin', 'Manage menu, staff, and view business reports', Icons.admin_panel_settings_outlined),

            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _isCreatingUser ? null : _handleCreateUser,
                child: _isCreatingUser
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Text(
                        'Create Staff Member',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleCheckbox(String roleId, String title, String subtitle, IconData icon) {
    final isSelected = _selectedRoles.contains(roleId);
    return CheckboxListTile(
      value: isSelected,
      dense: true,
      contentPadding: EdgeInsets.zero,
      activeColor: AppColors.primaryGreen,
      secondary: Icon(icon, color: isSelected ? AppColors.primaryGreen : Colors.grey, size: 20),
      title: Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isSelected ? AppColors.primaryGreen : Colors.black)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      onChanged: (val) {
        setState(() {
          if (val == true) {
            _selectedRoles.add(roleId);
          } else {
            _selectedRoles.remove(roleId);
          }
        });
      },
    );
  }

  Widget _buildStaffDirectoryCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Active Staff Directory',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: _loadStaffMembers,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_isLoadingStaff)
            const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator(color: AppColors.primaryGreen)))
          else if (_staffList.isEmpty)
            const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('No active staff members found.')))
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _staffList.length,
              separatorBuilder: (_, __) => const Divider(height: 16),
              itemBuilder: (context, index) {
                final staff = _staffList[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: AppColors.primaryLight,
                    child: Text(
                      staff.fullName.isNotEmpty ? staff.fullName[0].toUpperCase() : 'S',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryGreen),
                    ),
                  ),
                  title: Text(
                    staff.fullName,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  subtitle: Text(
                    'Role: ${staff.role.toUpperCase()}${staff.phone != null ? ' • Phone: ${staff.phone}' : ''}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          staff.isActive ? 'ACTIVE' : 'INACTIVE',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: staff.isActive ? Colors.green.shade700 : Colors.red,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.key_rounded, size: 20, color: AppColors.primaryGreen),
                        tooltip: 'Reset Password',
                        padding: const EdgeInsets.all(6),
                        constraints: const BoxConstraints(),
                        onPressed: () => _showResetPasswordDialog(context, staff),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  void _showResetPasswordDialog(BuildContext context, UserProfile staff) {
    final passwordCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool isPasswordVisible = false;
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.lock_reset_rounded, color: AppColors.primaryGreen, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Reset Password', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    Text(
                      '${staff.fullName} (${staff.role.toUpperCase()})',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.normal),
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Set a new login password for this staff member:',
                  style: TextStyle(fontSize: 12.5, color: Colors.black87),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: passwordCtrl,
                  obscureText: !isPasswordVisible,
                  decoration: InputDecoration(
                    labelText: 'New Password *',
                    hintText: 'Enter new password',
                    prefixIcon: const Icon(Icons.lock_outline, size: 20),
                    suffixIcon: IconButton(
                      icon: Icon(isPasswordVisible ? Icons.visibility_off : Icons.visibility, size: 20),
                      onPressed: () => setDlgState(() => isPasswordVisible = !isPasswordVisible),
                    ),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().length < 6) {
                      return 'Password must be at least 6 characters';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryGreen,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: isSubmitting
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setDlgState(() => isSubmitting = true);
                      try {
                        await ref.read(authRepositoryProvider).resetStaffPassword(
                              userId: staff.id,
                              newPassword: passwordCtrl.text.trim(),
                            );
                        if (context.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Password updated successfully for ${staff.fullName}'),
                              backgroundColor: AppColors.primaryGreen,
                            ),
                          );
                        }
                      } catch (e) {
                        setDlgState(() => isSubmitting = false);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Failed to reset password: $e'),
                              backgroundColor: Colors.red.shade700,
                            ),
                          );
                        }
                      }
                    },
              child: isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Text('Update Password'),
            ),
          ],
        ),
      ),
    );
  }
}
