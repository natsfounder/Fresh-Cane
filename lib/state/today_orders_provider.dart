import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/today_order_model.dart';
import '../repositories/order_repository.dart';
import '../services/supabase_service.dart';
import 'server_order_provider.dart';

/// Immutable state for the authenticated Server's Today Orders feed.
@immutable
class TodayOrdersState {
  final List<TodayOrder> orders;
  final bool isLoading;
  final bool isRefreshing;
  final String? errorMessage;

  const TodayOrdersState({
    this.orders = const [],
    this.isLoading = false,
    this.isRefreshing = false,
    this.errorMessage,
  });

  /// List of orders excluding empty consolidated secondary orders (0 items & ₹0)
  List<TodayOrder> get visibleOrders =>
      orders.where((o) => !o.isConsolidatedEmpty).toList();

  /// True if the order history has successfully loaded and is empty.
  bool get isEmpty => !isLoading && !isRefreshing && visibleOrders.isEmpty;

  /// True if the order history has loaded with at least one order.
  bool get isSuccess => !isLoading && errorMessage == null;

  /// Total count of valid customer orders recorded today (excluding ghost empty orders).
  int get totalOrdersCount => visibleOrders.length;

  /// Total count of active (non-cancelled) valid orders recorded today.
  int get activeOrdersCount => visibleOrders.where((o) => o.isActive).length;

  /// Total count of unique customers served today (among visible orders).
  int get totalCustomersCount {
    final uniqueKeys = <String>{};
    for (final o in visibleOrders) {
      final key = o.customerId ?? '${o.customerName}_${o.tableNumber}';
      uniqueKeys.add(key);
    }
    return uniqueKeys.length;
  }

  /// Total count of cancelled orders recorded today.
  int get cancelledOrdersCount => orders.where((o) => o.isCancelled).length;

  /// Authoritative total billable revenue for today's active orders (cancelled orders contribute ₹0).
  double get totalBillableAmount =>
      visibleOrders.fold(0.0, (sum, o) => sum + o.billableAmount);

  TodayOrdersState copyWith({
    List<TodayOrder>? orders,
    bool? isLoading,
    bool? isRefreshing,
    String? Function()? errorMessage,
  }) {
    return TodayOrdersState(
      orders: orders ?? this.orders,
      isLoading: isLoading ?? this.isLoading,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      errorMessage: errorMessage != null ? errorMessage() : this.errorMessage,
    );
  }
}

/// Riverpod Notifier managing the authenticated Server's Today Orders.
///
/// Strictly isolates to the authenticated server's own order history and
/// the current Asia/Kolkata business day.
/// Automatically subscribes to Supabase Realtime so that when bills or orders
/// are created or completed by Cashier, the screen updates automatically.
class TodayOrdersNotifier extends Notifier<TodayOrdersState> {
  bool _mounted = true;
  RealtimeChannel? _realtimeChannel;

  @override
  TodayOrdersState build() {
    _mounted = true;
    ref.onDispose(() {
      _mounted = false;
      _realtimeChannel?.unsubscribe();
    });

    _subscribeToRealtime();
    Future.microtask(() => loadOrders());
    return const TodayOrdersState(isLoading: true);
  }

  OrderRepository get _repository => ref.read(orderRepositoryProvider);

  void _subscribeToRealtime() {
    _realtimeChannel?.unsubscribe();
    final client = SupabaseService.client;
    _realtimeChannel = client
        .channel('server_today_orders_sync')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          callback: (_) {
            if (_mounted) refresh();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'bills',
          callback: (_) {
            if (_mounted) refresh();
          },
        )
        .subscribe();
  }

  /// Fetch today's orders for the authenticated server from Supabase.
  Future<void> loadOrders() async {
    if (!_mounted) return;
    state = state.copyWith(isLoading: true, errorMessage: () => null);

    try {
      final orders = await _repository.fetchTodayOrders();
      if (!_mounted) return;
      state = state.copyWith(
        orders: orders,
        isLoading: false,
      );
    } catch (e) {
      if (!_mounted) return;
      debugPrint('Error loading today orders: $e');
      state = state.copyWith(
        isLoading: false,
        errorMessage: () => 'Failed to load today orders: $e',
      );
    }
  }

  /// Explicitly refresh the today orders feed.
  Future<void> refresh() async {
    if (!_mounted) return;
    try {
      final orders = await _repository.fetchTodayOrders();
      if (!_mounted) return;
      state = state.copyWith(
        orders: orders,
        isRefreshing: false,
      );
    } catch (e) {
      debugPrint('Error refreshing today orders: $e');
      if (!_mounted) return;
      state = state.copyWith(
        isRefreshing: false,
        errorMessage: () => 'Failed to refresh orders: $e',
      );
    }
  }
}

/// Global provider for the authenticated Server's Today Orders feed.
final todayOrdersProvider =
    NotifierProvider<TodayOrdersNotifier, TodayOrdersState>(
  TodayOrdersNotifier.new,
);
