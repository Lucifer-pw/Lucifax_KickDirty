import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/service_model.dart';
import '../models/order_model.dart';

class DatabaseService with ChangeNotifier {
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  // ==========================================
  // SERVICES CRUD
  // ==========================================

  // Get stream of all services
  Stream<List<ServiceModel>> getServices() {
    return _db.collection('services').orderBy('createdAt', descending: true).snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => ServiceModel.fromMap(doc.data(), doc.id)).toList();
    });
  }

  // Add a new service
  Future<void> addService(ServiceModel service) async {
    await _db.collection('services').add(service.toMap());
  }

  // Update an existing service
  Future<void> updateService(ServiceModel service) async {
    await _db.collection('services').doc(service.id).update(service.toMap());
  }

  // Delete a service
  Future<void> deleteService(String serviceId) async {
    await _db.collection('services').doc(serviceId).delete();
  }

  // ==========================================
  // ORDERS MANAGEMENT
  // ==========================================

  // Get stream of all orders (Admin/Staff view)
  Stream<List<OrderModel>> getOrders() {
    return _db.collection('orders').orderBy('createdAt', descending: true).snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => OrderModel.fromMap(doc.data(), doc.id)).toList();
    });
  }

  // Get stream of customer orders
  Stream<List<OrderModel>> getCustomerOrders(String customerId) {
    return _db
        .collection('orders')
        .where('customerId', isEqualTo: customerId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => OrderModel.fromMap(doc.data(), doc.id)).toList();
    });
  }

  // Get stream of customer orders by WhatsApp phone number
  Stream<List<OrderModel>> getOrdersByPhone(String phoneNumber) {
    return _db
        .collection('orders')
        .where('customerPhone', isEqualTo: phoneNumber)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => OrderModel.fromMap(doc.data(), doc.id)).toList();
    });
  }

  // Generate unique invoice ID: KD-DDMMYYYY-XXX
  Future<String> generateInvoiceId() async {
    DateTime now = DateTime.now();
    String day = now.day.toString().padLeft(2, '0');
    String month = now.month.toString().padLeft(2, '0');
    String year = now.year.toString();
    String dateStr = "$day$month$year"; // e.g. 26062026

    // Query for orders created on this date to determine sequence
    DateTime startOfDay = DateTime(now.year, now.month, now.day);
    DateTime endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59);

    QuerySnapshot todayOrders = await _db
        .collection('orders')
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
        .get();

    int count = todayOrders.docs.length + 1;
    String sequence = count.toString().padLeft(3, '0'); // e.g. 001

    return "KD-$dateStr-$sequence";
  }

  // Add Order with Idempotency Mechanism
  Future<String> addOrder(OrderModel order) async {
    // 1. Idempotency Check: Verify if an order with the same token already exists
    if (order.idempotencyToken.isNotEmpty) {
      QuerySnapshot check = await _db
          .collection('orders')
          .where('idempotencyToken', isEqualTo: order.idempotencyToken)
          .limit(1)
          .get();

      if (check.docs.isNotEmpty) {
        // Order already created by a previous request, return existing ID
        if (kDebugMode) {
          print("Duplicate request detected. Skipping order creation for token: ${order.idempotencyToken}");
        }
        return check.docs.first.id;
      }
    }

    // 2. Generate a fresh invoice ID if not defined (or reuse if it's already set)
    String invoiceId = order.id.isNotEmpty ? order.id : await generateInvoiceId();

    // 3. Write document to Firestore using set (which is idempotent if invoiceId is used as document key)
    await _db.collection('orders').doc(invoiceId).set(order.toMap());
    return invoiceId;
  }

  // Update order status
  Future<void> updateOrderStatus(String orderId, String newStatus) async {
    await _db.collection('orders').doc(orderId).update({
      'status': newStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // Update order payment status
  Future<void> updateOrderPaymentStatus(String orderId, String newPaymentStatus) async {
    await _db.collection('orders').doc(orderId).update({
      'paymentStatus': newPaymentStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ==========================================
  // DASHBOARD SALES RECAPS
  // ==========================================

  // Calculate totals from orders list
  Map<String, double> calculateSalesRecap(List<OrderModel> orders) {
    double daily = 0;
    double weekly = 0;
    double monthly = 0;
    double yearly = 0;

    DateTime now = DateTime.now();
    DateTime today = DateTime(now.year, now.month, now.day);
    
    // Start of week (Monday)
    int weekdayDiff = now.weekday - 1;
    DateTime startOfWeek = today.subtract(Duration(days: weekdayDiff));
    
    // Start of month
    DateTime startOfMonth = DateTime(now.year, now.month, 1);
    
    // Start of year
    DateTime startOfYear = DateTime(now.year, 1, 1);

    for (var order in orders) {
      // Only count paid orders, or count all depending on business rule.
      // Usually, revenue only counts if paid ("sudah_bayar"), but we can count total sales.
      // Let's count total completed or paid sales. We will count all orders (or "sudah_bayar" orders).
      // Let's count orders that are "sudah_bayar" as revenue/penjualan.
      if (order.paymentStatus != 'sudah_bayar') continue;

      DateTime orderDate = order.createdAt;

      // Daily (today)
      if (orderDate.isAfter(today) || orderDate.isAtSameMomentAs(today)) {
        daily += order.totalAmount;
      }
      // Weekly
      if (orderDate.isAfter(startOfWeek) || orderDate.isAtSameMomentAs(startOfWeek)) {
        weekly += order.totalAmount;
      }
      // Monthly
      if (orderDate.isAfter(startOfMonth) || orderDate.isAtSameMomentAs(startOfMonth)) {
        monthly += order.totalAmount;
      }
      // Yearly
      if (orderDate.isAfter(startOfYear) || orderDate.isAtSameMomentAs(startOfYear)) {
        yearly += order.totalAmount;
      }
    }

    return {
      'daily': daily,
      'weekly': weekly,
      'monthly': monthly,
      'yearly': yearly,
    };
  }
}
