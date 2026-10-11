import 'package:flutter/foundation.dart';

/// Distinct customer order lifecycle states within a table session.
enum CustomerStatus {
  active,
  finished,
  billed,
  closed;

  static CustomerStatus fromString(String? value) {
    switch (value?.toLowerCase().trim()) {
      case 'finished':
        return CustomerStatus.finished;
      case 'billed':
        return CustomerStatus.billed;
      case 'closed':
        return CustomerStatus.closed;
      case 'active':
      default:
        return CustomerStatus.active;
    }
  }

  String toDbString() => name;
}

/// Table session dining & billing lifecycle states.
enum SessionStatus {
  available,
  active,
  billing,
  completed,
  cancelled;

  static SessionStatus fromString(String? value) {
    switch (value?.toLowerCase().trim()) {
      case 'active':
        return SessionStatus.active;
      case 'billing':
        return SessionStatus.billing;
      case 'completed':
        return SessionStatus.completed;
      case 'cancelled':
        return SessionStatus.cancelled;
      case 'available':
      default:
        return SessionStatus.available;
    }
  }

  String toDbString() => name;
}

/// Immutable summary of an individual order within a table session.
@immutable
class SessionOrderSummary {
  final String id;
  final String orderNumber;
  final String status;
  final double totalAmount;
  final int itemsCount;
  final String itemsSummary;
  final String? billNumber;
  final DateTime? createdAt;
  final DateTime? cancelledAt;
  final String? cancellationReason;

  const SessionOrderSummary({
    required this.id,
    required this.orderNumber,
    required this.status,
    required this.totalAmount,
    required this.itemsCount,
    required this.itemsSummary,
    this.billNumber,
    this.createdAt,
    this.cancelledAt,
    this.cancellationReason,
  });

  /// True if order is active and contributes to the active billable total (not cancelled and not completed).
  bool get isActive => status != 'cancelled' && status != 'completed';

  /// True if order has already been completed/settled.
  bool get isCompleted => status == 'completed';

  /// True if order is cancelled.
  bool get isCancelled => status == 'cancelled';

  factory SessionOrderSummary.fromJson(Map<String, dynamic> json) {
    return SessionOrderSummary(
      id: json['id'] as String,
      orderNumber: json['order_number'] as String? ?? '',
      status: json['status'] as String? ?? 'open',
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0.0,
      itemsCount: (json['items_count'] as num?)?.toInt() ?? 0,
      itemsSummary: json['items_summary'] as String? ?? '',
      billNumber: json['bill_number'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())?.toLocal()
          : null,
      cancelledAt: json['cancelled_at'] != null
          ? DateTime.tryParse(json['cancelled_at'].toString())?.toLocal()
          : null,
      cancellationReason: json['cancellation_reason'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'order_number': orderNumber,
      'status': status,
      'total_amount': totalAmount,
      'items_count': itemsCount,
      'items_summary': itemsSummary,
      'bill_number': billNumber,
      'created_at': createdAt?.toIso8601String(),
      'cancelled_at': cancelledAt?.toIso8601String(),
      'cancellation_reason': cancellationReason,
    };
  }
}

/// Immutable representation of a customer seated at a table session.
@immutable
class SessionCustomer {
  final String id;
  final String sessionId;
  final String customerLabel;
  final String? customerName;
  final String? customerPhone;
  final CustomerStatus status;
  final DateTime? finishedAt;
  final String? finishedBy;
  final List<SessionOrderSummary> orders;
  final int activeOrdersCount;
  final double activeTotal;

  const SessionCustomer({
    required this.id,
    required this.sessionId,
    required this.customerLabel,
    this.customerName,
    this.customerPhone,
    this.status = CustomerStatus.active,
    this.finishedAt,
    this.finishedBy,
    this.orders = const [],
    this.activeOrdersCount = 0,
    this.activeTotal = 0.0,
  });

  /// Display name or label (e.g. "Customer 1" or "Rajesh").
  String get displayName =>
      (customerName != null && customerName!.trim().isNotEmpty)
          ? customerName!.trim()
          : customerLabel;

  /// True if customer is currently active and can place new dine-in orders.
  bool get isActive => status == CustomerStatus.active;

  /// True if customer has finished ordering and is awaiting cashier billing.
  bool get isFinished => status == CustomerStatus.finished;

  /// True if customer orders have been billed by Cashier.
  bool get isBilled => status == CustomerStatus.billed;

  /// True if customer session lifecycle is closed.
  bool get isClosed => status == CustomerStatus.closed;

  /// Server guard: customer may only order if in active status.
  bool get canOrder => isActive;

  /// Cashier handoff guard: customer is ready for billing when finished.
  /// IMPORTANT: Does NOT depend on activeTotal > 0.
  bool get isReadyForBilling => status == CustomerStatus.finished;

  /// Cashier filter: True only if customer has finished dining and has unpaid active orders.
  bool get hasUnpaidOrders =>
      isFinished &&
      status != CustomerStatus.billed &&
      status != CustomerStatus.closed &&
      orders.any((o) => o.isActive);

  factory SessionCustomer.fromJson(Map<String, dynamic> json) {
    final rawOrders = json['orders'] as List<dynamic>? ?? [];
    final parsedOrders = rawOrders
        .map((e) => SessionOrderSummary.fromJson(e as Map<String, dynamic>))
        .toList();

    return SessionCustomer(
      id: json['id'] as String,
      sessionId: json['session_id'] as String? ?? '',
      customerLabel: json['customer_label'] as String? ?? 'Customer',
      customerName: json['customer_name'] as String?,
      customerPhone: json['customer_phone'] as String?,
      status: CustomerStatus.fromString(json['status'] as String?),
      finishedAt: json['finished_at'] != null
          ? DateTime.tryParse(json['finished_at'].toString())?.toLocal()
          : null,
      finishedBy: json['finished_by'] as String?,
      orders: parsedOrders,
      activeOrdersCount: (json['active_orders_count'] as num?)?.toInt() ??
          parsedOrders.where((o) => o.isActive).length,
      activeTotal: (json['active_total'] as num?)?.toDouble() ??
          parsedOrders
              .where((o) => o.isActive)
              .fold(0.0, (sum, o) => sum + o.totalAmount),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'session_id': sessionId,
      'customer_label': customerLabel,
      'customer_name': customerName,
      'customer_phone': customerPhone,
      'status': status.toDbString(),
      'finished_at': finishedAt?.toIso8601String(),
      'finished_by': finishedBy,
      'orders': orders.map((o) => o.toJson()).toList(),
      'active_orders_count': activeOrdersCount,
      'active_total': activeTotal,
    };
  }
}

/// Immutable aggregated table session details.
@immutable
class TableSessionDetails {
  final String tableId;
  final String tableNumber;
  final int seatingCapacity;
  final String tableStatus;
  final String? sessionId;
  final String status;
  final DateTime? openedAt;
  final List<SessionCustomer> customers;
  final double activeTotal;
  final int activeOrdersCount;

  const TableSessionDetails({
    required this.tableId,
    required this.tableNumber,
    required this.seatingCapacity,
    required this.tableStatus,
    this.sessionId,
    required this.status,
    this.openedAt,
    this.customers = const [],
    this.activeTotal = 0.0,
    this.activeOrdersCount = 0,
  });

  /// Strongly-typed SessionStatus enum representation.
  SessionStatus get sessionStatus => SessionStatus.fromString(status);

  /// True if session is active (customers currently ordering).
  bool get isActive => status == 'active';

  /// True if all customers finished and session is queued for Cashier billing.
  bool get isBilling => status == 'billing';

  /// True if session has completed and closed.
  bool get isCompleted => status == 'completed';

  /// True if session was cancelled.
  bool get isCancelled => status == 'cancelled';

  /// True if table has an active session with seated customers (active or billing).
  bool get hasActiveSession =>
      sessionId != null && (status == 'active' || status == 'billing');

  /// True if physical table is available for new party seating.
  /// IMPORTANT: Physical table availability is distinct from session billing state.
  bool get isAvailable =>
      status == 'available' || (!hasActiveSession && tableStatus == 'available');

  TableSessionDetails copyWith({
    String? tableId,
    String? tableNumber,
    int? seatingCapacity,
    String? tableStatus,
    String? sessionId,
    String? status,
    DateTime? openedAt,
    List<SessionCustomer>? customers,
    double? activeTotal,
    int? activeOrdersCount,
  }) {
    return TableSessionDetails(
      tableId: tableId ?? this.tableId,
      tableNumber: tableNumber ?? this.tableNumber,
      seatingCapacity: seatingCapacity ?? this.seatingCapacity,
      tableStatus: tableStatus ?? this.tableStatus,
      sessionId: sessionId ?? this.sessionId,
      status: status ?? this.status,
      openedAt: openedAt ?? this.openedAt,
      customers: customers ?? this.customers,
      activeTotal: activeTotal ?? this.activeTotal,
      activeOrdersCount: activeOrdersCount ?? this.activeOrdersCount,
    );
  }

  factory TableSessionDetails.fromJson(Map<String, dynamic> json) {
    final rawCustomers = json['customers'] as List<dynamic>? ?? [];
    final parsedCustomers = rawCustomers
        .map((e) => SessionCustomer.fromJson(e as Map<String, dynamic>))
        .toList();

    return TableSessionDetails(
      tableId: json['table_id'] as String,
      tableNumber: json['table_number'] as String,
      seatingCapacity: (json['seating_capacity'] as num?)?.toInt() ?? 4,
      tableStatus: json['table_status'] as String? ?? 'available',
      sessionId: json['session_id'] as String?,
      status: json['status'] as String? ?? 'available',
      openedAt: json['opened_at'] != null
          ? DateTime.tryParse(json['opened_at'].toString())?.toLocal()
          : null,
      customers: parsedCustomers,
      activeTotal: (json['active_total'] as num?)?.toDouble() ?? 0.0,
      activeOrdersCount: (json['active_orders_count'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'table_id': tableId,
      'table_number': tableNumber,
      'seating_capacity': seatingCapacity,
      'table_status': tableStatus,
      'session_id': sessionId,
      'status': status,
      'opened_at': openedAt?.toIso8601String(),
      'customers': customers.map((c) => c.toJson()).toList(),
      'active_total': activeTotal,
      'active_orders_count': activeOrdersCount,
    };
  }
}
