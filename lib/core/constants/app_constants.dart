/// Domain constants aligning with Fresh Cane PostgreSQL 17 database schema.
class AppConstants {
  const AppConstants._();

  // Store Configuration
  static const String storeSettingsSingletonId =
      '00000000-0000-0000-0000-000000000001';
  static const String defaultCurrencySymbol = '₹';
  static const String defaultCurrencyCode = 'INR';

  // User Roles (Enforced by public.user_profiles and RLS)
  static const String roleServer = 'server';
  static const String roleCashier = 'cashier';
  static const String roleSuperAdmin = 'super_admin';

  // Order Types
  static const String orderTypeDineIn = 'dine_in';
  static const String orderTypeTakeaway = 'takeaway';

  // Order Lifecycle Statuses
  static const String orderStatusOpen = 'open';
  static const String orderStatusServed = 'served';
  static const String orderStatusCompleted = 'completed';
  static const String orderStatusCancelled = 'cancelled';

  // Bill Statuses
  static const String billStatusUnpaid = 'unpaid';
  static const String billStatusPaid = 'paid';
  static const String billStatusVoided = 'voided';

  // Payment Methods
  static const String paymentMethodCash = 'cash';
  static const String paymentMethodUpi = 'upi';
  static const String paymentMethodCard = 'card';
  static const String paymentMethodSplit = 'split';

  // Payment Statuses
  static const String paymentStatusCompleted = 'completed';
  static const String paymentStatusRefunded = 'refunded';

  // Table Statuses
  static const String tableStatusAvailable = 'available';
  static const String tableStatusOccupied = 'occupied';
}
