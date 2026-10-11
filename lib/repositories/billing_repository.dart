import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/errors/domain_exceptions.dart';
import '../models/models.dart';
import '../services/supabase_service.dart';

/// Repository handling Cashier billing operations, tax invoice generation,
/// split payment settlement, table session closure, and parcel order placement.
class BillingRepository {
  final SupabaseClient _client;

  BillingRepository([SupabaseClient? client])
      : _client = client ?? SupabaseService.client;

  FreshCaneException _mapPostgrestException(PostgrestException e) {
    final msg = e.message;
    if (msg.contains('Unauthorized')) {
      return UnauthorizedException(msg);
    }
    if (msg.contains('already exists')) {
      return const RepositoryFailureException('A bill already exists for this order.');
    }
    if (msg.contains('not billable') || msg.contains('no active items')) {
      return RepositoryFailureException(msg, e);
    }
    if (msg.contains('exceeds limit')) {
      return RepositoryFailureException(msg, e);
    }
    return RepositoryFailureException(msg, e);
  }

  /// Generate a tax bill for an individual order via RPC `generate_bill_for_order`.
  Future<Bill> generateBillForOrder(
    String orderId, {
    String? discountType,
    double discountValue = 0,
    String? discountReason,
  }) async {
    try {
      final response = await _client.rpc(
        'generate_bill_for_order',
        params: {
          'p_order_id': orderId,
          'p_discount_type': discountType,
          'p_discount_value': discountValue,
          'p_discount_reason': discountReason,
        },
      );

      if (response == null || response is! Map) {
        throw const RepositoryFailureException('Invalid response returned from server for bill generation');
      }

      final billId = response['bill_id'] as String;
      return await fetchBillById(billId);
    } on PostgrestException catch (e) {
      debugPrint('PostgrestException during generate_bill_for_order: ${e.message}');
      throw _mapPostgrestException(e);
    } catch (e) {
      debugPrint('Unexpected error generating bill: $e');
      rethrow;
    }
  }

  /// Fetch bill by bill ID from public.bills.
  Future<Bill> fetchBillById(String billId) async {
    try {
      final data = await _client
          .from('bills')
          .select()
          .eq('id', billId)
          .single();

      return Bill.fromJson(Map<String, dynamic>.from(data));
    } on PostgrestException catch (e) {
      debugPrint('Postgrest error fetching bill: ${e.message}');
      throw _mapPostgrestException(e);
    } catch (e) {
      debugPrint('Unexpected error fetching bill: $e');
      rethrow;
    }
  }

  /// Fetch existing bill for an order if generated.
  Future<Bill?> fetchBillForOrder(String orderId) async {
    try {
      final data = await _client
          .from('bills')
          .select()
          .eq('order_id', orderId)
          .maybeSingle();

      if (data == null) return null;
      return Bill.fromJson(Map<String, dynamic>.from(data));
    } catch (e) {
      debugPrint('Error fetching bill for order: $e');
      return null;
    }
  }

  /// Transactionally settle a bill with multi-tender payment array via RPC `settle_bill`.
  Future<Map<String, dynamic>> settleBill(
    String billId,
    List<Map<String, dynamic>> payments,
  ) async {
    if (payments.isEmpty) {
      throw const RepositoryFailureException('At least one payment entry is required');
    }

    try {
      final response = await _client.rpc(
        'settle_bill',
        params: {
          'p_bill_id': billId,
          'p_payments': payments,
        },
      );

      if (response == null || response is! Map) {
        throw const RepositoryFailureException('Invalid response returned when settling bill');
      }

      return Map<String, dynamic>.from(response);
    } on PostgrestException catch (e) {
      debugPrint('PostgrestException during settle_bill: ${e.message}');
      throw _mapPostgrestException(e);
    } catch (e) {
      debugPrint('Unexpected error settling bill: $e');
      rethrow;
    }
  }

  /// Atomically submit a parcel (takeaway) order via RPC `submit_parcel_order`.
  Future<Map<String, dynamic>> submitParcelOrder({
    String? customerName,
    required String customerPhone,
    required List<CartItem> items,
    String? notes,
  }) async {
    if (items.isEmpty) {
      throw const RepositoryFailureException('Cannot submit a parcel order with no items');
    }

    final itemsPayload = items.map((i) => i.toRpcJson()).toList();

    try {
      final response = await _client.rpc(
        'submit_parcel_order',
        params: {
          'p_customer_name': customerName?.trim().isNotEmpty == true
              ? customerName!.trim()
              : null,
          'p_customer_phone': customerPhone.trim(),
          'p_items': itemsPayload,
          'p_notes': notes?.trim().isNotEmpty == true ? notes!.trim() : null,
        },
      );

      if (response == null || response is! Map) {
        throw const RepositoryFailureException('Invalid response returned when submitting parcel order');
      }

      return Map<String, dynamic>.from(response);
    } on PostgrestException catch (e) {
      debugPrint('PostgrestException during submit_parcel_order: ${e.message}');
      throw _mapPostgrestException(e);
    } catch (e) {
      debugPrint('Unexpected error during parcel order submission: $e');
      rethrow;
    }
  }

  /// Close table session after all billing/payments are complete.
  Future<void> closeTableSession(String tableId, {String reason = 'Session completed & billed'}) async {
    try {
      await _client.rpc(
        'close_table_session',
        params: {
          'p_table_id': tableId,
          'p_reason': reason,
        },
      );
    } on PostgrestException catch (e) {
      debugPrint('PostgrestException during close_table_session: ${e.message}');
      throw _mapPostgrestException(e);
    } catch (e) {
      debugPrint('Error closing table session: $e');
      rethrow;
    }
  }
}
