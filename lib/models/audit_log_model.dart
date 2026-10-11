import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Represents a structured, immutable audit log record adhering to:
/// WHO → DID WHAT → TO WHAT → WHEN → RESULT/CHANGE
class AuditLogEntry {
  final String id;
  final String? userId;
  final String userName;
  final String userRole;
  final String rawAction;
  final String actionTitle;
  final String module;
  final String entityType;
  final String? entityId;
  final String entityName;
  final String changeSummary;
  final String previousStateText;
  final String newStateText;
  final String? reason;
  final Map<String, dynamic>? oldData;
  final Map<String, dynamic>? newData;
  final DateTime createdAt;

  const AuditLogEntry({
    required this.id,
    this.userId,
    required this.userName,
    required this.userRole,
    required this.rawAction,
    required this.actionTitle,
    required this.module,
    required this.entityType,
    this.entityId,
    required this.entityName,
    required this.changeSummary,
    required this.previousStateText,
    required this.newStateText,
    this.reason,
    this.oldData,
    this.newData,
    required this.createdAt,
  });

  /// Formatted date string, e.g. "08 Oct 2026"
  String get formattedDate => DateFormat('dd MMM yyyy').format(createdAt);

  /// Formatted time string, e.g. "07:42 PM"
  String get formattedTime => DateFormat('hh:mm a').format(createdAt);

  /// Full formatted timestamp, e.g. "08 Oct 2026, 07:42 PM"
  String get formattedDateTime => DateFormat('dd MMM yyyy, hh:mm a').format(createdAt);

  /// Compact timestamp, e.g. "08 Oct 2026 • 07:42 PM"
  String get formattedDateTimeCompact => '$formattedDate • $formattedTime';

  factory AuditLogEntry.fromMap(Map<String, dynamic> map) {
    final id = map['id']?.toString() ?? '';
    final userId = map['user_id']?.toString();
    final rawAction = (map['action']?.toString() ?? 'UNKNOWN').trim();
    final rawEntityType = (map['entity_type']?.toString() ?? map['table_name']?.toString() ?? 'system').trim();
    final entityId = map['entity_id']?.toString();

    // Parse actor profile
    final userProfile = map['user_profiles'] as Map<String, dynamic>?;
    String rawRole = userProfile?['role']?.toString() ?? '';
    String userName = userProfile?['full_name']?.toString() ?? '';

    final oldData = map['old_data'] is Map ? Map<String, dynamic>.from(map['old_data'] as Map) : null;
    final newData = map['new_data'] is Map ? Map<String, dynamic>.from(map['new_data'] as Map) : null;

    // Fallbacks for actor name
    if (userName.isEmpty) {
      if (newData?['user_name'] != null) {
        userName = newData!['user_name'].toString();
      } else if (newData?['actor_name'] != null) {
        userName = newData!['actor_name'].toString();
      } else if (rawRole.toLowerCase() == 'super_admin') {
        userName = 'Super Admin';
      } else if (userId != null && userId.isNotEmpty) {
        userName = 'User #${userId.substring(0, userId.length > 8 ? 8 : userId.length)}';
      } else {
        userName = 'System';
      }
    }

    // Format actor role
    if (rawRole.isEmpty) {
      rawRole = newData?['role']?.toString() ?? (userId == null ? 'Automated' : 'Admin');
    }
    final formattedRole = _formatRoleName(rawRole);

    // Module classification
    final module = _determineModule(rawEntityType, rawAction);

    // Action Title
    final actionTitle = _determineActionTitle(rawAction, rawEntityType, oldData, newData);

    // Entity Display Name
    final entityName = _determineEntityName(rawEntityType, entityId, oldData, newData);

    // Change Summary
    final changeSummary = _computeChangeSummary(
      rawAction: rawAction,
      entityType: rawEntityType,
      oldData: oldData,
      newData: newData,
      actionTitle: actionTitle,
    );

    // Structured Previous & New State Texts
    final previousStateText = _formatStateSummary(oldData, isPrevious: true);
    final newStateText = _formatStateSummary(newData, isPrevious: false);

    // Reason / Metadata extraction
    final reason = _extractReason(newData, oldData);

    // Parse Timestamp
    DateTime createdAt = DateTime.now();
    if (map['created_at'] != null) {
      try {
        createdAt = DateTime.parse(map['created_at'].toString()).toLocal();
      } catch (_) {
        createdAt = DateTime.now();
      }
    }

    return AuditLogEntry(
      id: id,
      userId: userId,
      userName: userName,
      userRole: formattedRole,
      rawAction: rawAction,
      actionTitle: actionTitle,
      module: module,
      entityType: rawEntityType,
      entityId: entityId,
      entityName: entityName,
      changeSummary: changeSummary,
      previousStateText: previousStateText,
      newStateText: newStateText,
      reason: reason,
      oldData: oldData,
      newData: newData,
      createdAt: createdAt,
    );
  }

  // ---------------------------------------------------------------------------
  // HEURISTIC HELPERS
  // ---------------------------------------------------------------------------

  static String _formatRoleName(String role) {
    final clean = role.toLowerCase().replaceAll('_', ' ').trim();
    if (clean.isEmpty) return 'Staff';
    if (clean == 'super admin') return 'Super Admin';
    if (clean == 'admin') return 'Admin';
    if (clean == 'cashier') return 'Cashier';
    if (clean == 'server') return 'Server';
    if (clean == 'automated' || clean == 'system') return 'Automated';
    return clean.split(' ').map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '').join(' ');
  }

  static String _determineModule(String entityType, String action) {
    final ent = entityType.toLowerCase();
    final act = action.toUpperCase();

    if (ent.contains('menu') || ent.contains('product') || ent.contains('category') || ent.contains('addon') || act.contains('MENU') || act.contains('PRODUCT') || act.contains('PRICE')) {
      return 'MENU';
    }
    if (ent.contains('order') || ent.contains('session') || ent.contains('customer') || ent.contains('table') || act.contains('ORDER') || act.contains('SESSION') || act.contains('TABLE')) {
      return 'ORDERS';
    }
    if (ent.contains('bill') || ent.contains('payment') || ent.contains('settle') || act.contains('BILL') || act.contains('PAYMENT') || act.contains('SETTLEMENT') || act.contains('REVERT')) {
      return 'BILLING';
    }
    if (ent.contains('expense') || act.contains('EXPENSE')) {
      return 'EXPENSES';
    }
    if (ent.contains('user') || ent.contains('staff') || ent.contains('profile') || ent.contains('auth') || act.contains('USER') || act.contains('ROLE')) {
      return 'USERS';
    }
    if (ent.contains('setting') || ent.contains('config') || ent.contains('store') || act.contains('SETTING')) {
      return 'SETTINGS';
    }
    return 'SYSTEM';
  }

  static String _determineActionTitle(
    String rawAction,
    String entityType,
    Map<String, dynamic>? oldData,
    Map<String, dynamic>? newData,
  ) {
    final actUpper = rawAction.toUpperCase();
    final actLower = rawAction.toLowerCase();

    // Check specific known action codes first
    switch (actUpper) {
      case 'PRICE_UPDATED':
      case 'PRICE_UPDATE':
        return 'Price Updated';
      case 'ORDER_CANCELLED':
      case 'CANCEL_ORDER':
        return 'Order Cancelled';
      case 'ORDER_ITEM_CANCELLED':
        return 'Order Item Cancelled';
      case 'ORDER_CREATED':
        return 'Order Created';
      case 'ORDER_FINISHED':
        return 'Order Finished';
      case 'ORDER_REOPENED':
        return 'Order Reopened';
      case 'ORDER_CORRECTED':
        return 'Order Corrected';
      case 'BILL_GENERATED':
      case 'GENERATE_BILL':
        return 'Bill Generated';
      case 'PAYMENT_COMPLETED':
      case 'COMPLETE_PAYMENT':
        return 'Payment Completed';
      case 'BILL_VOIDED':
      case 'VOID_BILL':
      case 'REVERT_BILL':
        return 'Bill Voided / Reverted';
      case 'BILL_CORRECTED':
      case 'EDIT_PARCEL_BILL':
        return 'Bill Corrected';
      case 'BILL_REPRINTED':
        return 'Bill Reprinted';
      case 'SWAP_CUSTOMER_TABLE':
      case 'TRANSFER_CUSTOMER':
        return 'Table Swapped';
      case 'USER_CREATED':
      case 'CREATE_USER':
        return 'User Created';
      case 'USER_UPDATED':
      case 'UPDATE_USER':
        return 'User Updated';
      case 'ROLE_CHANGED':
        return 'Role Changed';
      case 'USER_ACTIVATED':
        return 'User Activated';
      case 'USER_DEACTIVATED':
        return 'User Deactivated';
      case 'EXPENSE_RECORDED':
      case 'CREATE_EXPENSE':
        return 'Expense Recorded';
      case 'EXPENSE_CORRECTED':
        return 'Expense Corrected';
      case 'EXPENSE_DEFINITION_CREATED':
        return 'Expense Category Created';
      case 'EXPENSE_DEFINITION_UPDATED':
        return 'Expense Category Updated';
      case 'EXPENSE_DEFINITION_DEACTIVATED':
        return 'Expense Category Deactivated';
      case 'PRODUCT_CREATED':
        return 'Product Created';
      case 'PRODUCT_UPDATED':
        return 'Product Updated';
      case 'PRODUCT_ACTIVATED':
        return 'Product Activated';
      case 'PRODUCT_DEACTIVATED':
        return 'Product Deactivated';
      case 'CATEGORY_CREATED':
        return 'Category Created';
      case 'CATEGORY_UPDATED':
        return 'Category Updated';
      case 'PAYMENT_METHOD_ENABLED':
        return 'Payment Method Enabled';
      case 'PAYMENT_METHOD_DISABLED':
        return 'Payment Method Disabled';
      case 'PAYMENT_METHOD_UPDATED':
        return 'Payment Method Updated';
      case 'IMPORTANT_SETTING_CHANGED':
        return 'Setting Changed';
    }

    // Generic SQL Trigger actions (INSERT, UPDATE, DELETE)
    if (actLower == 'insert' || actLower == 'create') {
      if (entityType.contains('menu') || entityType.contains('product')) return 'Product Created';
      if (entityType.contains('category')) return 'Category Created';
      if (entityType.contains('order')) return 'Order Created';
      if (entityType.contains('bill')) return 'Bill Generated';
      if (entityType.contains('payment')) return 'Payment Recorded';
      if (entityType.contains('expense')) return 'Expense Recorded';
      if (entityType.contains('user')) return 'User Created';
      return 'Record Created';
    }

    if (actLower == 'update' || actLower == 'modify') {
      // Check if price specifically changed
      final oldPrice = oldData?['price'] ?? oldData?['base_price'];
      final newPrice = newData?['price'] ?? newData?['base_price'];
      if (oldPrice != null && newPrice != null && oldPrice.toString() != newPrice.toString()) {
        return 'Price Updated';
      }

      // Check if status changed to cancelled
      final newStatus = newData?['status']?.toString().toLowerCase();
      if (newStatus == 'cancelled' || newStatus == 'canceled' || newStatus == 'void') {
        return 'Order Cancelled';
      }

      // Check if availability toggled
      if (oldData?['is_available'] != null && newData?['is_available'] != null && oldData!['is_available'] != newData!['is_available']) {
        return newData['is_available'] == true ? 'Product In-Stock' : 'Product Out-of-Stock';
      }

      if (entityType.contains('menu')) return 'Menu Item Updated';
      if (entityType.contains('order')) return 'Order Updated';
      if (entityType.contains('bill')) return 'Bill Updated';
      if (entityType.contains('user')) return 'User Updated';
      return 'Record Updated';
    }

    if (actLower == 'delete' || actLower == 'remove') {
      return 'Record Deleted';
    }

    // Fallback: title-case the string
    return rawAction
        .replaceAll('_', ' ')
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
        .join(' ');
  }

  static String _determineEntityName(
    String entityType,
    String? entityId,
    Map<String, dynamic>? oldData,
    Map<String, dynamic>? newData,
  ) {
    // 1. Direct name from new or old data
    final directName = newData?['name'] ??
        oldData?['name'] ??
        newData?['item_name'] ??
        oldData?['item_name'] ??
        newData?['product_name'] ??
        oldData?['product_name'] ??
        newData?['full_name'] ??
        oldData?['full_name'] ??
        newData?['title'] ??
        oldData?['title'];

    if (directName != null && directName.toString().trim().isNotEmpty) {
      return directName.toString().trim();
    }

    // 2. Bill representation
    final billNumber = newData?['bill_number'] ?? oldData?['bill_number'];
    if (billNumber != null) {
      return 'Bill #$billNumber';
    }
    if (entityType.toLowerCase().contains('bill')) {
      final idShort = entityId != null && entityId.length > 6 ? entityId.substring(entityId.length - 6) : (entityId ?? '');
      return idShort.isNotEmpty ? 'Bill #$idShort' : 'Bill';
    }

    // 3. Order representation (with table info)
    final orderNumber = newData?['order_number'] ?? oldData?['order_number'];
    final tableNumber = newData?['table_number'] ?? oldData?['table_number'];

    if (orderNumber != null && tableNumber != null) {
      return 'Table $tableNumber / Order #$orderNumber';
    } else if (orderNumber != null) {
      return 'Order #$orderNumber';
    } else if (tableNumber != null) {
      return 'Table $tableNumber';
    }

    // 4. Expense representation
    if (entityType.toLowerCase().contains('expense')) {
      final category = newData?['category'] ?? oldData?['category'] ?? newData?['category_name'] ?? 'Expense';
      final amt = newData?['amount'] ?? oldData?['amount'];
      return amt != null ? '$category (₹$amt)' : '$category';
    }

    // 5. Fallback formatting
    final cleanType = entityType
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '')
        .join(' ');

    if (entityId != null && entityId.isNotEmpty) {
      final shortId = entityId.length > 8 ? entityId.substring(entityId.length - 6) : entityId;
      return '$cleanType #$shortId';
    }
    return cleanType;
  }

  static String _computeChangeSummary({
    required String rawAction,
    required String entityType,
    required Map<String, dynamic>? oldData,
    required Map<String, dynamic>? newData,
    required String actionTitle,
  }) {
    final od = oldData;
    final nd = newData;

    // 1. Price change
    final oldPrice = od?['price'] ?? od?['base_price'];
    final newPrice = nd?['price'] ?? nd?['base_price'];
    if (oldPrice != null && newPrice != null && oldPrice.toString() != newPrice.toString()) {
      return '₹$oldPrice → ₹$newPrice';
    }

    // 2. Status change
    final oldStatus = od?['status']?.toString();
    final newStatus = nd?['status']?.toString();
    if (oldStatus != null && newStatus != null && oldStatus.toLowerCase() != newStatus.toLowerCase()) {
      return '${_toTitle(oldStatus)} → ${_toTitle(newStatus)}';
    }

    // 3. Availability change
    if (od != null && nd != null && od['is_available'] != null && nd['is_available'] != null && od['is_available'] != nd['is_available']) {
      final from = od['is_available'] == true ? 'In Stock' : 'Out of Stock';
      final to = nd['is_available'] == true ? 'In Stock' : 'Out of Stock';
      return '$from → $to';
    }

    // 4. Active / Inactive change
    if (od != null && nd != null && od['is_active'] != null && nd['is_active'] != null && od['is_active'] != nd['is_active']) {
      final from = od['is_active'] == true ? 'Active' : 'Inactive';
      final to = nd['is_active'] == true ? 'Active' : 'Inactive';
      return '$from → $to';
    }

    // 5. Table Swapping
    if (nd != null && nd['from_table'] != null && nd['to_table'] != null) {
      return 'Table ${nd['from_table']} → Table ${nd['to_table']}';
    }

    // 6. Role change
    final oldRole = oldData?['role']?.toString();
    final newRole = newData?['role']?.toString();
    if (oldRole != null && newRole != null && oldRole.toLowerCase() != newRole.toLowerCase()) {
      return '${_formatRoleName(oldRole)} → ${_formatRoleName(newRole)}';
    }

    // 7. Amount / Total change
    final oldTotal = oldData?['total_amount'] ?? oldData?['total'] ?? oldData?['amount'];
    final newTotal = newData?['total_amount'] ?? newData?['total'] ?? newData?['amount'];
    if (oldTotal != null && newTotal != null && oldTotal.toString() != newTotal.toString()) {
      return '₹$oldTotal → ₹$newTotal';
    }

    // 8. Newly Created or Initial Record
    if (oldData == null || oldData.isEmpty) {
      if (newTotal != null) {
        return 'Total: ₹$newTotal';
      }
      if (newPrice != null) {
        return 'Price: ₹$newPrice';
      }
      if (newStatus != null) {
        return 'Status: ${_toTitle(newStatus)}';
      }
      return 'New record created';
    }

    // 9. Single field difference detection
    final differences = <String>[];
    for (final key in newData?.keys ?? <String>[]) {
      if (key == 'updated_at' || key == 'created_at' || key == 'id') continue;
      if (oldData.containsKey(key) && oldData[key]?.toString() != newData![key]?.toString()) {
        final cleanKey = key.replaceAll('_', ' ');
        differences.add('$cleanKey: ${oldData[key]} → ${newData[key]}');
        if (differences.length >= 2) break;
      }
    }

    if (differences.isNotEmpty) {
      return differences.join(', ');
    }

    // 10. Fallback clean summary
    if (rawAction.toLowerCase() == 'delete') {
      return 'Record deleted';
    }
    return 'Record updated';
  }

  static String _formatStateSummary(Map<String, dynamic>? data, {required bool isPrevious}) {
    if (data == null || data.isEmpty) {
      return isPrevious ? 'Not available (Initial creation or not captured)' : 'No details recorded';
    }

    final buffer = StringBuffer();
    final keyFields = ['price', 'base_price', 'amount', 'total_amount', 'status', 'is_available', 'is_active', 'role', 'table_number', 'bill_number', 'category', 'notes'];

    bool hasKeyField = false;
    for (final field in keyFields) {
      if (data.containsKey(field) && data[field] != null) {
        hasKeyField = true;
        final label = field.replaceAll('_', ' ').split(' ').map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '').join(' ');
        var val = data[field];
        if (field.contains('price') || field.contains('amount')) {
          val = '₹$val';
        }
        buffer.writeln('$label: $val');
      }
    }

    if (!hasKeyField) {
      // Print first 4 entries
      int count = 0;
      data.forEach((k, v) {
        if (count < 4 && k != 'id' && k != 'created_at' && k != 'updated_at') {
          buffer.writeln('${k.replaceAll('_', ' ')}: $v');
          count++;
        }
      });
    }

    final result = buffer.toString().trim();
    return result.isEmpty ? 'Data state recorded' : result;
  }

  static String? _extractReason(Map<String, dynamic>? newData, Map<String, dynamic>? oldData) {
    final possibleKeys = ['reason', 'notes', 'remark', 'remarks', 'edit_reason', 'cancel_reason', 'cancellation_reason'];
    for (final key in possibleKeys) {
      if (newData?[key] != null && newData![key].toString().trim().isNotEmpty) {
        return newData[key].toString().trim();
      }
      if (oldData?[key] != null && oldData![key].toString().trim().isNotEmpty) {
        return oldData[key].toString().trim();
      }
    }
    return null;
  }

  static String _toTitle(String s) {
    if (s.isEmpty) return s;
    return s.split('_').map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}' : '').join(' ');
  }

  // Visual Theme helpers
  Color get moduleColor {
    switch (module) {
      case 'MENU':
        return const Color(0xFFE65100); // Warm Amber / Orange
      case 'ORDERS':
        return const Color(0xFF2E7D32); // Fresh Green
      case 'BILLING':
        return const Color(0xFF1565C0); // Royal Blue
      case 'EXPENSES':
        return const Color(0xFFC2185B); // Crimson / Magenta
      case 'USERS':
        return const Color(0xFF6A1B9A); // Deep Purple
      case 'SETTINGS':
        return const Color(0xFF455A64); // Slate Grey
      default:
        return const Color(0xFF2D6A4F);
    }
  }

  IconData get moduleIcon {
    switch (module) {
      case 'MENU':
        return Icons.restaurant_menu_rounded;
      case 'ORDERS':
        return Icons.shopping_bag_outlined;
      case 'BILLING':
        return Icons.receipt_long_rounded;
      case 'EXPENSES':
        return Icons.account_balance_wallet_outlined;
      case 'USERS':
        return Icons.person_outline_rounded;
      case 'SETTINGS':
        return Icons.tune_rounded;
      default:
        return Icons.security_rounded;
    }
  }

  Color get actionColor {
    final act = rawAction.toLowerCase();
    if (act.contains('cancel') || act.contains('void') || act.contains('delete') || act.contains('deactivate')) {
      return const Color(0xFFD32F2F); // Red
    }
    if (act.contains('price') || act.contains('update') || act.contains('correct') || act.contains('swap')) {
      return const Color(0xFF0277BD); // Blue
    }
    if (act.contains('create') || act.contains('insert') || act.contains('complete') || act.contains('generate') || act.contains('activate')) {
      return const Color(0xFF2E7D32); // Green
    }
    return const Color(0xFFE65100); // Amber
  }
}
