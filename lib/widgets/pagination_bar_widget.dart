import 'dart:math';
import 'package:flutter/material.dart';
import '../theme.dart';

class PaginationBarWidget extends StatelessWidget {
  final int totalItems;
  final int currentPage;
  final int itemsPerPage;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<int> onItemsPerPageChanged;
  final List<int> availableItemsPerPage;
  final String itemUnitName;

  const PaginationBarWidget({
    Key? key,
    required this.totalItems,
    required this.currentPage,
    required this.itemsPerPage,
    required this.onPageChanged,
    required this.onItemsPerPageChanged,
    this.availableItemsPerPage = const [10, 25, 50, 100],
    this.itemUnitName = 'transaksi',
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final int totalPages = max(1, (totalItems / itemsPerPage).ceil());
    final int startItem = totalItems == 0 ? 0 : ((currentPage - 1) * itemsPerPage) + 1;
    final int endItem = min(currentPage * itemsPerPage, totalItems);

    final bool isFirstPage = currentPage <= 1;
    final bool isLastPage = currentPage >= totalPages;

    final isDark = AppTheme.isDarkMode;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          width: 1,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 600;

          final infoText = Text(
            totalItems == 0
                ? 'Tidak ada $itemUnitName'
                : 'Menampilkan $startItem-$endItem dari $totalItems $itemUnitName',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
          );

          final controlsRow = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Items per page dropdown
              Text(
                'Tampilkan: ',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                ),
              ),
              const SizedBox(width: 4),
              DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: availableItemsPerPage.contains(itemsPerPage)
                      ? itemsPerPage
                      : availableItemsPerPage.first,
                  dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                  isDense: true,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : AppTheme.darkBlueText,
                  ),
                  items: availableItemsPerPage.map((count) {
                    return DropdownMenuItem<int>(
                      value: count,
                      child: Text('$count / hal'),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      onItemsPerPageChanged(val);
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),

              // Navigation Buttons
              // First Page |<
              IconButton(
                icon: const Icon(Icons.first_page, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                color: isFirstPage
                    ? (isDark ? Colors.white24 : Colors.black26)
                    : AppTheme.primaryBlue,
                onPressed: isFirstPage ? null : () => onPageChanged(1),
                tooltip: 'Halaman Pertama',
              ),

              // Prev Page <
              IconButton(
                icon: const Icon(Icons.chevron_left, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                color: isFirstPage
                    ? (isDark ? Colors.white24 : Colors.black26)
                    : AppTheme.primaryBlue,
                onPressed: isFirstPage ? null : () => onPageChanged(currentPage - 1),
                tooltip: 'Halaman Sebelumnya',
              ),

              const SizedBox(width: 4),

              // Current Page Indicator Pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
                  ),
                ),
                child: Text(
                  'Hal $currentPage dari $totalPages',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : AppTheme.darkBlueText,
                  ),
                ),
              ),

              const SizedBox(width: 4),

              // Next Page >
              IconButton(
                icon: const Icon(Icons.chevron_right, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                color: isLastPage
                    ? (isDark ? Colors.white24 : Colors.black26)
                    : AppTheme.primaryBlue,
                onPressed: isLastPage ? null : () => onPageChanged(currentPage + 1),
                tooltip: 'Halaman Berikutnya',
              ),

              // Last Page >|
              IconButton(
                icon: const Icon(Icons.last_page, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                color: isLastPage
                    ? (isDark ? Colors.white24 : Colors.black26)
                    : AppTheme.primaryBlue,
                onPressed: isLastPage ? null : () => onPageChanged(totalPages),
                tooltip: 'Halaman Terakhir',
              ),
            ],
          );

          if (isNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                infoText,
                const SizedBox(height: 8),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: controlsRow,
                ),
              ],
            );
          }

          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              infoText,
              controlsRow,
            ],
          );
        },
      ),
    );
  }
}
