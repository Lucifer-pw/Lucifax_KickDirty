import 'package:flutter_test/flutter_test.dart';
import 'package:lucifax_kickdirty/models/order_model.dart';
import 'package:lucifax_kickdirty/services/database_service.dart';

void main() {
  group('DatabaseService Sales Recap Tests', () {
    final dbService = DatabaseService();

    test('calculateSalesRecap correctly filters unpaid orders and groups totals', () {
      final now = DateTime.now();

      // Create test orders
      final orderTodayPaid = OrderModel(
        id: 'KD-1',
        idempotencyToken: 'tok-1',
        customerName: 'Customer 1',
        customerPhone: '628123456789',
        customerId: '',
        items: [
          OrderItem(itemName: 'Nike', serviceId: 's1', serviceName: 'Deep Clean', price: 100000)
        ],
        totalAmount: 100000,
        status: 'diterima',
        paymentStatus: 'sudah_bayar',
        qrisImage: '',
        notes: '',
        createdAt: now,
        updatedAt: now,
      );

      final orderTodayUnpaid = OrderModel(
        id: 'KD-2',
        idempotencyToken: 'tok-2',
        customerName: 'Customer 2',
        customerPhone: '628123456780',
        customerId: '',
        items: [
          OrderItem(itemName: 'Adidas', serviceId: 's1', serviceName: 'Deep Clean', price: 80000)
        ],
        totalAmount: 80000,
        status: 'diterima',
        paymentStatus: 'belum_bayar', // Should be excluded from sales recap
        qrisImage: '',
        notes: '',
        createdAt: now,
        updatedAt: now,
      );

      final orderYesterdayPaid = OrderModel(
        id: 'KD-3',
        idempotencyToken: 'tok-3',
        customerName: 'Customer 3',
        customerPhone: '628123456781',
        customerId: '',
        items: [
          OrderItem(itemName: 'Vans', serviceId: 's2', serviceName: 'Repaint', price: 50000)
        ],
        totalAmount: 50000,
        status: 'sedang_diproses',
        paymentStatus: 'sudah_bayar',
        qrisImage: '',
        notes: '',
        createdAt: now.subtract(const Duration(days: 1)),
        updatedAt: now.subtract(const Duration(days: 1)),
      );

      // Make sure 5 days ago falls within the same week if possible, or we just test general calculations.
      // We know weekday represents index. Subtracting safely.
      final int daysToStartOfWeek = now.weekday - 1;
      final DateTime dateThisWeek = now.subtract(Duration(days: daysToStartOfWeek > 1 ? 1 : 0)); // guarantee it's this week
      
      final orderThisWeekPaid = OrderModel(
        id: 'KD-4',
        idempotencyToken: 'tok-4',
        customerName: 'Customer 4',
        customerPhone: '628123456782',
        customerId: '',
        items: [
          OrderItem(itemName: 'Puma', serviceId: 's1', serviceName: 'Deep Clean', price: 150000)
        ],
        totalAmount: 150000,
        status: 'selesai',
        paymentStatus: 'sudah_bayar',
        qrisImage: '',
        notes: '',
        createdAt: dateThisWeek,
        updatedAt: dateThisWeek,
      );

      // 45 days ago: clearly another month, but same year
      final orderLastMonthPaid = OrderModel(
        id: 'KD-5',
        idempotencyToken: 'tok-5',
        customerName: 'Customer 5',
        customerPhone: '628123456783',
        customerId: '',
        items: [
          OrderItem(itemName: 'Converse', serviceId: 's3', serviceName: 'Reglue', price: 300000)
        ],
        totalAmount: 300000,
        status: 'diambil',
        paymentStatus: 'sudah_bayar',
        qrisImage: '',
        notes: '',
        createdAt: now.subtract(const Duration(days: 45)),
        updatedAt: now.subtract(const Duration(days: 45)),
      );

      final List<OrderModel> testOrders = [
        orderTodayPaid,
        orderTodayUnpaid,
        orderYesterdayPaid,
        orderThisWeekPaid,
        orderLastMonthPaid,
      ];

      // Run recap calculation
      final recaps = dbService.calculateSalesRecap(testOrders);

      // Dynamically calculate expected values based on real-time date
      final today = DateTime(now.year, now.month, now.day);
      
      double expectedDaily = 100000.0; // KD-1 is today
      if (dateThisWeek.isAfter(today) || dateThisWeek.isAtSameMomentAs(today)) {
        expectedDaily += 150000.0; // KD-4 falls on today
      }

      double expectedWeekly = 100000.0 + 150000.0; // KD-1 + KD-4 (both this week)
      double expectedYearly = 100000.0 + 150000.0; // KD-1 + KD-4

      final startOfWeek = today.subtract(Duration(days: now.weekday - 1));
      final startOfYear = DateTime(now.year, 1, 1);

      // Check if KD-3 (yesterday) falls in this week and this year
      final yesterday = now.subtract(const Duration(days: 1));
      if (yesterday.isAfter(startOfWeek) || yesterday.isAtSameMomentAs(startOfWeek)) {
        expectedWeekly += 50000.0;
      }
      if (yesterday.isAfter(startOfYear) || yesterday.isAtSameMomentAs(startOfYear)) {
        expectedYearly += 50000.0;
      }

      // Check if KD-5 (45 days ago) falls in this year
      final fortyFiveDaysAgo = now.subtract(const Duration(days: 45));
      if (fortyFiveDaysAgo.isAfter(startOfYear) || fortyFiveDaysAgo.isAtSameMomentAs(startOfYear)) {
        expectedYearly += 300000.0;
      }

      // Verify daily
      expect(recaps['daily'], equals(expectedDaily));

      // Verify weekly
      expect(recaps['weekly'], equals(expectedWeekly));

      // Verify yearly
      expect(recaps['yearly'], equals(expectedYearly));
    });
  });
}
