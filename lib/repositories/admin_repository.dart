import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/errors/domain_exceptions.dart';
import '../services/supabase_service.dart';

/// Repository handling all Admin Module data operations:
/// - Dashboard executive metrics
/// - 9 standard operational and financial reports
/// - Menu categories, products, availability, and pricing
/// - Add-ons and promotional offers
/// - Table occupancy & active status
/// - Customer records and historical spend
/// - Audit logs and Store settings
class AdminRepository {
  final SupabaseClient _client;

  AdminRepository([SupabaseClient? client])
      : _client = client ?? SupabaseService.client;

  FreshCaneException _handleError(dynamic error) {
    if (error is PostgrestException) {
      debugPrint('[AdminRepository] PostgrestException: ${error.message} (${error.code})');
      return RepositoryFailureException(error.message, error);
    }
    return RepositoryFailureException(error.toString(), error);
  }

  // ---------------------------------------------------------------------------
  // DASHBOARD METRICS
  // ---------------------------------------------------------------------------

  /// Fetches executive dashboard metrics via PostgreSQL RPC `get_admin_dashboard_metrics`.
  Future<Map<String, dynamic>> fetchDashboardMetrics({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final now = DateTime.now();
      final start = (startDate ?? now).toIso8601String().substring(0, 10);
      final end = (endDate ?? now).toIso8601String().substring(0, 10);

      final response = await _client.rpc(
        'get_admin_dashboard_metrics',
        params: {
          'p_start_date': start,
          'p_end_date': end,
        },
      );

      if (response is Map<String, dynamic>) {
        return response;
      }
      return Map<String, dynamic>.from(response as Map);
    } catch (e) {
      throw _handleError(e);
    }
  }

  // ---------------------------------------------------------------------------
  // REPORTING CENTER
  // ---------------------------------------------------------------------------

  /// Fetches report data using the unified transactional RPC `get_admin_report_data`.
  /// Supported types: 'sales', 'product', 'category', 'server', 'payment',
  /// 'table', 'order_type', 'offer', 'cancellation'
  Future<List<Map<String, dynamic>>> fetchReportData({
    required String reportType,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final now = DateTime.now();
      final start = (startDate ?? now).toIso8601String().substring(0, 10);
      final end = (endDate ?? now).toIso8601String().substring(0, 10);

      final response = await _client.rpc(
        'get_admin_report_data',
        params: {
          'p_report_type': reportType,
          'p_start_date': start,
          'p_end_date': end,
        },
      );

      if (response is Map && response['records'] is List) {
        return List<Map<String, dynamic>>.from(
          (response['records'] as List).map((item) => Map<String, dynamic>.from(item as Map)),
        );
      } else if (response is List) {
        return List<Map<String, dynamic>>.from(
          response.map((item) => Map<String, dynamic>.from(item as Map)),
        );
      }
      return [];
    } catch (e) {
      throw _handleError(e);
    }
  }

  // ---------------------------------------------------------------------------
  // CATEGORIES MANAGEMENT
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> fetchCategories() async {
    try {
      final response = await _client
          .from('categories')
          .select('*')
          .order('display_order', ascending: true);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> saveCategory({
    String? id,
    required String name,
    required String slug,
    int displayOrder = 0,
    bool isActive = true,
  }) async {
    try {
      final data = {
        'name': name.trim(),
        'slug': slug.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '-'),
        'display_order': displayOrder,
        'is_active': isActive,
      };

      if (id != null && id.isNotEmpty) {
        await _client.from('categories').update(data).eq('id', id);
      } else {
        await _client.from('categories').insert(data);
      }
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> toggleCategoryActive(String id, bool isActive) async {
    try {
      await _client.from('categories').update({'is_active': isActive}).eq('id', id);
    } catch (e) {
      throw _handleError(e);
    }
  }

  // ---------------------------------------------------------------------------
  // MENU ITEMS (PRODUCTS) MANAGEMENT
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> fetchMenuItems() async {
    try {
      final response = await _client
          .from('menu_items')
          .select('*, categories(name, slug)')
          .order('display_order', ascending: true);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> saveMenuItem({
    String? id,
    required String name,
    required String categoryId,
    required double basePrice,
    String? description,
    bool isAvailable = true,
    bool isActive = true,
    int displayOrder = 0,
    String? imageUrl,
  }) async {
    try {
      final data = <String, dynamic>{
        'name': name.trim(),
        'category_id': categoryId,
        'base_price': basePrice,
        'description': description?.trim(),
        'is_available': isAvailable,
        'is_active': isActive,
        'display_order': displayOrder,
        'image_url': (imageUrl != null && imageUrl.isNotEmpty) ? imageUrl : null,
      };

      if (id != null && id.isNotEmpty) {
        await _client.from('menu_items').update(data).eq('id', id);
      } else {
        await _client.from('menu_items').insert(data);
      }
    } catch (e) {
      throw _handleError(e);
    }
  }

  /// Validates that raw image does not exceed 3MB (3 * 1024 * 1024 bytes),
  /// then automatically converts the image to WebP format.
  static Future<Uint8List> processAndConvertToWebp(Uint8List rawBytes) async {
    const maxBytes = 3 * 1024 * 1024;
    if (rawBytes.lengthInBytes > maxBytes) {
      throw const RepositoryFailureException('Image size exceeds 3MB limit. Please choose a photo under 3MB.');
    }

    try {
      final webpBytes = await FlutterImageCompress.compressWithList(
        rawBytes,
        format: CompressFormat.webp,
        quality: 85,
        minWidth: 1024,
        minHeight: 1024,
      );

      if (webpBytes.isEmpty) {
        throw const RepositoryFailureException('Failed to convert image to WebP format.');
      }

      if (webpBytes.lengthInBytes > maxBytes) {
        throw const RepositoryFailureException('Processed image exceeds 3MB limit.');
      }

      return webpBytes;
    } catch (e) {
      if (e is FreshCaneException) rethrow;
      throw RepositoryFailureException('Failed to process image: $e');
    }
  }

  /// Automatically validates 3MB max size, converts to WebP format,
  /// and uploads to Supabase Storage 'menu-items' bucket with 'image/webp' contentType.
  /// Zero image bytes stored in DB table.
  Future<String> uploadMenuItemImage({
    required Uint8List bytes,
    String? fileName,
    String? mimeType,
  }) async {
    try {
      // 1. Enforce 3MB limit and convert ANY format to WebP
      final webpBytes = await processAndConvertToWebp(bytes);

      // 2. Generate clean WebP storage path
      final uniqueName = 'item_${DateTime.now().millisecondsSinceEpoch}_${math.Random().nextInt(999999)}.webp';
      final path = 'products/$uniqueName';

      // 3. Upload binary with explicit image/webp content type
      await _client.storage.from('menu-items').uploadBinary(
        path,
        webpBytes,
        fileOptions: const FileOptions(
          contentType: 'image/webp',
          upsert: true,
        ),
      );

      final publicUrl = _client.storage.from('menu-items').getPublicUrl(path);
      return publicUrl;
    } catch (e) {
      throw _handleError(e);
    }
  }

  /// Deletes a product image from the Supabase Storage 'menu-items' bucket
  /// when replacing or clearing a product's photo.
  Future<void> deleteMenuItemImage(String imageUrl) async {
    try {
      if (imageUrl.isEmpty) return;
      final uri = Uri.tryParse(imageUrl);
      if (uri == null) return;
      final pathSegments = uri.pathSegments;
      final bucketIndex = pathSegments.indexOf('menu-items');
      if (bucketIndex != -1 && bucketIndex < pathSegments.length - 1) {
        final relativePath = pathSegments.sublist(bucketIndex + 1).join('/');
        await _client.storage.from('menu-items').remove([relativePath]);
      }
    } catch (e) {
      debugPrint('[AdminRepository] Error deleting image from storage: $e');
    }
  }

  Future<void> toggleMenuItemAvailability(String id, bool isAvailable) async {
    try {
      await _client
          .from('menu_items')
          .update({'is_available': isAvailable})
          .eq('id', id);
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> updateMenuItemPrice(String id, double newPrice) async {
    try {
      await _client
          .from('menu_items')
          .update({'base_price': newPrice})
          .eq('id', id);
    } catch (e) {
      throw _handleError(e);
    }
  }

  // ---------------------------------------------------------------------------
  // ADD-ONS MANAGEMENT
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> fetchAddons() async {
    try {
      final response = await _client
          .from('menu_addons')
          .select('*')
          .order('name', ascending: true);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> saveAddon({
    String? id,
    required String name,
    required double price,
    String? menuItemId,
    bool isAvailable = true,
  }) async {
    try {
      final data = <String, dynamic>{
        'name': name.trim(),
        'price': price,
        'is_active': isAvailable,
      };
      if (menuItemId != null) {
        data['menu_item_id'] = menuItemId;
      }

      if (id != null && id.isNotEmpty) {
        await _client.from('menu_addons').update(data).eq('id', id);
      } else {
        await _client.from('menu_addons').insert(data);
      }
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> toggleAddonAvailability(String id, bool isAvailable) async {
    try {
      await _client
          .from('menu_addons')
          .update({'is_active': isAvailable})
          .eq('id', id);
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> deleteAddon(String id) async {
    try {
      await _client.from('menu_addons').delete().eq('id', id);
    } catch (e) {
      throw _handleError(e);
    }
  }

  // ---------------------------------------------------------------------------
  // COMBOS MANAGEMENT
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> fetchCombos() async {
    try {
      final response = await _client.rpc('fetch_combos_with_items');
      if (response is List) {
        return List<Map<String, dynamic>>.from(
          response.map((item) => Map<String, dynamic>.from(item as Map)),
        );
      }
      return [];
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> saveCombo({
    String? id,
    required String name,
    required double price,
    bool isAvailable = true,
    bool isActive = true,
    required List<Map<String, dynamic>> items,
  }) async {
    try {
      await _client.rpc(
        'save_combo',
        params: {
          'p_id': id,
          'p_name': name.trim(),
          'p_price': price,
          'p_is_available': isAvailable,
          'p_is_active': isActive,
          'p_items': items,
        },
      );
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> deleteCombo(String id) async {
    try {
      await _client.rpc('delete_combo', params: {'p_id': id});
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> toggleComboAvailability(String id, bool isAvailable) async {
    try {
      final combos = await fetchCombos();
      final target = combos.firstWhere((c) => c['id'] == id, orElse: () => {});
      if (target.isEmpty) return;

      final items = (target['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      await saveCombo(
        id: id,
        name: target['name'] ?? '',
        price: (target['price'] as num?)?.toDouble() ?? 0.0,
        isAvailable: isAvailable,
        isActive: target['is_active'] ?? true,
        items: items,
      );
    } catch (e) {
      throw _handleError(e);
    }
  }

  // ---------------------------------------------------------------------------
  // OFFERS / PROMOTIONS MANAGEMENT
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> fetchOffers() async {
    try {
      final response = await _client
          .from('offers')
          .select('*')
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> saveOffer({
    String? id,
    required String title,
    required String code,
    required String discountType,
    required double discountValue,
    List<String> applicableProductIds = const [],
    int buyQuantity = 1,
    int getQuantity = 1,
    double minOrderAmount = 0.0,
    double? maxDiscountAmount,
    DateTime? startDate,
    DateTime? endDate,
    bool isActive = true,
  }) async {
    try {
      final data = {
        'title': title.trim(),
        'name': title.trim(),
        'code': code.trim().toUpperCase(),
        'discount_type': discountType,
        'discount_value': discountValue,
        'applicable_product_ids': applicableProductIds,
        'buy_quantity': buyQuantity,
        'get_quantity': getQuantity,
        'min_order_amount': minOrderAmount,
        'max_discount_amount': maxDiscountAmount,
        if (startDate != null) 'valid_from': startDate.toIso8601String().substring(0, 10),
        if (endDate != null) 'valid_until': endDate.toIso8601String().substring(0, 10),
        if (startDate != null) 'start_date': startDate.toIso8601String(),
        if (endDate != null) 'end_date': endDate.toIso8601String(),
        'is_active': isActive,
      };

      if (id != null && id.isNotEmpty) {
        await _client.from('offers').update(data).eq('id', id);
      } else {
        await _client.from('offers').insert(data);
      }
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> toggleOfferActive(String id, bool isActive) async {
    try {
      await _client.from('offers').update({'is_active': isActive}).eq('id', id);
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> deleteOffer(String id) async {
    try {
      await _client.from('offers').delete().eq('id', id);
    } catch (e) {
      throw _handleError(e);
    }
  }

  // ---------------------------------------------------------------------------
  // TABLE MANAGEMENT
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> fetchTables() async {
    try {
      final response = await _client
          .from('restaurant_tables')
          .select('*')
          .order('table_number', ascending: true);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> saveTable({
    String? id,
    required String tableNumber,
    required int seatingCapacity,
    bool isActive = true,
  }) async {
    try {
      final data = {
        'table_number': tableNumber.trim(),
        'seating_capacity': seatingCapacity,
        'is_active': isActive,
      };

      if (id != null && id.isNotEmpty) {
        await _client.from('restaurant_tables').update(data).eq('id', id);
      } else {
        await _client.from('restaurant_tables').insert(data);
      }
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> toggleTableActive(String id, bool isActive) async {
    try {
      await _client
          .from('restaurant_tables')
          .update({'is_active': isActive})
          .eq('id', id);
    } catch (e) {
      throw _handleError(e);
    }
  }

  // ---------------------------------------------------------------------------
  // CUSTOMER MANAGEMENT
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> fetchCustomers() async {
    try {
      try {
        final response = await _client
            .from('customers')
            .select('*')
            .order('total_spend', ascending: false);
        return List<Map<String, dynamic>>.from(response);
      } catch (_) {
        final response = await _client
            .from('customers')
            .select('*')
            .order('created_at', ascending: false);
        return List<Map<String, dynamic>>.from(response);
      }
    } catch (e) {
      throw _handleError(e);
    }
  }

  // ---------------------------------------------------------------------------
  // AUDIT LOGS
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> fetchAuditLogs({int limit = 100}) async {
    try {
      final response = await _client
          .from('audit_logs')
          .select('*, user_profiles(full_name, role)')
          .order('created_at', ascending: false)
          .limit(limit);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      throw _handleError(e);
    }
  }

  // ---------------------------------------------------------------------------
  // STORE SETTINGS
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>?> fetchStoreSettings() async {
    try {
      final response = await _client
          .from('store_settings')
          .select('*')
          .limit(1)
          .maybeSingle();
      return response;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> updateStoreSettings(String id, Map<String, dynamic> data) async {
    try {
      await _client.from('store_settings').update(data).eq('id', id);
    } catch (e) {
      throw _handleError(e);
    }
  }
}
