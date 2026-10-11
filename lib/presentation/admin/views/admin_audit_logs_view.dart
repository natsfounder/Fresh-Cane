import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/audit_log_model.dart';
import '../../../state/admin_provider.dart';

/// Professional, Responsive Audit Log & Audit History Screen.
///
/// Implements the structured WHO → DID WHAT → TO WHAT → WHEN → RESULT/CHANGE event model.
/// Adapts gracefully across:
/// - Phone Portrait (Compact audit cards)
/// - Phone Landscape (Expanded cards)
/// - Tablet Portrait (Spacious audit list)
/// - Tablet Landscape (Professional audit table)
class AdminAuditLogsView extends ConsumerStatefulWidget {
  const AdminAuditLogsView({super.key});

  @override
  ConsumerState<AdminAuditLogsView> createState() => _AdminAuditLogsViewState();
}

class _AdminAuditLogsViewState extends ConsumerState<AdminAuditLogsView> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedModule = 'ALL';
  DateTime? _selectedDate;

  final List<String> _modules = [
    'ALL',
    'MENU',
    'ORDERS',
    'BILLING',
    'EXPENSES',
    'USERS',
    'SETTINGS',
  ];

  @override
  void initState() {
    super.initState();
    // Ensure audit logs are loaded on view entry
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = ref.read(adminProvider);
      if (state.auditLogs.isEmpty && !state.isLoadingAuditLogs) {
        ref.read(adminProvider.notifier).loadAuditLogs();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(adminProvider);
    final notifier = ref.read(adminProvider.notifier);

    // Convert raw maps to structured domain models
    final allEntries = state.auditLogs.map((log) => AuditLogEntry.fromMap(log)).toList();

    // Filter entries
    final filteredEntries = allEntries.where((entry) {
      // 1. Module filter
      if (_selectedModule != 'ALL' && entry.module != _selectedModule) {
        return false;
      }

      // 2. Date filter
      if (_selectedDate != null) {
        final d1 = entry.createdAt;
        final d2 = _selectedDate!;
        if (d1.year != d2.year || d1.month != d2.month || d1.day != d2.day) {
          return false;
        }
      }

      // 3. Search query
      final query = _searchController.text.trim().toLowerCase();
      if (query.isNotEmpty) {
        final matchesUser = entry.userName.toLowerCase().contains(query);
        final matchesRole = entry.userRole.toLowerCase().contains(query);
        final matchesAction = entry.actionTitle.toLowerCase().contains(query) || entry.rawAction.toLowerCase().contains(query);
        final matchesEntity = entry.entityName.toLowerCase().contains(query) || entry.entityType.toLowerCase().contains(query);
        final matchesChange = entry.changeSummary.toLowerCase().contains(query);
        final matchesReason = entry.reason?.toLowerCase().contains(query) ?? false;
        final matchesId = entry.entityId?.toLowerCase().contains(query) ?? false;

        if (!matchesUser && !matchesRole && !matchesAction && !matchesEntity && !matchesChange && !matchesReason && !matchesId) {
          return false;
        }
      }

      return true;
    }).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final isTableLandscape = constraints.maxWidth >= 900;
        final isCompact = constraints.maxWidth < 600;

        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isCompact ? 12.0 : 20.0,
            vertical: 12.0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Header with title, record counter, and refresh button
              _buildHeader(
                isCompact: isCompact,
                totalCount: allEntries.length,
                filteredCount: filteredEntries.length,
                isLoading: state.isLoadingAuditLogs,
                onRefresh: () => notifier.loadAuditLogs(),
              ),

              const SizedBox(height: 12),

              // 2. Search and Filter Bar
              _buildFilterBar(isCompact: isCompact),

              const SizedBox(height: 12),

              // 3. Main Content (List / Table / Empty / Loading)
              Expanded(
                child: state.isLoadingAuditLogs && state.auditLogs.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(color: AppColors.primaryGreen),
                            SizedBox(height: 12),
                            Text('Loading audit trail records...', style: TextStyle(color: Colors.grey, fontSize: 13)),
                          ],
                        ),
                      )
                    : filteredEntries.isEmpty
                        ? _buildEmptyState(allEntries.isEmpty)
                        : isTableLandscape
                            ? _buildTableView(filteredEntries)
                            : _buildListView(filteredEntries, isCompact),
              ),
            ],
          ),
        );
      },
    );
  }

  // ===========================================================================
  // 1. HEADER SECTION
  // ===========================================================================

  Widget _buildHeader({
    required bool isCompact,
    required int totalCount,
    required int filteredCount,
    required bool isLoading,
    required VoidCallback onRefresh,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isCompact ? 14 : 18, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: AppColors.shadowSmall,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.shield_outlined, color: AppColors.primaryGreen, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        'Audit Trail & History',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: isCompact ? 16 : 18,
                          color: AppColors.primaryDark,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primaryGreen.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        filteredCount == totalCount ? '$totalCount events' : '$filteredCount of $totalCount',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primaryGreen,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Immutable log of business actions, role modifications, and system events',
                  style: TextStyle(fontSize: isCompact ? 11 : 12, color: AppColors.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Refresh audit log',
            icon: isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryGreen),
                  )
                : const Icon(Icons.refresh_rounded, color: AppColors.primaryGreen),
            onPressed: isLoading ? null : onRefresh,
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // 2. SEARCH & FILTER BAR
  // ===========================================================================

  Widget _buildFilterBar({required bool isCompact}) {
    final hasActiveFilter = _selectedModule != 'ALL' || _selectedDate != null || _searchController.text.isNotEmpty;

    return Container(
      padding: EdgeInsets.all(isCompact ? 10 : 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Search field + Date picker button + Reset button
          Row(
            children: [
              // Search input
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Search user, action, item, or ID...',
                      hintStyle: const TextStyle(fontSize: 12.5, color: AppColors.textTertiary),
                      prefixIcon: const Icon(Icons.search_rounded, size: 18, color: AppColors.textSecondary),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 16),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {});
                              },
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                      filled: true,
                      fillColor: AppColors.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppColors.borderLight),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppColors.borderLight),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppColors.primaryGreen, width: 1.5),
                      ),
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ),

              const SizedBox(width: 8),

              // Date Filter Button
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: _selectedDate != null ? AppColors.primaryLight : AppColors.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _selectedDate != null ? AppColors.primaryGreen : AppColors.borderLight,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.calendar_today_rounded,
                        size: 15,
                        color: _selectedDate != null ? AppColors.primaryGreen : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _selectedDate != null ? DateFormat('dd MMM').format(_selectedDate!) : 'Date',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: _selectedDate != null ? FontWeight.bold : FontWeight.w500,
                          color: _selectedDate != null ? AppColors.primaryGreen : AppColors.textSecondary,
                        ),
                      ),
                      if (_selectedDate != null) ...[
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: () => setState(() => _selectedDate = null),
                          child: const Icon(Icons.close_rounded, size: 14, color: AppColors.primaryGreen),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              if (hasActiveFilter) ...[
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Reset all filters',
                  icon: const Icon(Icons.filter_alt_off_rounded, size: 20, color: AppColors.textSecondary),
                  onPressed: () {
                    setState(() {
                      _selectedModule = 'ALL';
                      _selectedDate = null;
                      _searchController.clear();
                    });
                  },
                ),
              ],
            ],
          ),

          const SizedBox(height: 10),

          // Row 2: Module Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _modules.map((mod) {
                final isSelected = _selectedModule == mod;
                return Padding(
                  padding: const EdgeInsets.only(right: 6.0),
                  child: ChoiceChip(
                    label: Text(mod == 'ALL' ? 'All Modules' : mod),
                    selected: isSelected,
                    onSelected: (val) {
                      if (val) setState(() => _selectedModule = mod);
                    },
                    selectedColor: AppColors.primaryGreen,
                    backgroundColor: AppColors.surface,
                    labelStyle: TextStyle(
                      fontSize: 11.5,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected ? Colors.white : AppColors.textSecondary,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(
                        color: isSelected ? AppColors.primaryGreen : AppColors.borderLight,
                      ),
                    ),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2025),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primaryGreen,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: AppColors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  // ===========================================================================
  // 3. TABLE VIEW (TABLET LANDSCAPE / WIDE SCREENS >= 900px)
  // ===========================================================================

  Widget _buildTableView(List<AuditLogEntry> entries) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: AppColors.shadowSmall,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SingleChildScrollView(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(const Color(0xFFF4F7F5)),
              horizontalMargin: 16,
              columnSpacing: 18,
              headingTextStyle: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: AppColors.primaryDark,
                letterSpacing: 0.3,
              ),
              dataRowMinHeight: 52,
              dataRowMaxHeight: 58,
              columns: const [
                DataColumn(label: Text('DATE & TIME')),
                DataColumn(label: Text('ACTOR')),
                DataColumn(label: Text('MODULE')),
                DataColumn(label: Text('ACTION')),
                DataColumn(label: Text('ENTITY / TARGET')),
                DataColumn(label: Text('CHANGE SUMMARY')),
                DataColumn(label: Text('ACTIONS')),
              ],
              rows: entries.map((entry) {
                return DataRow(
                  cells: [
                    // 1. Date & Time
                    DataCell(
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            entry.formattedDate,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                          ),
                          Text(
                            entry.formattedTime,
                            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),

                    // 2. Actor
                    DataCell(
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            entry.userName,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: AppColors.borderLight),
                            ),
                            child: Text(
                              entry.userRole,
                              style: const TextStyle(fontSize: 10, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // 3. Module
                    DataCell(
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: entry.moduleColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(entry.moduleIcon, size: 12, color: entry.moduleColor),
                            const SizedBox(width: 4),
                            Text(
                              entry.module,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: entry.moduleColor,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // 4. Action
                    DataCell(
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: entry.actionColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          entry.actionTitle,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: entry.actionColor,
                          ),
                        ),
                      ),
                    ),

                    // 5. Entity
                    DataCell(
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 180),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              entry.entityName,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              entry.entityType,
                              style: const TextStyle(fontSize: 10.5, color: AppColors.textTertiary),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ),

                    // 6. Change Summary
                    DataCell(
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 220),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF6F8F6),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Text(
                            entry.changeSummary,
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1B4332),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),

                    // 7. Actions Button
                    DataCell(
                      IconButton(
                        tooltip: 'View event details',
                        icon: const Icon(Icons.visibility_outlined, size: 18, color: AppColors.primaryGreen),
                        onPressed: () => _showAuditDetails(entry),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // 4. LIST VIEW (MOBILE & TABLET PORTRAIT / < 900px)
  // ===========================================================================

  Widget _buildListView(List<AuditLogEntry> entries, bool isCompact) {
    return ListView.separated(
      itemCount: entries.length,
      separatorBuilder: (_, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final entry = entries[index];
        return _buildAuditCard(entry, isCompact);
      },
    );
  }

  Widget _buildAuditCard(AuditLogEntry entry, bool isCompact) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: AppColors.shadowSmall,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _showAuditDetails(entry),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row: Timestamp & Module Badge
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.access_time_rounded, size: 13, color: AppColors.textTertiary),
                        const SizedBox(width: 4),
                        Text(
                          entry.formattedDateTimeCompact,
                          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: entry.moduleColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(entry.moduleIcon, size: 11, color: entry.moduleColor),
                          const SizedBox(width: 4),
                          Text(
                            entry.module,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: entry.moduleColor,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // Middle section: Action Badge & Entity Name
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: entry.actionColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        entry.actionTitle,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: entry.actionColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        entry.entityName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13.5,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // Change Summary Chip
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF6F8F6),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE2EBE5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.arrow_right_alt_rounded, size: 16, color: AppColors.primaryGreen),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          entry.changeSummary,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1B4332),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                // Bottom row: Actor Info + View Details trigger
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 10,
                          backgroundColor: AppColors.primaryLight,
                          child: const Icon(Icons.person, size: 12, color: AppColors.primaryGreen),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${entry.userName} • ${entry.userRole}',
                          style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Text(
                          'Details',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primaryGreen.withValues(alpha: 0.9),
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.primaryGreen),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // 5. EMPTY STATE
  // ===========================================================================

  Widget _buildEmptyState(bool isAbsoluteEmpty) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(28),
        constraints: const BoxConstraints(maxWidth: 400),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isAbsoluteEmpty ? Icons.history_edu_rounded : Icons.search_off_rounded,
              size: 48,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: 12),
            Text(
              isAbsoluteEmpty ? 'No Audit Logs Recorded' : 'No Matching Audit Events',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 6),
            Text(
              isAbsoluteEmpty
                  ? 'System actions, price alterations, and security operations will appear here.'
                  : 'Try adjusting your search keywords, selected module, or date filter.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            if (!isAbsoluteEmpty) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Reset Filters'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primaryGreen,
                  side: const BorderSide(color: AppColors.primaryGreen),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () {
                  setState(() {
                    _selectedModule = 'ALL';
                    _selectedDate = null;
                    _searchController.clear();
                  });
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // 6. VIEW DETAILS MODAL (STRUCTURED, NON-TECHNICAL USER EXPERIENCE)
  // ===========================================================================

  void _showAuditDetails(AuditLogEntry entry) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.88,
            maxWidth: 680,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Modal Grab Handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 6),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Sheet Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: entry.actionColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(entry.moduleIcon, size: 18, color: entry.actionColor),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.actionTitle,
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.primaryDark),
                            ),
                            Text(
                              'Event ID: ${entry.id.length > 12 ? entry.id.substring(0, 12) : entry.id}...',
                              style: const TextStyle(fontSize: 10.5, color: AppColors.textTertiary),
                            ),
                          ],
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              const Divider(height: 1),

              // Sheet Scrollable Body
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. Overview Grid: WHO, WHEN, MODULE
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.borderLight),
                        ),
                        child: Column(
                          children: [
                            _buildDetailRow(
                              label: 'Actor (User)',
                              value: '${entry.userName} (${entry.userRole})',
                              icon: Icons.person_outline_rounded,
                            ),
                            const Divider(height: 14),
                            _buildDetailRow(
                              label: 'Date & Time',
                              value: entry.formattedDateTime,
                              icon: Icons.calendar_today_rounded,
                            ),
                            const Divider(height: 14),
                            _buildDetailRow(
                              label: 'System Module',
                              value: entry.module,
                              icon: entry.moduleIcon,
                            ),
                            const Divider(height: 14),
                            _buildDetailRow(
                              label: 'Affected Entity',
                              value: entry.entityName,
                              icon: Icons.inventory_2_outlined,
                            ),
                            if (entry.entityId != null && entry.entityId!.isNotEmpty) ...[
                              const Divider(height: 14),
                              _buildDetailRow(
                                label: 'Entity ID / Ref',
                                value: entry.entityId!,
                                icon: Icons.tag_rounded,
                              ),
                            ],
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // 2. Structured State Comparison (Previous vs New)
                      const Text(
                        'Change Inspection',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.primaryDark),
                      ),
                      const SizedBox(height: 8),

                      LayoutBuilder(
                        builder: (context, boxConstraints) {
                          final isSideBySide = boxConstraints.maxWidth > 450;
                          return isSideBySide
                              ? Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: _buildStateCard(
                                        title: 'PREVIOUS VALUE / STATE',
                                        content: entry.previousStateText,
                                        isPrevious: true,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: _buildStateCard(
                                        title: 'NEW VALUE / STATE',
                                        content: entry.newStateText,
                                        isPrevious: false,
                                      ),
                                    ),
                                  ],
                                )
                              : Column(
                                  children: [
                                    _buildStateCard(
                                      title: 'PREVIOUS VALUE / STATE',
                                      content: entry.previousStateText,
                                      isPrevious: true,
                                    ),
                                    const SizedBox(height: 8),
                                    _buildStateCard(
                                      title: 'NEW VALUE / STATE',
                                      content: entry.newStateText,
                                      isPrevious: false,
                                    ),
                                  ],
                                );
                        },
                      ),

                      // 3. Reason / Metadata (if present)
                      if (entry.reason != null) ...[
                        const SizedBox(height: 16),
                        const Text(
                          'Recorded Reason / Remarks',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.primaryDark),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF9E8),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFF3E5AB)),
                          ),
                          child: Text(
                            entry.reason!,
                            style: const TextStyle(fontSize: 13, color: AppColors.woodDark, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],

                      const SizedBox(height: 20),

                      // 4. Secondary Collapsible Technical Data
                      Theme(
                        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: const Row(
                            children: [
                              Icon(Icons.code_rounded, size: 16, color: AppColors.textTertiary),
                              SizedBox(width: 6),
                              Text(
                                'Technical Audit Data (Advanced)',
                                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                          children: [
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E222A),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'EVENT UUID: ${entry.id}',
                                    style: const TextStyle(color: Colors.greenAccent, fontSize: 11, fontFamily: 'monospace'),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'ACTOR UUID: ${entry.userId ?? "NULL"}',
                                    style: const TextStyle(color: Colors.lightBlueAccent, fontSize: 11, fontFamily: 'monospace'),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'TABLE/ENTITY: ${entry.entityType}',
                                    style: const TextStyle(color: Colors.amberAccent, fontSize: 11, fontFamily: 'monospace'),
                                  ),
                                  const SizedBox(height: 8),
                                  if (entry.oldData != null) ...[
                                    const Text('OLD DATA (JSONB):', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 2),
                                    Text(
                                      const JsonEncoder.withIndent('  ').convert(entry.oldData),
                                      style: const TextStyle(color: Colors.white60, fontSize: 10.5, fontFamily: 'monospace'),
                                    ),
                                    const SizedBox(height: 6),
                                  ],
                                  if (entry.newData != null) ...[
                                    const Text('NEW DATA (JSONB):', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 2),
                                    Text(
                                      const JsonEncoder.withIndent('  ').convert(entry.newData),
                                      style: const TextStyle(color: Colors.white60, fontSize: 10.5, fontFamily: 'monospace'),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDetailRow({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildStateCard({
    required String title,
    required String content,
    required bool isPrevious,
  }) {
    final bgColor = isPrevious ? const Color(0xFFFBFBFB) : const Color(0xFFF3F9F5);
    final borderColor = isPrevious ? Colors.grey.shade300 : const Color(0xFFB7DFC6);
    final titleColor = isPrevious ? Colors.grey.shade700 : const Color(0xFF1B4332);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: titleColor,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            content,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              height: 1.4,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
