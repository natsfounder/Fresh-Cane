import 'package:flutter/foundation.dart' hide Category;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/errors/domain_exceptions.dart';
import '../models/models.dart';
import '../services/supabase_service.dart';

/// Repository handling dining tables, table sessions, multi-customer groups,
/// menu categories, products, customer lookups, order submission, cancellation,
/// customer finish handoff, and today's orders.
class OrderRepository {
  final SupabaseClient _client;

  OrderRepository([SupabaseClient? client])
      : _client = client ?? SupabaseService.client;

  FreshCaneException _mapPostgrestException(PostgrestException e) {
    final msg = e.message;
    if (msg.contains('Unauthorized')) {
      return UnauthorizedException(msg);
    }
    if (msg.contains('completed ordering') ||
        msg.contains('cannot place new orders') ||
        msg.contains('All customers in this table session have finished ordering')) {
      return CustomerCannotOrderException(msg);
    }
    if (msg.contains('already billed') || msg.contains('already closed')) {
      return CustomerNoLongerActiveException(msg);
    }
    if (msg.contains('Customer not found') || msg.contains('Table not found')) {
      return CustomerNotFoundException(msg);
    }
    return RepositoryFailureException(msg, e);
  }

  /// Fetch all active restaurant tables ordered by table number with active session details.
  Future<List<RestaurantTable>> fetchTables() async {
    try {
      try {
        final data = await _client
            .from('restaurant_tables')
            .select('*, table_sessions(id, status, table_session_customers(id, status))')
            .eq('is_active', true)
            .order('table_number');

        return (data as List)
            .map((item) => RestaurantTable.fromJson(item as Map<String, dynamic>))
            .toList();
      } catch (nestedErr) {
        debugPrint('Nested session query fallback: $nestedErr');
        final data = await _client
            .from('restaurant_tables')
            .select()
            .eq('is_active', true)
            .order('table_number');

        return (data as List)
            .map((item) => RestaurantTable.fromJson(item as Map<String, dynamic>))
            .toList();
      }
    } on PostgrestException catch (e) {
      debugPrint('Postgrest error fetching tables: ${e.message}');
      throw _mapPostgrestException(e);
    } catch (e) {
      debugPrint('Unexpected error fetching tables: $e');
      throw RepositoryFailureException('Unable to load tables. Please check your network.', e);
    }
  }

  /// Realtime stream of active restaurant tables to reactively reflect
  /// occupancy and finished customer updates across all staff devices.
  Stream<List<RestaurantTable>> streamTables() {
    return _client
        .from('restaurant_tables')
        .stream(primaryKey: ['id'])
        .order('table_number')
        .asyncMap((_) async {
          try {
            return await fetchTables();
          } catch (_) {
            return [];
          }
        });
  }

  /// Open or retrieve an active dining session for a table.
  Future<TableSessionDetails> openOrGetTableSession(String tableId) async {
    try {
      final response = await _client.rpc(
        'open_or_get_table_session',
        params: {'p_table_id': tableId},
      );

      if (response == null || response is! Map) {
        throw const RepositoryFailureException('Invalid response returned from server for table session');
      }

      return TableSessionDetails.fromJson(Map<String, dynamic>.from(response));
    } on PostgrestException catch (e) {
      debugPrint('PostgrestException in openOrGetTableSession: ${e.message}');
      throw _mapPostgrestException(e);
    } catch (e) {
      debugPrint('Unexpected error in openOrGetTableSession: $e');
      rethrow;
    }
  }

  /// Fetch current active session details, customers, and orders for a table.
  Future<TableSessionDetails> fetchActiveTableSession(String tableId) async {
    try {
      final response = await _client.rpc(
        'get_active_table_session_details',
        params: {'p_table_id': tableId},
      );

      if (response == null || response is! Map) {
        throw const RepositoryFailureException('Invalid response returned from server');
      }

      return TableSessionDetails.fromJson(Map<String, dynamic>.from(response));
    } on PostgrestException catch (e) {
      debugPrint('PostgrestException in fetchActiveTableSession: ${e.message}');
      throw _mapPostgrestException(e);
    } catch (e) {
      debugPrint('Unexpected error in fetchActiveTableSession: $e');
      rethrow;
    }
  }

  /// Add a customer to an active table session.
  Future<Map<String, dynamic>> addCustomerToSession(
    String sessionId, {
    String? name,
    String? phone,
  }) async {
    try {
      final response = await _client.rpc(
        'add_customer_to_table_session',
        params: {
          'p_session_id': sessionId,
          'p_name': name?.trim().isNotEmpty == true ? name!.trim() : null,
          'p_phone': phone?.trim().isNotEmpty == true ? phone!.trim() : null,
        },
      );

      if (response == null || response is! Map) {
        throw const RepositoryFailureException('Invalid response returned when adding customer');
      }

      return Map<String, dynamic>.from(response);
    } on PostgrestException catch (e) {
      debugPrint('PostgrestException in addCustomerToSession: ${e.message}');
      throw _mapPostgrestException(e);
    } catch (e) {
      debugPrint('Unexpected error in addCustomerToSession: $e');
      rethrow;
    }
  }

  /// Fetch all active categories ordered by display order.
  Future<List<Category>> fetchCategories() async {
    try {
      final data = await _client
          .from('categories')
          .select()
          .eq('is_active', true)
          .order('display_order');

      return (data as List)
          .map((item) => Category.fromJson(item as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      debugPrint('Postgrest error fetching categories: ${e.message}');
      throw _mapPostgrestException(e);
    } catch (e) {
      debugPrint('Unexpected error fetching categories: $e');
      throw RepositoryFailureException('Unable to load categories. Please check your network.', e);
    }
  }

  /// Fetch all active menu products ordered by display order.
  /// When [onlyAvailable] is true, filters out out-of-stock items.
  Future<List<MenuItem>> fetchMenuItems({bool onlyAvailable = true}) async {
    try {
      var query = _client
          .from('menu_items')
          .select()
          .eq('is_active', true);

      if (onlyAvailable) {
        query = query.eq('is_available', true);
      }

      final data = await query.order('display_order');

      return (data as List)
          .map((item) => MenuItem.fromJson(item as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      debugPrint('Postgrest error fetching menu items: ${e.message}');
      throw _mapPostgrestException(e);
    } catch (e) {
      debugPrint('Unexpected error fetching menu items: $e');
      throw RepositoryFailureException('Unable to load menu items. Please check your network.', e);
    }
  }

  /// Fetch all active menu add-ons.
  Future<List<MenuAddon>> fetchAddons({bool onlyActive = true}) async {
    try {
      var query = _client.from('menu_addons').select();
      if (onlyActive) {
        query = query.eq('is_active', true);
      }
      final data = await query.order('name');
      final list = (data as List)
          .map((item) => MenuAddon.fromJson(item as Map<String, dynamic>))
          .toList();
      return list.isNotEmpty ? list : MenuAddon.defaultAddons;
    } catch (e) {
      debugPrint('Error fetching addons (fallback to default): $e');
      return MenuAddon.defaultAddons;
    }
  }

  /// Look up an existing customer by 10-digit Indian phone number.
  Future<Customer?> fetchCustomerByPhone(String rawPhone) async {
    final cleaned = rawPhone.replaceAll(RegExp(r'\D'), '');
    final phone = cleaned.length >= 10
        ? cleaned.substring(cleaned.length - 10)
        : cleaned;

    if (phone.length != 10) return null;

    try {
      final data = await _client
          .from('customers')
          .select()
          .eq('phone', phone)
          .maybeSingle();

      if (data == null) return null;
      return Customer.fromJson(data);
    } catch (e) {
      debugPrint('Error looking up customer by phone: $e');
      return null;
    }
  }

  /// Submit a dine-in order atomically via PostgreSQL RPC `submit_dine_in_order`.
  ///
  /// Supports multi-customer and repeat orders linked to a table session.
  /// Enforces database-level customer status guard (customer must be active).
  Future<Map<String, dynamic>> submitDineInOrder({
    required String tableId,
    String? sessionId,
    String? sessionCustomerId,
    String? customerName,
    String? customerPhone,
    required List<CartItem> items,
    String? notes,
  }) async {
    if (items.isEmpty) {
      throw const RepositoryFailureException('Cannot submit an order with no items');
    }

    final itemsPayload = items.map((i) => i.toRpcJson()).toList();

    try {
      final response = await _client.rpc(
        'submit_dine_in_order',
        params: {
          'p_table_id': tableId,
          'p_session_id': sessionId,
          'p_session_customer_id': sessionCustomerId,
          'p_customer_name': customerName?.trim().isNotEmpty == true
              ? customerName!.trim()
              : null,
          'p_customer_phone': customerPhone?.trim().isNotEmpty == true
              ? customerPhone!.trim()
              : null,
          'p_items': itemsPayload,
          'p_notes': notes?.trim().isNotEmpty == true ? notes!.trim() : null,
        },
      );

      if (response == null || response is! Map) {
        throw const RepositoryFailureException('Invalid response returned from server');
      }

      return Map<String, dynamic>.from(response);
    } on PostgrestException catch (e) {
      debugPrint('PostgrestException during submit_dine_in_order: ${e.message}');
      throw _mapPostgrestException(e);
    } on FreshCaneException {
      rethrow;
    } catch (e) {
      debugPrint('Unexpected error during order submission: $e');
      throw RepositoryFailureException('Failed to submit order: $e', e);
    }
  }

  /// Cancel an individual server order independently.
  ///
  /// Cancelling an order marks its status as 'cancelled', preserves the record
  /// for auditability, and does NOT cancel the table session or other orders.
  Future<Map<String, dynamic>> cancelOrder(
    String orderId, {
    String? reason,
  }) async {
    try {
      final response = await _client.rpc(
        'cancel_server_order',
        params: {
          'p_order_id': orderId,
          'p_reason': reason?.trim().isNotEmpty == true
              ? reason!.trim()
              : 'Cancelled by server',
        },
      );

      if (response == null || response is! Map) {
        throw const RepositoryFailureException('Invalid response returned from server');
      }

      return Map<String, dynamic>.from(response);
    } on PostgrestException catch (e) {
      debugPrint('PostgrestException during cancel_server_order: ${e.message}');
      throw _mapPostgrestException(e);
    } catch (e) {
      debugPrint('Unexpected error during order cancellation: $e');
      rethrow;
    }
  }

  /// Delete a session customer from table session when they have no active orders.
  Future<Map<String, dynamic>> deleteSessionCustomer(String customerId) async {
    try {
      final response = await _client.rpc(
        'delete_session_customer',
        params: {'p_customer_id': customerId},
      );

      if (response == null || response is! Map) {
        throw const RepositoryFailureException('Invalid response returned from server');
      }

      return Map<String, dynamic>.from(response);
    } on PostgrestException catch (e) {
      debugPrint('PostgrestException during delete_session_customer: ${e.message}');
      throw _mapPostgrestException(e);
    } catch (e) {
      debugPrint('Unexpected error during delete_session_customer: $e');
      rethrow;
    }
  }

  /// Transfer a customer and all their active orders to another table.
  Future<Map<String, dynamic>> swapCustomerTable({
    required String customerId,
    required String targetTableId,
  }) async {
    try {
      final response = await _client.rpc(
        'swap_customer_table',
        params: {
          'p_customer_id': customerId,
          'p_target_table_id': targetTableId,
        },
      );

      if (response == null || response is! Map) {
        throw const RepositoryFailureException('Invalid response returned from server for table swap');
      }

      return Map<String, dynamic>.from(response);
    } on PostgrestException catch (e) {
      debugPrint('PostgrestException during swap_customer_table: ${e.message}');
      throw _mapPostgrestException(e);
    } catch (e) {
      debugPrint('Unexpected error during swap_customer_table: $e');
      rethrow;
    }
  }

  /// Fetch details of an existing server order, including its line items.
  Future<Map<String, dynamic>> fetchOrderDetails(String orderId) async {
    try {
      final response = await _client.rpc(
        'get_server_order_details',
        params: {'p_order_id': orderId},
      );

      if (response == null || response is! Map) {
        throw const RepositoryFailureException('Invalid response returned from server');
      }

      return Map<String, dynamic>.from(response);
    } on PostgrestException catch (e) {
      debugPrint('PostgrestException during get_server_order_details: ${e.message}');
      throw _mapPostgrestException(e);
    } catch (e) {
      debugPrint('Unexpected error fetching order details: $e');
      rethrow;
    }
  }

  /// Update an existing server order in-place without creating a new order.
  Future<Map<String, dynamic>> updateOrder(
    String orderId, {
    required List<CartItem> items,
    String? notes,
  }) async {
    if (items.isEmpty) {
      throw const RepositoryFailureException('Cannot update an order with no items');
    }

    final itemsPayload = items.map((i) => i.toRpcJson()).toList();

    try {
      final response = await _client.rpc(
        'update_server_order',
        params: {
          'p_order_id': orderId,
          'p_items': itemsPayload,
          'p_notes': notes?.trim().isNotEmpty == true ? notes!.trim() : null,
        },
      );

      if (response == null || response is! Map) {
        throw const RepositoryFailureException('Invalid response returned from server');
      }

      return Map<String, dynamic>.from(response);
    } on PostgrestException catch (e) {
      debugPrint('PostgrestException during update_server_order: ${e.message}');
      throw _mapPostgrestException(e);
    } catch (e) {
      debugPrint('Unexpected error updating order: $e');
      rethrow;
    }
  }


  /// Transactionally finish customer ordering via RPC `finish_table_session_customer`.
  ///
  /// Transitions customer from active to finished. If all customers in the session
  /// have completed ordering, table_sessions.status transitions to billing.
  /// Handled idempotently if customer was already finished.
  Future<Map<String, dynamic>> finishCustomer(String customerId) async {
    try {
      final response = await _client.rpc(
        'finish_table_session_customer',
        params: {'p_customer_id': customerId},
      );

      if (response == null || response is! Map) {
        throw const RepositoryFailureException('Invalid response returned when finishing customer');
      }

      return Map<String, dynamic>.from(response);
    } on PostgrestException catch (e) {
      debugPrint('PostgrestException during finishCustomer: ${e.message}');
      throw _mapPostgrestException(e);
    } on FreshCaneException {
      rethrow;
    } catch (e) {
      debugPrint('Unexpected error during finishCustomer: $e');
      throw RepositoryFailureException('Failed to finish customer: $e', e);
    }
  }

  /// Fetch authenticated Server's orders for the current Asia/Kolkata business day.
  ///
  /// The database derives server identity from auth.uid() and determines the
  /// business day boundary in IST (+05:30). Client clock has zero influence.
  Future<List<TodayOrder>> fetchTodayOrders({DateTime? date}) async {
    try {
      final params = <String, dynamic>{};
      if (date != null) {
        final dateStr =
            '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        params['p_date'] = dateStr;
      }

      final response = await _client.rpc(
        'get_server_today_orders',
        params: params,
      );

      if (response == null || response is! List) {
        return const [];
      }

      return response
          .map((item) => TodayOrder.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList();
    } on PostgrestException catch (e) {
      debugPrint('PostgrestException during fetchTodayOrders: ${e.message}');
      throw _mapPostgrestException(e);
    } on FreshCaneException {
      rethrow;
    } catch (e) {
      debugPrint('Unexpected error during fetchTodayOrders: $e');
      throw RepositoryFailureException('Failed to fetch today orders: $e', e);
    }
  }

  /// Close table session and release table back to available.
  Future<void> closeTableSession(String tableId) async {
    try {
      await _client.rpc(
        'close_table_session',
        params: {'p_table_id': tableId},
      );
    } catch (e) {
      debugPrint('Error closing table session: $e');
      rethrow;
    }
  }
}
