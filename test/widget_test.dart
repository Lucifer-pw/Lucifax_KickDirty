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

      // Verify daily (only today paid order: KD-1 = 100,000)
      expect(recaps['daily'], equals(100000));

      // Verify weekly (today paid + yesterday paid + this week paid)
      // KD-1 (100k) + KD-3 (50k) + KD-4 (150k) = 300,000
      expect(recaps['weekly'], greaterThanOrEqualTo(300000));

      // Verify yearly (all paid orders)
      // KD-1 (100k) + KD-3 (50k) + KD-4 (150k) + KD-5 (300k) = 600,000
      expect(recaps['yearly'], equals(600000));
    });
  });
}
