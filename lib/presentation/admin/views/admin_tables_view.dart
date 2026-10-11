import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../state/admin_provider.dart';

class AdminTablesView extends ConsumerWidget {
  const AdminTablesView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(adminProvider);
    final notifier = ref.read(adminProvider.notifier);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 600;
        final isTablet = constraints.maxWidth >= 600 && constraints.maxWidth < 1100;

        return Padding(
          padding: EdgeInsets.all(isMobile ? 12.0 : 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Restaurant Tables & Seating',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: isMobile ? 16 : 18,
                            color: const Color(0xFF0F2E1E),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${state.tables.length} configured tables',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: Text(
                      isMobile ? 'Add' : 'Add Table',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF266540),
                      foregroundColor: Colors.white,
                      elevation: 1,
                      padding: EdgeInsets.symmetric(
                        horizontal: isMobile ? 12 : 16,
                        vertical: isMobile ? 10 : 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () => _showTableDialog(context, null, notifier),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Content Area
              Expanded(
                child: state.isLoadingTables
                    ? const Center(
                        child: CircularProgressIndicator(color: Color(0xFF266540)),
                      )
                    : state.tables.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.table_restaurant_outlined,
                                  size: 48,
                                  color: Colors.grey.shade400,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'No tables configured yet.',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Tap "+ Add Table" above to add your first restaurant table.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : GridView.builder(
                            physics: const BouncingScrollPhysics(),
                            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: isMobile ? 200 : 240,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                              childAspectRatio: isMobile ? 0.95 : (isTablet ? 1.05 : 1.15),
                            ),
                            itemCount: state.tables.length,
                            itemBuilder: (context, index) {
                              final t = state.tables[index];
                              final isActive = t['is_active'] == true;
                              final status = (t['status'] ?? 'available').toString().toLowerCase();
                              final isOccupied = status == 'occupied';

                              return Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: isOccupied
                                        ? const Color(0xFFE67E22).withValues(alpha: 0.5)
                                        : (isActive
                                            ? const Color(0xFFE2E8E0)
                                            : Colors.red.shade100),
                                    width: isOccupied ? 1.5 : 1.0,
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
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Row 1: Table Name & Active Switch
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: isOccupied
                                                  ? const Color(0xFFFFF3E0)
                                                  : (isActive
                                                      ? const Color(0xFFE8F5E9)
                                                      : Colors.grey.shade100),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              'Table ${t['table_number']}',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 13,
                                                color: isOccupied
                                                    ? const Color(0xFFE67E22)
                                                    : (isActive
                                                        ? const Color(0xFF0F2E1E)
                                                        : Colors.grey.shade700),
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Transform.scale(
                                          scale: 0.72,
                                          alignment: Alignment.centerRight,
                                          child: Switch(
                                            value: isActive,
                                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                            activeTrackColor: const Color(0xFF266540),
                                            activeThumbColor: Colors.white,
                                            onChanged: (val) => notifier.toggleTableActive(t['id'], val),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const Spacer(),

                                    // Row 2: Seating Capacity
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.people_outline_rounded,
                                          size: 15,
                                          color: Colors.grey.shade600,
                                        ),
                                        const SizedBox(width: 5),
                                        Expanded(
                                          child: Text(
                                            'Capacity: ${t['seating_capacity'] ?? 4}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.grey.shade700,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const Spacer(),

                                    // Row 3: Status Badge & Edit Action
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 7,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isOccupied
                                                ? const Color(0xFFFFF3E0)
                                                : (isActive
                                                    ? const Color(0xFFE8F5E9)
                                                    : Colors.grey.shade100),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(
                                              color: isOccupied
                                                  ? const Color(0xFFE67E22).withValues(alpha: 0.3)
                                                  : (isActive
                                                      ? const Color(0xFF2D6A4F).withValues(alpha: 0.2)
                                                      : Colors.grey.shade300),
                                            ),
                                          ),
                                          child: Text(
                                            isOccupied
                                                ? 'OCCUPIED'
                                                : (isActive ? 'AVAILABLE' : 'INACTIVE'),
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: 0.3,
                                              color: isOccupied
                                                  ? const Color(0xFFE67E22)
                                                  : (isActive
                                                      ? const Color(0xFF2D6A4F)
                                                      : Colors.grey.shade600),
                                            ),
                                          ),
                                        ),
                                        InkWell(
                                          onTap: () => _showTableDialog(context, t, notifier),
                                          borderRadius: BorderRadius.circular(6),
                                          child: Container(
                                            padding: const EdgeInsets.all(5),
                                            decoration: BoxDecoration(
                                              color: Colors.grey.shade100,
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Icon(
                                              Icons.edit_outlined,
                                              size: 16,
                                              color: Colors.grey.shade700,
                                            ),
                                          ),
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
      },
    );
  }

  void _showTableDialog(BuildContext context, Map<String, dynamic>? table, dynamic notifier) {
    final isEdit = table != null;
    final numCtrl = TextEditingController(text: table?['table_number'] ?? '');
    final capCtrl = TextEditingController(
      text: table != null ? (table['seating_capacity'] ?? 4).toString() : '4',
    );

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          actionsPadding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.table_restaurant_rounded,
                  color: Color(0xFF266540),
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                isEdit ? 'Edit Table' : 'Add New Table',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                  color: Color(0xFF0F2E1E),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: numCtrl,
                decoration: InputDecoration(
                  labelText: 'Table Number * (e.g. 1, 2, T-1)',
                  labelStyle: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFF266540), width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: capCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Seating Capacity *',
                  labelStyle: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFF266540), width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              style: TextButton.styleFrom(
                foregroundColor: Colors.grey.shade700,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF266540),
                foregroundColor: Colors.white,
                elevation: 1,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                final numVal = numCtrl.text.trim();
                final capVal = int.tryParse(capCtrl.text.trim()) ?? 4;
                if (numVal.isEmpty) return;

                await notifier.saveTable(
                  id: table?['id'],
                  tableNumber: numVal,
                  seatingCapacity: capVal,
                );
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: Text(
                isEdit ? 'Save Changes' : 'Create Table',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        );
      },
    );
  }
}
