import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/order_model.dart';
import '../../theme.dart';
import '../../widgets/watermark.dart';

/// Detailed Sales Report screen that shows breakdown of revenue
/// for a specific period (daily, weekly, monthly, yearly).
class SalesDetailScreen extends StatelessWidget {
  final String periodTitle; // 'Harian', 'Mingguan', 'Bulanan', 'Tahunan'
  final String periodKey; // 'daily', 'weekly', 'monthly', 'yearly'
  final double totalAmount;
  final List<OrderModel> allOrders;
  final Color themeColor;

  const SalesDetailScreen({
    Key? key,
    required this.periodTitle,
    required this.periodKey,
    required this.totalAmount,
    required this.allOrders,
    required this.themeColor,
  }) : super(key: key);

  /// Filter orders for the given period that are paid
  List<OrderModel> _getFilteredOrders() {
    DateTime now = DateTime.now();
    DateTime today = DateTime(now.year, now.month, now.day);
    int weekdayDiff = now.weekday - 1;
    DateTime startOfWeek = today.subtract(Duration(days: weekdayDiff));
    DateTime startOfMonth = DateTime(now.year, now.month, 1);
    DateTime startOfYear = DateTime(now.year, 1, 1);

    DateTime startDate;
    switch (periodKey) {
      case 'daily':
        startDate = today;
        break;
      case 'weekly':
        startDate = startOfWeek;
        break;
      case 'monthly':
        startDate = startOfMonth;
        break;
      case 'yearly':
        startDate = startOfYear;
        break;
      default:
        startDate = today;
    }

    return allOrders.where((order) {
      if (order.paymentStatus != 'sudah_bayar') return false;
      return order.createdAt.isAfter(startDate) || order.createdAt.isAtSameMomentAs(startDate);
    }).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  /// Build service popularity analytics
  Map<String, Map<String, dynamic>> _getServiceAnalytics(List<OrderModel> orders) {
    Map<String, Map<String, dynamic>> serviceMap = {};

    for (var order in orders) {
      for (var item in order.items) {
        final name = item.serviceName;
        if (!serviceMap.containsKey(name)) {
          serviceMap[name] = {'count': 0, 'revenue': 0.0};
        }
        serviceMap[name]!['count'] = (serviceMap[name]!['count'] as int) + 1;
        serviceMap[name]!['revenue'] = (serviceMap[name]!['revenue'] as double) + item.price;
      }
    }

    return serviceMap;
  }

  /// Build shoe brand analytics
  Map<String, int> _getShoeBrandAnalytics(List<OrderModel> orders) {
    Map<String, int> brandMap = {};

    for (var order in orders) {
      for (var item in order.items) {
        final name = item.itemName.trim();
        if (name.isNotEmpty) {
          brandMap[name] = (brandMap[name] ?? 0) + 1;
        }
      }
    }

    return brandMap;
  }

  String _formatCurrency(double amount) {
    return amount.toStringAsFixed(0).replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]}.',
        );
  }

  @override
  Widget build(BuildContext context) {
    final filteredOrders = _getFilteredOrders();
    final serviceAnalytics = _getServiceAnalytics(filteredOrders);
    final brandAnalytics = _getShoeBrandAnalytics(filteredOrders);

    // Sort services by revenue descending
    final sortedServices = serviceAnalytics.entries.toList()
      ..sort((a, b) => (b.value['revenue'] as double).compareTo(a.value['revenue'] as double));

    // Sort brands by count descending
    final sortedBrands = brandAnalytics.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final maxServiceRevenue = sortedServices.isNotEmpty
        ? sortedServices.first.value['revenue'] as double
        : 1.0;

    final maxBrandCount = sortedBrands.isNotEmpty ? sortedBrands.first.value : 1;

    return Scaffold(
      appBar: AppBar(
        title: Text('Rincian Penjualan $periodTitle'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: filteredOrders.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.receipt_long_outlined, size: 64, color: themeColor.withOpacity(0.3)),
                  const SizedBox(height: 16),
                  Text(
                    'Belum ada transaksi $periodTitle',
                    style: const TextStyle(color: AppTheme.textGray, fontSize: 16),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ========== SUMMARY HEADER ==========
                  _buildSummaryHeader(filteredOrders),
                  const SizedBox(height: 20),

                  // ========== SERVICE REVENUE CHART ==========
                  if (sortedServices.isNotEmpty) ...[
                    _buildSectionTitle('Pendapatan per Layanan', Icons.pie_chart_outline),
                    const SizedBox(height: 12),
                    _buildServiceChart(sortedServices, maxServiceRevenue),
                    const SizedBox(height: 24),
                  ],

                  // ========== SHOE BRAND POPULARITY ==========
                  if (sortedBrands.isNotEmpty) ...[
                    _buildSectionTitle('Sepatu Paling Sering Dicuci', Icons.trending_up),
                    const SizedBox(height: 12),
                    _buildBrandChart(sortedBrands, maxBrandCount),
                    const SizedBox(height: 24),
                  ],

                  // ========== ORDER LIST ==========
                  _buildSectionTitle('Daftar Transaksi (${filteredOrders.length})', Icons.list_alt),
                  const SizedBox(height: 12),
                  ...filteredOrders.map((order) => _buildOrderCard(order)),
                  const SizedBox(height: 32),
                  const Center(child: Watermark()),
                ],
              ),
            ),
    );
  }

  Widget _buildSummaryHeader(List<OrderModel> orders) {
    final totalItems = orders.fold<int>(0, (sum, o) => sum + o.items.length);
    final avgPerOrder = orders.isNotEmpty ? totalAmount / orders.length : 0.0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [themeColor, themeColor.withOpacity(0.7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: themeColor.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          const Text(
            'Total Pendapatan',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Text(
            'Rp ${_formatCurrency(totalAmount)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildStatItem('Transaksi', '${orders.length}', Icons.receipt),
              Container(width: 1, height: 32, color: Colors.white24),
              _buildStatItem('Item', '$totalItems', Icons.checkroom),
              Container(width: 1, height: 32, color: Colors.white24),
              _buildStatItem('Rata-rata', 'Rp ${_formatCurrency(avgPerOrder)}', Icons.analytics),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white70, size: 18),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.white60, fontSize: 10),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: themeColor),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppTheme.darkBlueText,
          ),
        ),
      ],
    );
  }

  Widget _buildServiceChart(List<MapEntry<String, Map<String, dynamic>>> services, double maxRevenue) {
    // Color palette for bars
    final barColors = [
      Colors.blue,
      Colors.indigo,
      Colors.deepPurple,
      Colors.teal,
      Colors.orange,
      Colors.pink,
      Colors.cyan,
      Colors.amber,
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.lightGray),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        children: services.asMap().entries.map((entry) {
          final index = entry.key;
          final service = entry.value;
          final name = service.key;
          final revenue = service.value['revenue'] as double;
          final count = service.value['count'] as int;
          final ratio = maxRevenue > 0 ? revenue / maxRevenue : 0.0;
          final color = barColors[index % barColors.length];

          return Padding(
            padding: EdgeInsets.only(bottom: index < services.length - 1 ? 14 : 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.darkBlueText,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '$count pesanan',
                      style: const TextStyle(fontSize: 11, color: AppTheme.textGray),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: ratio,
                          backgroundColor: color.withOpacity(0.1),
                          valueColor: AlwaysStoppedAnimation<Color>(color),
                          minHeight: 10,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 100,
                      child: Text(
                        'Rp ${_formatCurrency(revenue)}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBrandChart(List<MapEntry<String, int>> brands, int maxCount) {
    final topBrands = brands.take(10).toList(); // Show top 10

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.lightGray),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        children: topBrands.asMap().entries.map((entry) {
          final index = entry.key;
          final brand = entry.value;
          final ratio = maxCount > 0 ? brand.value / maxCount : 0.0;
          final isTop = index == 0;

          return Padding(
            padding: EdgeInsets.only(bottom: index < topBrands.length - 1 ? 10 : 0),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isTop ? themeColor : AppTheme.textGray,
                    ),
                  ),
                ),
                if (isTop)
                  const Icon(Icons.emoji_events, color: Colors.amber, size: 16)
                else
                  const SizedBox(width: 16),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: Text(
                    brand.key,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isTop ? FontWeight.bold : FontWeight.normal,
                      color: AppTheme.darkBlueText,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: ratio,
                      backgroundColor: themeColor.withOpacity(0.08),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isTop ? themeColor : themeColor.withOpacity(0.5),
                      ),
                      minHeight: 8,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 40,
                  child: Text(
                    '${brand.value}x',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isTop ? themeColor : AppTheme.textGray,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildOrderCard(OrderModel order) {
    final dateFormat = DateFormat('dd MMM yyyy, HH:mm', 'id_ID');
    final formattedDate = dateFormat.format(order.createdAt);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.lightGray),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.receipt_outlined, size: 16, color: themeColor),
                  const SizedBox(width: 6),
                  Text(
                    order.id,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: themeColor,
                    ),
                  ),
                ],
              ),
              Text(
                'Rp ${_formatCurrency(order.totalAmount)}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.darkBlueText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.person_outline, size: 14, color: AppTheme.textGray),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  order.customerName,
                  style: const TextStyle(fontSize: 12, color: AppTheme.darkBlueText),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(Icons.access_time, size: 14, color: AppTheme.textGray),
              const SizedBox(width: 4),
              Text(
                formattedDate,
                style: const TextStyle(fontSize: 11, color: AppTheme.textGray),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: order.items.map((item) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: themeColor.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${item.itemName} • ${item.serviceName}',
                  style: TextStyle(fontSize: 11, color: themeColor, fontWeight: FontWeight.w500),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
