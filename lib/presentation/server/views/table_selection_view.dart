import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/responsive.dart';
import '../../../models/models.dart';
import '../../../state/server_order_provider.dart';

/// Step 1 / Default Landing Screen: Tables Screen.
///
/// Features:
/// - Responsive grid of table cards (3–4 columns on tablet landscape).
/// - Shows Table Number, color-coded Status (Available / Occupied).
/// - Shows Seating Count Badge when occupied (e.g. "2 seatings" / "1 seating").
/// - Tapping a table opens the Order Screen for that table.
/// - Data synced in real time via Supabase Realtime.
class TableSelectionView extends ConsumerStatefulWidget {
  const TableSelectionView({super.key});

  @override
  ConsumerState<TableSelectionView> createState() => _TableSelectionViewState();
}

class _TableSelectionViewState extends ConsumerState<TableSelectionView> {
  final TextEditingController _searchController = TextEditingController();
  String _filterQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _filterQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onTableTapped(RestaurantTable table) async {
    HapticFeedback.lightImpact();
    // Tapping any table (new or existing) enters Table Context (Step 2)
    ref.read(serverOrderProvider.notifier).openTable(table);
  }

  @override
  Widget build(BuildContext context) {
    final orderState = ref.watch(serverOrderProvider);
    final allTables = orderState.tables;

    final filteredTables = allTables.where((t) {
      if (!t.isActive) return false;
      if (_filterQuery.isNotEmpty) {
        if (!t.tableNumber.toLowerCase().contains(_filterQuery)) return false;
      }
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F2),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ─── Mockup Header: Select Table + Filter Pills + Search Bar ────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                bottom: BorderSide(color: Colors.grey.shade200, width: 1),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 16,
              runSpacing: 12,
              children: [
                // Title
                const Text(
                  'Select Table',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F2E1E),
                    letterSpacing: -0.3,
                  ),
                ),

                // Search Bar
                SizedBox(
                  width: 240,
                  height: 38,
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(fontSize: 13, color: Color(0xFF1A2E20)),
                    decoration: InputDecoration(
                      hintText: 'Search table...',
                      hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                      prefixIcon: Icon(Icons.search_rounded, size: 18, color: Colors.grey.shade500),
                      suffixIcon: _filterQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 16),
                              onPressed: () => _searchController.clear(),
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                      filled: true,
                      fillColor: const Color(0xFFF8F9F7),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: const BorderSide(color: Color(0xFF266540), width: 1.5),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ─── Responsive Tables Grid ────────────────────────────────────────
          Expanded(
            child: orderState.isLoading && allTables.isEmpty
                ? const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFF266540),
                    ),
                  )
                : filteredTables.isEmpty
                    ? Center(
                        child: Text(
                          _filterQuery.isNotEmpty
                              ? 'No tables match "$_filterQuery"'
                              : 'No tables found',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final crossAxisCount = Responsive.gridColumns(context);
                          final spacing = Responsive.gridSpacing(context);
                          final aspectRatio = Responsive.tableCardAspectRatio(context);
                          final padding = Responsive.screenPadding(context);

                          return GridView.builder(
                            padding: padding,
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: crossAxisCount,
                              crossAxisSpacing: spacing,
                              mainAxisSpacing: spacing,
                              childAspectRatio: aspectRatio,
                            ),
                            itemCount: filteredTables.length,
                            itemBuilder: (context, index) {
                              final table = filteredTables[index];
                              return _TableCard(
                                table: table,
                                onTap: () => _onTableTapped(table),
                              );
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

/// Modern individual Table Card matching Mockup Screen 2.
class _TableCard extends StatelessWidget {
  final RestaurantTable table;
  final VoidCallback onTap;

  const _TableCard({
    required this.table,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isOccupied = table.isOccupied;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isOccupied
                  ? const Color(0xFFFED7AA)
                  : const Color(0xFFE2E8E0),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Table Number
              Text(
                table.tableNumber,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F2E1E),
                ),
              ),
              const SizedBox(height: 4),

              // Capacity
              Text(
                table.seatingsLabel,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 10),

              // Status Pill (Occupied = Orange pill, Available = Soft Green pill)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  color: isOccupied
                      ? const Color(0xFFE67E22)
                      : (table.isActive ? const Color(0xFFE8F5E9) : Colors.grey.shade200),
                  borderRadius: BorderRadius.circular(12),
                  border: isOccupied
                      ? null
                      : Border.all(
                          color: table.isActive ? const Color(0xFFA7D489) : Colors.grey.shade400,
                          width: 1,
                        ),
                ),
                child: Text(
                  isOccupied ? 'Occupied' : (table.isActive ? 'Available' : 'Unavailable'),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isOccupied
                        ? Colors.white
                        : (table.isActive ? const Color(0xFF2D6A4F) : Colors.grey.shade600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
