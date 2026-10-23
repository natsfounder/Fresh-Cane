import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/app_colors.dart';
import '../../../repositories/admin_repository.dart';
import '../../../services/report_export_service.dart';
import '../../../state/admin_provider.dart';

class AdminMenuView extends ConsumerStatefulWidget {
  const AdminMenuView({super.key});

  @override
  ConsumerState<AdminMenuView> createState() => _AdminMenuViewState();
}

class _AdminMenuViewState extends ConsumerState<AdminMenuView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchController = TextEditingController();
  String _productSearchQuery = '';
  String? _selectedCategoryFilter;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(adminProvider.notifier).loadMenuData();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(adminProvider);
    final notifier = ref.read(adminProvider.notifier);

    return Column(
      children: [
        // TabBar Header
        Container(
          color: Colors.white,
          child: TabBar(
            controller: _tabController,
            labelColor: AppColors.primaryGreen,
            unselectedLabelColor: Colors.grey.shade600,
            indicatorColor: AppColors.primaryGreen,
            indicatorWeight: 3,
            tabs: [
              Tab(
                icon: const Icon(Icons.fastfood_outlined, size: 20),
                text: 'Products (${state.menuItems.length})',
              ),
              Tab(
                icon: const Icon(Icons.category_outlined, size: 20),
                text: 'Categories (${state.categories.length})',
              ),
              Tab(
                icon: const Icon(Icons.add_circle_outline, size: 20),
                text: 'Add-ons (${state.addons.length})',
              ),
              Tab(
                icon: const Icon(Icons.set_meal_outlined, size: 20),
                text: 'Combos (${state.combos.length})',
              ),
            ],
          ),
        ),

        // Tab Views
        Expanded(
          child: state.isLoadingMenu
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.primaryGreen),
                )
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildProductsTab(context, state, notifier),
                    _buildCategoriesTab(context, state, notifier),
                    _buildAddonsTab(context, state, notifier),
                    _buildCombosTab(context, state, notifier),
                  ],
                ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // PRODUCTS TAB
  // ---------------------------------------------------------------------------

  Widget _buildProductsTab(
    BuildContext context,
    dynamic state,
    dynamic notifier,
  ) {
    final menuItems = (state.menuItems as List<Map<String, dynamic>>).where((item) {
      if (_selectedCategoryFilter != null &&
          item['category_id'] != _selectedCategoryFilter) {
        return false;
      }
      if (_productSearchQuery.isNotEmpty) {
        final q = _productSearchQuery.toLowerCase();
        final name = (item['name'] ?? '').toString().toLowerCase();
        if (!name.contains(q)) return false;
      }
      return true;
    }).toList();
    final allAddons = state.addons is List ? (state.addons as List<Map<String, dynamic>>) : <Map<String, dynamic>>[];

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          // Row 1: Search input
          SizedBox(
            height: 38,
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _productSearchQuery = v),
              decoration: InputDecoration(
                hintText: 'Search products by name...',
                hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                prefixIcon: const Icon(Icons.search, size: 18, color: Colors.grey),
                filled: true,
                fillColor: Colors.white,
                contentPadding: EdgeInsets.zero,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Row 2: Category Filter & Add Product
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      value: _selectedCategoryFilter,
                      hint: const Text('All Categories', style: TextStyle(fontSize: 12)),
                      isExpanded: true,
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('All Categories', style: TextStyle(fontSize: 12)),
                        ),
                        ...state.categories.map((c) {
                          return DropdownMenuItem<String?>(
                            value: c['id'] as String?,
                            child: Text(c['name'] ?? '', style: const TextStyle(fontSize: 12)),
                          );
                        }),
                      ],
                      onChanged: (v) => setState(() => _selectedCategoryFilter = v),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add Product', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => _showProductDialog(context, null, state, notifier),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Product List
          Expanded(
            child: menuItems.isEmpty
                    ? const Center(child: Text('No products found matching filters.'))
                    : ListView.separated(
                        itemCount: menuItems.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final p = menuItems[index];
                          final isAvailable = p['is_available'] == true;
                          final basePrice = (p['base_price'] as num?)?.toDouble() ?? 0.0;
                          final catName = p['categories'] != null ? p['categories']['name'] : 'General';
                          final productAddonCount = allAddons.where((a) => a['menu_item_id'] == p['id']).length;

                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: isAvailable ? Colors.grey.shade200 : Colors.red.shade100),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // Thumbnail with exact 42x42 dimensions (image or icon)
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: SizedBox(
                                    width: 42,
                                    height: 42,
                                    child: (p['image_url'] != null && (p['image_url'] as String).isNotEmpty)
                                        ? Image.network(
                                            p['image_url'] as String,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) => Container(
                                              color: isAvailable ? AppColors.primaryLight : Colors.red.shade50,
                                              alignment: Alignment.center,
                                              child: Icon(
                                                Icons.fastfood,
                                                color: isAvailable ? AppColors.primaryGreen : Colors.red.shade300,
                                                size: 20,
                                              ),
                                            ),
                                          )
                                        : Container(
                                            color: isAvailable ? AppColors.primaryLight : Colors.red.shade50,
                                            alignment: Alignment.center,
                                            child: Icon(
                                              Icons.fastfood,
                                              color: isAvailable ? AppColors.primaryGreen : Colors.red.shade300,
                                              size: 20,
                                            ),
                                          ),
                                  ),
                                ),
                                const SizedBox(width: 10),

                                // Product Info & Price
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              p['name'] ?? '',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13.5,
                                                color: isAvailable ? AppColors.textPrimary : Colors.grey.shade600,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            ReportExportService.formatCurrency(basePrice),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13.5,
                                              color: AppColors.primaryDark,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '$catName • ${p['description'] ?? 'No description'}',
                                        style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      InkWell(
                                        onTap: () => _showProductAddonsSheet(context, p, state, notifier),
                                        borderRadius: BorderRadius.circular(6),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: productAddonCount > 0
                                                ? AppColors.primaryLight
                                                : const Color(0xFFF1F5F9),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(
                                              color: productAddonCount > 0
                                                  ? AppColors.primaryGreen.withValues(alpha: 0.4)
                                                  : Colors.grey.shade300,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.extension_outlined,
                                                size: 11,
                                                color: productAddonCount > 0
                                                    ? AppColors.primaryGreen
                                                    : Colors.grey.shade700,
                                              ),
                                              const SizedBox(width: 3),
                                              Flexible(
                                                child: Text(
                                                  productAddonCount > 0
                                                      ? 'Add-ons ($productAddonCount)'
                                                      : '+ Add-ons',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w700,
                                                    color: productAddonCount > 0
                                                        ? AppColors.primaryDark
                                                        : Colors.grey.shade700,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),

                                // Controls: Stock Switch & Edit Button
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        SizedBox(
                                          height: 26,
                                          child: Transform.scale(
                                            scale: 0.75,
                                            child: Switch(
                                              value: isAvailable,
                                              activeThumbColor: AppColors.primaryGreen,
                                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                              onChanged: (val) => notifier.toggleProductAvailability(p['id'], val),
                                            ),
                                          ),
                                        ),
                                        Text(
                                          isAvailable ? 'In Stock' : 'Out',
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w600,
                                            color: isAvailable ? AppColors.primaryGreen : Colors.red,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(width: 2),
                                    IconButton(
                                      icon: const Icon(Icons.edit_outlined, size: 18),
                                      color: Colors.grey.shade600,
                                      padding: const EdgeInsets.all(4),
                                      constraints: const BoxConstraints(),
                                      onPressed: () => _showProductDialog(context, p, state, notifier),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                  ),
          ),
        ],
      ),
    );
  }

  void _showProductDialog(
    BuildContext context,
    Map<String, dynamic>? product,
    dynamic state,
    dynamic notifier,
  ) {
    final isEdit = product != null;
    final nameCtrl = TextEditingController(text: product?['name'] ?? '');
    final priceCtrl = TextEditingController(
      text: product != null ? (product['base_price'] as num?)?.toString() ?? '' : '',
    );
    final descCtrl = TextEditingController(text: product?['description'] ?? '');
    String? categoryId = product?['category_id'] ?? (state.categories.isNotEmpty ? state.categories.first['id'] : null);
    bool isAvailable = product?['is_available'] ?? true;

    // Photo state
    final String? originalImageUrl = product?['image_url'] as String?;
    String? currentImageUrl = originalImageUrl;
    XFile? pickedFile;
    Uint8List? pickedBytes;
    bool isPhotoRemoved = false;
    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: !isSaving,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            final localBytes = pickedBytes;
            final localUrl = (!isPhotoRemoved && currentImageUrl != null && currentImageUrl.isNotEmpty)
                ? currentImageUrl
                : null;
            final hasPhoto = localBytes != null || localUrl != null;

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text(isEdit ? 'Edit Product' : 'Add New Product'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Product Photo Box & Controls
                    Center(
                      child: Column(
                        children: [
                          Stack(
                            alignment: Alignment.topRight,
                            children: [
                              Container(
                                width: 110,
                                height: 110,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: hasPhoto ? AppColors.primaryGreen.withValues(alpha: 0.5) : Colors.grey.shade300,
                                    width: 1.5,
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(15),
                                  child: localBytes != null
                                      ? Image.memory(localBytes, fit: BoxFit.cover)
                                      : localUrl != null
                                          ? Image.network(
                                              localUrl,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) => const Icon(
                                                Icons.fastfood,
                                                size: 40,
                                                color: Colors.grey,
                                              ),
                                            )
                                          : Column(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Icon(Icons.add_a_photo_outlined, size: 36, color: Colors.grey.shade500),
                                                const SizedBox(height: 4),
                                                Text(
                                                  'Add Photo',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.grey.shade600,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ],
                                            ),
                                ),
                              ),
                              if (hasPhoto && !isSaving)
                                Positioned(
                                  top: -2,
                                  right: -2,
                                  child: InkWell(
                                    onTap: () {
                                      setDlgState(() {
                                        pickedBytes = null;
                                        pickedFile = null;
                                        isPhotoRemoved = true;
                                      });
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: const BoxDecoration(
                                        color: Colors.red,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.close, size: 14, color: Colors.white),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  foregroundColor: AppColors.primaryGreen,
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  visualDensity: VisualDensity.compact,
                                ),
                                icon: const Icon(Icons.photo_library_outlined, size: 16),
                                label: Text(
                                  hasPhoto ? 'Change Photo' : 'Upload Photo',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                                onPressed: isSaving
                                    ? null
                                    : () async {
                                        final picker = ImagePicker();
                                        final xfile = await picker.pickImage(
                                          source: ImageSource.gallery,
                                          maxWidth: 1920,
                                          maxHeight: 1920,
                                        );
                                        if (xfile != null) {
                                          final fileLength = await xfile.length();
                                          // Strict 3MB limit validation
                                          if (fileLength > 3 * 1024 * 1024) {
                                            if (ctx.mounted) {
                                              ScaffoldMessenger.of(ctx).showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    'Photo exceeds 3MB limit (${(fileLength / (1024 * 1024)).toStringAsFixed(1)}MB). Please choose a smaller photo.',
                                                  ),
                                                  backgroundColor: Colors.red.shade700,
                                                ),
                                              );
                                            }
                                            return;
                                          }

                                          final rawBytes = await xfile.readAsBytes();
                                          try {
                                            // Automatically convert any selected format to WebP
                                            final webpBytes = await AdminRepository.processAndConvertToWebp(rawBytes);
                                            setDlgState(() {
                                              pickedFile = xfile;
                                              pickedBytes = webpBytes;
                                              isPhotoRemoved = false;
                                            });
                                          } catch (err) {
                                            if (ctx.mounted) {
                                              ScaffoldMessenger.of(ctx).showSnackBar(
                                                SnackBar(
                                                  content: Text('Error processing photo: $err'),
                                                  backgroundColor: Colors.red.shade700,
                                                ),
                                              );
                                            }
                                          }
                                        }
                                      },
                              ),
                              if (hasPhoto && !isSaving) ...[
                                const SizedBox(width: 4),
                                TextButton.icon(
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.red.shade700,
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  icon: const Icon(Icons.delete_outline, size: 16),
                                  label: const Text(
                                    'Delete',
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                  ),
                                  onPressed: () {
                                    setDlgState(() {
                                      pickedBytes = null;
                                      pickedFile = null;
                                      isPhotoRemoved = true;
                                    });
                                  },
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: 'Product Name *'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: categoryId,
                      decoration: const InputDecoration(labelText: 'Category *'),
                      items: (state.categories as List<Map<String, dynamic>>).map((c) {
                        return DropdownMenuItem<String>(
                          value: c['id'] as String,
                          child: Text(c['name'] ?? ''),
                        );
                      }).toList(),
                      onChanged: isSaving ? null : (v) => setDlgState(() => categoryId = v),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: priceCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Base Price (₹) *'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descCtrl,
                      decoration: const InputDecoration(labelText: 'Description (Optional)'),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Available in Menu:'),
                        Switch(
                          value: isAvailable,
                          activeThumbColor: AppColors.primaryGreen,
                          onChanged: isSaving ? null : (v) => setDlgState(() => isAvailable = v),
                        ),
                      ],
                    ),
                    if (isEdit) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.extension_outlined, size: 16),
                        label: const Text('Manage Add-ons for this Product'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primaryGreen,
                          side: const BorderSide(color: AppColors.primaryGreen),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _showProductAddonsSheet(context, product, state, notifier);
                        },
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: isSaving
                      ? null
                      : () async {
                          final name = nameCtrl.text.trim();
                          final price = double.tryParse(priceCtrl.text.trim()) ?? 0.0;
                          if (name.isEmpty || categoryId == null || price <= 0) return;

                          setDlgState(() => isSaving = true);

                          try {
                            String? finalImageUrl = originalImageUrl;

                            // 1. If a new photo was picked, upload to Supabase Storage bucket
                            if (pickedBytes != null) {
                              final uploadedUrl = await notifier.uploadMenuItemImage(
                                bytes: pickedBytes!,
                                fileName: pickedFile?.name,
                              );
                              finalImageUrl = uploadedUrl;

                              // Clean up old storage image if one existed
                              if (originalImageUrl != null && originalImageUrl.isNotEmpty) {
                                await notifier.deleteMenuItemImage(originalImageUrl);
                              }
                            }
                            // 2. If photo was deleted / removed by user
                            else if (isPhotoRemoved) {
                              if (originalImageUrl != null && originalImageUrl.isNotEmpty) {
                                await notifier.deleteMenuItemImage(originalImageUrl);
                              }
                              finalImageUrl = null;
                            }

                            // 3. Save to database: only the clean public URL string is stored
                            await notifier.saveMenuItem(
                              id: product?['id'],
                              name: name,
                              categoryId: categoryId!,
                              basePrice: price,
                              description: descCtrl.text.trim(),
                              isAvailable: isAvailable,
                              imageUrl: finalImageUrl,
                            );

                            if (ctx.mounted) Navigator.pop(ctx);
                          } catch (e) {
                            setDlgState(() => isSaving = false);
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(
                                  content: Text('Failed to save product: $e'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        },
                  child: isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(isEdit ? 'Save Changes' : 'Create Product'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // CATEGORIES TAB
  // ---------------------------------------------------------------------------

  Widget _buildCategoriesTab(
    BuildContext context,
    dynamic state,
    dynamic notifier,
  ) {
    final categories = state.categories as List<Map<String, dynamic>>;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Menu Categories (${categories.length})',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add Category'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => _showCategoryDialog(context, null, notifier),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.separated(
              itemCount: categories.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final c = categories[index];
                final isActive = c['is_active'] == true;

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: AppColors.primaryLight,
                        child: const Icon(Icons.category, color: AppColors.primaryGreen, size: 18),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              c['name'] ?? '',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            Text(
                              'Slug: ${c['slug'] ?? '-'} • Order: ${c['display_order'] ?? 0}',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: isActive,
                        activeColor: AppColors.primaryGreen,
                        onChanged: (val) => notifier.toggleCategoryActive(c['id'], val),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 20),
                        onPressed: () => _showCategoryDialog(context, c, notifier),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showCategoryDialog(
    BuildContext context,
    Map<String, dynamic>? category,
    dynamic notifier,
  ) {
    final isEdit = category != null;
    final nameCtrl = TextEditingController(text: category?['name'] ?? '');
    final slugCtrl = TextEditingController(text: category?['slug'] ?? '');
    final orderCtrl = TextEditingController(
      text: category != null ? (category['display_order'] ?? 0).toString() : '0',
    );

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(isEdit ? 'Edit Category' : 'Add New Category'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Category Name *'),
                onChanged: (v) {
                  if (!isEdit) {
                    slugCtrl.text = v.toLowerCase().replaceAll(RegExp(r'\s+'), '-');
                  }
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: slugCtrl,
                decoration: const InputDecoration(labelText: 'Slug identifier *'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: orderCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Display Order'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryGreen,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                final name = nameCtrl.text.trim();
                final slug = slugCtrl.text.trim();
                final order = int.tryParse(orderCtrl.text.trim()) ?? 0;
                if (name.isEmpty || slug.isEmpty) return;

                await notifier.saveCategory(
                  id: category?['id'],
                  name: name,
                  slug: slug,
                  displayOrder: order,
                );
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: Text(isEdit ? 'Save Changes' : 'Create Category'),
            ),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // ADD-ONS TAB
  // ---------------------------------------------------------------------------

  Widget _buildAddonsTab(
    BuildContext context,
    dynamic state,
    dynamic notifier,
  ) {
    final addons = state.addons as List<Map<String, dynamic>>;
    final menuItems = state.menuItems as List<Map<String, dynamic>>;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Menu Add-ons (${addons.length})',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              Text(
                'Manage per product in Products tab',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: addons.isEmpty
                ? Center(
                    child: Text(
                      'No add-ons created yet.\nGo to the Products tab and tap "+ Add-ons" on any product to create one.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  )
                : ListView.separated(
                    itemCount: addons.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final a = addons[index];
                      final isAvailable = a['is_active'] == true;
                      final price = (a['price'] as num?)?.toDouble() ?? 0.0;
                      final linkedProduct = menuItems
                          .where((m) => m['id'] == a['menu_item_id'])
                          .firstOrNull;
                      final linkedName = linkedProduct != null
                          ? linkedProduct['name']
                          : 'General / Unassigned';

                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: AppColors.primaryLight,
                              child: const Icon(Icons.add_circle, color: AppColors.primaryGreen, size: 18),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    a['name'] ?? '',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Product: $linkedName',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: linkedProduct != null ? AppColors.primaryDark : Colors.grey.shade500,
                                      fontWeight: linkedProduct != null ? FontWeight.w600 : FontWeight.normal,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '+ ${ReportExportService.formatCurrency(price)}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            const SizedBox(width: 16),
                            Switch(
                              value: isAvailable,
                              activeColor: AppColors.primaryGreen,
                              onChanged: (val) => notifier.toggleAddonAvailability(a['id'], val),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 20),
                              onPressed: () => _showAddonDialog(
                                context,
                                a,
                                notifier,
                                preselectedMenuItemId: a['menu_item_id'],
                                productName: linkedProduct?['name'],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Delete Add-on'),
                                    content: Text('Are you sure you want to delete "${a['name']}"?'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                                        onPressed: () => Navigator.pop(ctx, true),
                                        child: const Text('Delete'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm == true) {
                                  await notifier.deleteAddon(a['id']);
                                }
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _showProductAddonsSheet(
    BuildContext context,
    Map<String, dynamic> product,
    dynamic state,
    dynamic notifier,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Consumer(
          builder: (context, ref, _) {
            final adminState = ref.watch(adminProvider);
            final allAddons = adminState.addons;
            final productAddons = allAddons
                .where((a) => a['menu_item_id'] == product['id'])
                .toList();

            final screenH = MediaQuery.of(context).size.height;
            final keyboardH = MediaQuery.of(context).viewInsets.bottom;

            return Container(
              constraints: BoxConstraints(maxHeight: screenH * 0.85),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 16,
                bottom: keyboardH + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Header
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Add-ons for ${product['name']}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                                color: AppColors.primaryDark,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${productAddons.length} add-on${productAddons.length == 1 ? '' : 's'} linked to this product',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Add New Add-on Button
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add New Add-on for this Product'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryGreen,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () {
                      _showAddonDialog(
                        context,
                        null,
                        notifier,
                        preselectedMenuItemId: product['id'],
                        productName: product['name'],
                      );
                    },
                  ),
                  const SizedBox(height: 12),

                  // Add-ons list
                  Flexible(
                    child: productAddons.isEmpty
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                                vertical: 32, horizontal: 16),
                            alignment: Alignment.center,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.extension_off_outlined,
                                  size: 40,
                                  color: Colors.grey.shade400,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'No add-ons for "${product['name']}" yet',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Tap the button above to create one specifically for this product.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: productAddons.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, idx) {
                              final a = productAddons[idx];
                              final isAvail = a['is_active'] == true;
                              final price =
                                  (a['price'] as num?)?.toDouble() ?? 0.0;

                              return Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: AppColors.surface,
                                  borderRadius: BorderRadius.circular(10),
                                  border:
                                      Border.all(color: AppColors.borderLight),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            a['name'] ?? '',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '+ ₹${price.toStringAsFixed(0)}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 12,
                                              color: AppColors.primaryGreen,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Switch(
                                      value: isAvail,
                                      activeColor: AppColors.primaryGreen,
                                      onChanged: (val) => notifier
                                          .toggleAddonAvailability(
                                              a['id'], val),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.edit_outlined,
                                          size: 18),
                                      color: Colors.grey.shade600,
                                      onPressed: () => _showAddonDialog(
                                        context,
                                        a,
                                        notifier,
                                        preselectedMenuItemId: product['id'],
                                        productName: product['name'],
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                          Icons.delete_outline_rounded,
                                          size: 18,
                                          color: Colors.red),
                                      onPressed: () async {
                                        final confirm =
                                            await showDialog<bool>(
                                          context: context,
                                          builder: (dCtx) => AlertDialog(
                                            title: const Text('Delete Add-on'),
                                            content: Text(
                                                'Delete "${a['name']}" from ${product['name']}?'),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(dCtx, false),
                                                child: const Text('Cancel'),
                                              ),
                                              ElevatedButton(
                                                style: ElevatedButton.styleFrom(
                                                    backgroundColor: Colors.red,
                                                    foregroundColor:
                                                        Colors.white),
                                                onPressed: () =>
                                                    Navigator.pop(dCtx, true),
                                                child: const Text('Delete'),
                                              ),
                                            ],
                                          ),
                                        );
                                        if (confirm == true) {
                                          await notifier.deleteAddon(a['id']);
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showAddonDialog(
    BuildContext context,
    Map<String, dynamic>? addon,
    dynamic notifier, {
    String? preselectedMenuItemId,
    String? productName,
  }) {
    final isEdit = addon != null;
    final nameCtrl = TextEditingController(text: addon?['name'] ?? '');
    final priceCtrl = TextEditingController(
      text: addon != null ? (addon['price'] as num?)?.toString() ?? '' : '',
    );
    final targetMenuItemId = preselectedMenuItemId ?? addon?['menu_item_id'];

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(isEdit
              ? 'Edit Add-on${productName != null ? " ($productName)" : ""}'
              : 'Add New Add-on${productName != null ? " for $productName" : ""}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (productName != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.fastfood, size: 14, color: AppColors.primaryGreen),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Product: $productName',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primaryDark,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Add-on Name *',
                    hintText: 'e.g. Mint, Lemon, Extra Ginger',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: priceCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Additional Price (₹) *',
                    hintText: 'e.g. 5 or 10',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryGreen,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                final name = nameCtrl.text.trim();
                final price = double.tryParse(priceCtrl.text.trim()) ?? 0.0;
                if (name.isEmpty) return;

                await notifier.saveAddon(
                  id: addon?['id'],
                  name: name,
                  price: price,
                  menuItemId: targetMenuItemId,
                );
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: Text(isEdit ? 'Save Changes' : 'Create Add-on'),
            ),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // COMBOS TAB
  // ---------------------------------------------------------------------------

  Widget _buildCombosTab(
    BuildContext context,
    dynamic state,
    dynamic notifier,
  ) {
    final combos = state.combos as List<Map<String, dynamic>>;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Menu Combos (${combos.length})',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add Combo'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => _showComboDialog(context, null, state, notifier),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: combos.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.set_meal_outlined, size: 48, color: Colors.grey.shade400),
                        const SizedBox(height: 12),
                        Text(
                          'No combos created yet',
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Bundle your best products into combos at special prices',
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Create First Combo'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryGreen,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: () => _showComboDialog(context, null, state, notifier),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: combos.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final c = combos[index];
                      final isAvailable = c['is_available'] == true;
                      final itemsCount = (c['items_count'] as num?)?.toInt() ?? 0;
                      final rawItems = (c['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];

                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.02),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _showComboDialog(context, c, state, notifier),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CircleAvatar(
                                    backgroundColor: const Color(0xFFE8F5E9),
                                    radius: 18,
                                    child: const Icon(Icons.set_meal, color: AppColors.primaryGreen, size: 18),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          c['name'] ?? '',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Wrap(
                                          crossAxisAlignment: WrapCrossAlignment.center,
                                          spacing: 8,
                                          children: [
                                            Text(
                                              ReportExportService.formatCurrency((c['price'] as num?)?.toDouble() ?? 0.0),
                                              style: const TextStyle(
                                                color: AppColors.primaryGreen,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                              ),
                                            ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFFEF3C7),
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(color: const Color(0xFFF59E0B)),
                                              ),
                                              child: Text(
                                                '$itemsCount Food Item${itemsCount == 1 ? '' : 's'}',
                                                style: const TextStyle(
                                                  color: Color(0xFFB45309),
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Transform.scale(
                                        scale: 0.8,
                                        child: Switch(
                                          value: isAvailable,
                                          activeColor: AppColors.primaryGreen,
                                          onChanged: (val) => notifier.toggleComboAvailability(c['id'], val),
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.edit_outlined, size: 18),
                                        visualDensity: VisualDensity.compact,
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                        onPressed: () => _showComboDialog(context, c, state, notifier),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                        visualDensity: VisualDensity.compact,
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                        onPressed: () async {
                                          final confirm = await showDialog<bool>(
                                            context: context,
                                            builder: (ctx) => AlertDialog(
                                              title: const Text('Delete Combo'),
                                              content: Text('Are you sure you want to delete "${c['name']}"?'),
                                              actions: [
                                                TextButton(
                                                  onPressed: () => Navigator.pop(ctx, false),
                                                  child: const Text('Cancel'),
                                                ),
                                                ElevatedButton(
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor: Colors.red,
                                                    foregroundColor: Colors.white,
                                                  ),
                                                  onPressed: () => Navigator.pop(ctx, true),
                                                  child: const Text('Delete'),
                                                ),
                                              ],
                                            ),
                                          );
                                          if (confirm == true) {
                                            await notifier.deleteCombo(c['id']);
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              if (rawItems.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.grey.shade200),
                                  ),
                                  child: Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    children: rawItems.map((it) {
                                      return Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: Colors.grey.shade300),
                                        ),
                                        child: Text(
                                          '${it['quantity']}x ${it['item_name']}',
                                          style: TextStyle(fontSize: 11, color: Colors.grey.shade800, fontWeight: FontWeight.w500),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _showComboDialog(
    BuildContext context,
    Map<String, dynamic>? combo,
    dynamic state,
    dynamic notifier,
  ) {
    final isEdit = combo != null;
    final nameCtrl = TextEditingController(text: combo?['name'] ?? '');
    final priceCtrl = TextEditingController(
      text: combo != null ? (combo['price']?.toString() ?? '') : '',
    );

    // Initial items in combo — FIX: use explicit return to create Map, not Set
    final initialRawItems = (combo?['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    List<Map<String, dynamic>> comboItems = initialRawItems.map((it) {
      return <String, dynamic>{
        'menu_item_id': it['menu_item_id']?.toString() ?? '',
        'item_name': it['item_name']?.toString() ?? '',
        'base_price': (it['base_price'] as num?)?.toDouble() ?? 0.0,
        'quantity': (it['quantity'] as num?)?.toInt() ?? 1,
      };
    }).toList();

    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            final totalItemsCount = comboItems.fold<int>(
              0,
              (sum, it) => sum + ((it['quantity'] as num?)?.toInt() ?? 1),
            );
            final totalRegularPrice = comboItems.fold<double>(
              0.0,
              (sum, it) => sum + (((it['base_price'] as num?)?.toDouble() ?? 0.0) * ((it['quantity'] as num?)?.toInt() ?? 1)),
            );

            // Pre-compute active products for the Add Items button
            final allMenuItems = (ref.read(adminProvider).menuItems as List<Map<String, dynamic>>);
            final activeProducts = allMenuItems.where((m) {
              final cat = m['categories'] is Map ? m['categories'] as Map<String, dynamic> : null;
              final catSlug = (cat?['slug'] ?? '').toString().toLowerCase();
              final catName = (cat?['name'] ?? '').toString().toLowerCase();
              if (catSlug == 'combos' || catName == 'combos') return false;
              if (m['is_active'] == false) return false;
              return true;
            }).toList();

            return AlertDialog(
              insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
              contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              title: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: AppColors.primaryLight,
                    radius: 16,
                    child: const Icon(Icons.set_meal, color: AppColors.primaryGreen, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isEdit ? 'Edit Combo' : 'Create New Combo',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: MediaQuery.of(context).size.width,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 10),
                      TextField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Combo Name *',
                          hintText: 'e.g. Cane Cooler + Sandwich Combo',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: priceCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Combo Price (₹) *',
                          hintText: 'e.g. 199.00',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Food Items Section Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Food Items',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEF3C7),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: const Color(0xFFF59E0B)),
                                ),
                                child: Text(
                                  '$totalItemsCount item${totalItemsCount == 1 ? '' : 's'}',
                                  style: const TextStyle(
                                    color: Color(0xFFB45309),
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Add Food Items Button — opens item picker dialog
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primaryGreen,
                            side: const BorderSide(color: AppColors.primaryGreen, width: 1.5),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: const Icon(Icons.add_circle_outline, size: 20),
                          label: Text(
                            activeProducts.isEmpty ? 'Loading menu items...' : 'Tap to Add Food Items',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                          onPressed: activeProducts.isEmpty
                              ? null
                              : () async {
                                  var menuList = activeProducts.isNotEmpty
                                      ? allMenuItems
                                      : (ref.read(adminProvider).menuItems as List<Map<String, dynamic>>);
                                  if (menuList.isEmpty) {
                                    await notifier.loadMenuData();
                                    menuList = (ref.read(adminProvider).menuItems as List<Map<String, dynamic>>);
                                  }
                                  if (!ctx.mounted) return;
                                  await _showItemPicker(
                                    ctx,
                                    menuList,
                                    comboItems,
                                  );
                                  if (ctx.mounted) {
                                    setDlgState(() {});
                                  }
                                },
                        ),
                      ),
                      const SizedBox(height: 10),

                      // List of Added Items
                      if (comboItems.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          alignment: Alignment.center,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.restaurant_menu, size: 28, color: Colors.grey.shade400),
                              const SizedBox(height: 6),
                              Text(
                                'No food items added yet',
                                style: TextStyle(color: Colors.grey.shade700, fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Tap the button above to add food items.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                              ),
                            ],
                          ),
                        )
                      else ...[
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: Colors.grey.shade200),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: comboItems.length,
                            separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade200),
                            itemBuilder: (context, idx) {
                              final it = comboItems[idx];
                              final qty = (it['quantity'] as num?)?.toInt() ?? 1;
                              final basePrice = (it['base_price'] as num?)?.toDouble() ?? 0.0;

                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            it['item_name'] ?? '',
                                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Base: ${ReportExportService.formatCurrency(basePrice)} each',
                                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    // Quantity Stepper
                                    Container(
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade100,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: Colors.grey.shade300),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          InkWell(
                                            onTap: () {
                                              setDlgState(() {
                                                if (qty > 1) {
                                                  it['quantity'] = qty - 1;
                                                } else {
                                                  comboItems.removeAt(idx);
                                                }
                                              });
                                            },
                                            child: const Padding(
                                              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              child: Icon(Icons.remove, size: 14, color: Colors.black87),
                                            ),
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 4),
                                            child: Text(
                                              '$qty',
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                            ),
                                          ),
                                          InkWell(
                                            onTap: () {
                                              setDlgState(() {
                                                it['quantity'] = qty + 1;
                                              });
                                            },
                                            child: const Padding(
                                              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              child: Icon(Icons.add, size: 14, color: AppColors.primaryGreen),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    // Delete Button
                                    InkWell(
                                      onTap: () {
                                        setDlgState(() {
                                          comboItems.removeAt(idx);
                                        });
                                      },
                                      child: const Padding(
                                        padding: EdgeInsets.all(4),
                                        child: Icon(Icons.close, size: 16, color: Colors.red),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                        if (totalRegularPrice > 0) ...[
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.primaryLight.withOpacity(0.4),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Total Items Value: ${ReportExportService.formatCurrency(totalRegularPrice)}',
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.primaryDark),
                                ),
                                Text(
                                  '$totalItemsCount item${totalItemsCount == 1 ? '' : 's'} included',
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: isSaving
                      ? null
                      : () async {
                          final name = nameCtrl.text.trim();
                          final price = double.tryParse(priceCtrl.text.trim()) ?? 0.0;

                          if (name.isEmpty) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(content: Text('Please enter a combo name'), backgroundColor: Colors.red),
                            );
                            return;
                          }
                          if (price <= 0) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(content: Text('Please enter a valid price greater than 0'), backgroundColor: Colors.red),
                            );
                            return;
                          }
                          if (comboItems.isEmpty) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(content: Text('Please add at least one food item to this combo'), backgroundColor: Colors.red),
                            );
                            return;
                          }

                          setDlgState(() => isSaving = true);
                          try {
                            await notifier.saveCombo(
                              id: combo?['id'],
                              name: name,
                              price: price,
                              items: comboItems,
                            );
                            if (ctx.mounted) Navigator.pop(ctx);
                          } catch (e) {
                            setDlgState(() => isSaving = false);
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(content: Text('Failed to save combo: $e'), backgroundColor: Colors.red),
                              );
                            }
                          }
                        },
                  child: isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(isEdit ? 'Save Changes' : 'Create Combo'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showItemPicker(
    BuildContext context,
    List<Map<String, dynamic>> menuItems,
    List<Map<String, dynamic>> comboItems,
  ) async {
    // Filter out combos category items and only exclude if explicitly inactive
    final activeProducts = menuItems.where((m) {
      final cat = m['categories'] is Map ? m['categories'] as Map<String, dynamic> : null;
      final catSlug = (cat?['slug'] ?? '').toString().toLowerCase();
      final catName = (cat?['name'] ?? '').toString().toLowerCase();
      if (catSlug == 'combos' || catName == 'combos') return false;
      if (m['is_active'] == false) return false;
      return true;
    }).toList();

    final searchCtrl = TextEditingController();
    String query = '';

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (pickerCtx) {
        return StatefulBuilder(
          builder: (stfContext, setPickerState) {
            final q = query.trim().toLowerCase();
            final filtered = activeProducts.where((p) {
              if (q.isEmpty) return true;
              final name = (p['name'] ?? '').toString().toLowerCase();
              final cat = p['categories'] is Map ? p['categories'] as Map<String, dynamic> : null;
              final catName = (cat?['name'] ?? '').toString().toLowerCase();
              return name.contains(q) || catName.contains(q);
            }).toList();

            final totalAdded = comboItems.fold<int>(
              0,
              (sum, it) => sum + ((it['quantity'] as num?)?.toInt() ?? 1),
            );

            final screenH = MediaQuery.of(pickerCtx).size.height;
            final dialogH = (screenH * 0.7).clamp(320.0, 520.0);

            return AlertDialog(
              insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              title: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: AppColors.primaryLight,
                    radius: 14,
                    child: const Icon(Icons.fastfood, color: AppColors.primaryGreen, size: 16),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Select Food Items', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                  if (totalAdded > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$totalAdded selected',
                        style: const TextStyle(color: AppColors.primaryGreen, fontWeight: FontWeight.bold, fontSize: 11),
                      ),
                    ),
                ],
              ),
              content: SizedBox(
                width: MediaQuery.of(pickerCtx).size.width,
                height: dialogH,
                child: Column(
                  children: [
                    TextField(
                      controller: searchCtrl,
                      decoration: InputDecoration(
                        hintText: 'Search food products...',
                        prefixIcon: const Icon(Icons.search, size: 18),
                        suffixIcon: query.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 16),
                                onPressed: () {
                                  searchCtrl.clear();
                                  setPickerState(() => query = '');
                                },
                              )
                            : null,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        isDense: true,
                      ),
                      onChanged: (val) {
                        setPickerState(() => query = val);
                      },
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.search_off, size: 36, color: Colors.grey.shade400),
                                  const SizedBox(height: 8),
                                  Text(
                                    q.isEmpty ? 'No products available' : 'No products found matching "$query"',
                                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                                  ),
                                ],
                              ),
                            )
                          : ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 6),
                              itemBuilder: (context, idx) {
                                final p = filtered[idx];
                                final cat = p['categories'] is Map ? p['categories'] as Map<String, dynamic> : null;
                                final catName = cat?['name'] ?? '';
                                final basePrice = (p['base_price'] as num?)?.toDouble() ?? 0.0;
                                final idStr = p['id'].toString();

                                final existingIndex = comboItems.indexWhere(
                                  (it) => it['menu_item_id'].toString() == idStr,
                                );
                                final isAdded = existingIndex >= 0;
                                final currentQty = isAdded
                                    ? ((comboItems[existingIndex]['quantity'] as num?)?.toInt() ?? 1)
                                    : 0;

                                return Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(10),
                                    onTap: () {
                                      setPickerState(() {
                                        if (isAdded) {
                                          comboItems[existingIndex]['quantity'] = currentQty + 1;
                                        } else {
                                          comboItems.add({
                                            'menu_item_id': idStr,
                                            'item_name': p['name'].toString(),
                                            'base_price': basePrice,
                                            'quantity': 1,
                                          });
                                        }
                                      });
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: isAdded ? AppColors.primaryLight.withOpacity(0.25) : Colors.white,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: isAdded ? AppColors.primaryGreen : Colors.grey.shade300,
                                          width: isAdded ? 1.5 : 1.0,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 22,
                                            height: 22,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: isAdded ? AppColors.primaryGreen : Colors.grey.shade100,
                                              border: Border.all(
                                                color: isAdded ? AppColors.primaryGreen : Colors.grey.shade400,
                                              ),
                                            ),
                                            child: isAdded
                                                ? const Icon(Icons.check, size: 14, color: Colors.white)
                                                : null,
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  p['name'] ?? '',
                                                  style: TextStyle(
                                                    fontWeight: isAdded ? FontWeight.bold : FontWeight.w600,
                                                    fontSize: 13,
                                                    color: isAdded ? AppColors.primaryDark : Colors.black87,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                                const SizedBox(height: 2),
                                                Row(
                                                  children: [
                                                    Text(
                                                      ReportExportService.formatCurrency(basePrice),
                                                      style: const TextStyle(
                                                        color: AppColors.primaryGreen,
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                    if (catName.isNotEmpty) ...[
                                                      const SizedBox(width: 6),
                                                      Text(
                                                        '• $catName',
                                                        style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          if (isAdded)
                                            Container(
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(color: AppColors.primaryGreen),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  InkWell(
                                                    onTap: () {
                                                      setPickerState(() {
                                                        if (currentQty > 1) {
                                                          comboItems[existingIndex]['quantity'] = currentQty - 1;
                                                        } else {
                                                          comboItems.removeAt(existingIndex);
                                                        }
                                                      });
                                                    },
                                                    child: const Padding(
                                                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                      child: Icon(Icons.remove, size: 14, color: Colors.black87),
                                                    ),
                                                  ),
                                                  Padding(
                                                    padding: const EdgeInsets.symmetric(horizontal: 4),
                                                    child: Text(
                                                      '$currentQty',
                                                      style: const TextStyle(
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 12,
                                                        color: AppColors.primaryGreen,
                                                      ),
                                                    ),
                                                  ),
                                                  InkWell(
                                                    onTap: () {
                                                      setPickerState(() {
                                                        comboItems[existingIndex]['quantity'] = currentQty + 1;
                                                      });
                                                    },
                                                    child: const Padding(
                                                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                      child: Icon(Icons.add, size: 14, color: AppColors.primaryGreen),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            )
                                          else
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: AppColors.primaryLight,
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: const Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(Icons.add, size: 12, color: AppColors.primaryGreen),
                                                  SizedBox(width: 2),
                                                  Text(
                                                    'Select',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.bold,
                                                      color: AppColors.primaryGreen,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(pickerCtx),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryGreen,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                      ),
                      onPressed: () => Navigator.pop(pickerCtx),
                      child: Text('Done${totalAdded > 0 ? " ($totalAdded Items)" : ""}'),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

}


