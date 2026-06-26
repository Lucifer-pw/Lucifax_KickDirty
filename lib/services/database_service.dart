import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/service_model.dart';
import '../models/order_model.dart';
import '../models/expense_model.dart';

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

  // Generate unique sequential invoice ID using Firestore transaction counter
  // Format: KD-(nomor) — e.g. KD-1, KD-2, KD-3, ...
  // Uses atomic transaction to prevent duplicate numbers even with concurrent orders
  Future<String> generateInvoiceId() async {
    final counterRef = _db.collection('counters').doc('invoice');

    String invoiceId = await _db.runTransaction<String>((transaction) async {
      final counterDoc = await transaction.get(counterRef);

      int lastNumber = 0;
      if (counterDoc.exists) {
        lastNumber = (counterDoc.data()?['lastNumber'] as int?) ?? 0;
      }

      int newNumber = lastNumber + 1;

      // Atomically update the counter
      transaction.set(counterRef, {'lastNumber': newNumber});

      return "KD-$newNumber";
    });

    return invoiceId;
  }

  // Add Order with Idempotency Mechanism
  Future<String> addOrder(OrderModel order) async {
    // 1. Idempotency Check (may fail for customers due to rules — skip gracefully)
    if (order.idempotencyToken.isNotEmpty) {
      try {
        QuerySnapshot check = await _db
            .collection('orders')
            .where('idempotencyToken', isEqualTo: order.idempotencyToken)
            .limit(1)
            .get();

        if (check.docs.isNotEmpty) {
          if (kDebugMode) {
            print("Duplicate request detected. Skipping order creation for token: ${order.idempotencyToken}");
          }
          return check.docs.first.id;
        }
      } catch (e) {
        // Customer may not have permission to query all orders — proceed with creation
        if (kDebugMode) print("Idempotency check skipped: $e");
      }
    }

    // 2. Generate a fresh invoice ID if not defined (or reuse if it's already set)
    String invoiceId = order.id.isNotEmpty ? order.id : await generateInvoiceId();

    // Calculate points earned
    int pointsEarned = (order.totalAmount / 10000).floor();
    OrderModel finalOrder = OrderModel(
      id: invoiceId,
      idempotencyToken: order.idempotencyToken,
      customerName: order.customerName,
      customerPhone: order.customerPhone,
      customerId: order.customerId,
      items: order.items,
      totalAmount: order.totalAmount,
      status: order.status,
      paymentStatus: order.paymentStatus,
      qrisImage: order.qrisImage,
      notes: order.notes,
      deliveryType: order.deliveryType,
      deliveryAddress: order.deliveryAddress,
      deliveryFee: order.deliveryFee,
      photoBefore: order.photoBefore,
      photoAfter: order.photoAfter,
      pointsEarned: pointsEarned,
      pointsRedeemed: order.pointsRedeemed,
      createdAt: order.createdAt,
      updatedAt: order.updatedAt,
    );

    // 3. Write document to Firestore using set (idempotent if invoiceId is used as document key)
    await _db.collection('orders').doc(invoiceId).set(finalOrder.toMap());

    // 4. Award points if paymentStatus is sudah_bayar, or handle point deduction
    if (finalOrder.paymentStatus == 'sudah_bayar' || finalOrder.pointsRedeemed > 0) {
      await _awardPoints(finalOrder);
    }
    return invoiceId;
  }

  // Award and redeem points logic helper
  Future<void> _awardPoints(OrderModel order) async {
    try {
      int pointsEarned = order.paymentStatus == 'sudah_bayar' ? order.pointsEarned : 0;
      int pointsChange = pointsEarned - order.pointsRedeemed;

      if (pointsChange == 0) return;

      // Update registered user document points if customerId is present
      if (order.customerId.isNotEmpty) {
        await _db.collection('users').doc(order.customerId).update({
          'loyaltyPoints': FieldValue.increment(pointsChange),
        });
      }

      // Always update/increment in customers database
      if (order.customerPhone.isNotEmpty) {
        final custRef = _db.collection('customers').doc(order.customerPhone);
        final snap = await custRef.get();
        if (snap.exists) {
          await custRef.update({
            'loyaltyPoints': FieldValue.increment(pointsChange),
            'name': order.customerName,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          await custRef.set({
            'name': order.customerName,
            'phone': order.customerPhone,
            'loyaltyPoints': pointsChange > 0 ? pointsChange : 0,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }
    } catch (e) {
      if (kDebugMode) print("Error updating loyalty points: $e");
    }
  }

  // Update order status
  Future<void> updateOrderStatus(String orderId, String newStatus) async {
    await _db.collection('orders').doc(orderId).update({
      'status': newStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // Update order status with after photo
  Future<void> updateOrderStatusWithPhoto(String orderId, String newStatus, List<String> afterPhotos) async {
    await _db.collection('orders').doc(orderId).update({
      'status': newStatus,
      'photoAfter': afterPhotos,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // Update order payment status
  Future<void> updateOrderPaymentStatus(String orderId, String newPaymentStatus) async {
    if (newPaymentStatus == 'sudah_bayar') {
      try {
        DocumentSnapshot orderDoc = await _db.collection('orders').doc(orderId).get();
        if (orderDoc.exists) {
          OrderModel order = OrderModel.fromMap(orderDoc.data() as Map<String, dynamic>, orderDoc.id);
          if (order.paymentStatus != 'sudah_bayar') {
            await _awardPoints(order);
          }
        }
      } catch (e) {
        if (kDebugMode) print("Error awarding points on payment update: $e");
      }
    }

    await _db.collection('orders').doc(orderId).update({
      'paymentStatus': newPaymentStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ==========================================
  // EXPENSES CRUD
  // ==========================================

  // Get stream of all expenses
  Stream<List<ExpenseModel>> getExpenses() {
    return _db.collection('expenses').orderBy('createdAt', descending: true).snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => ExpenseModel.fromMap(doc.data(), doc.id)).toList();
    });
  }

  // Add a new expense
  Future<void> addExpense(ExpenseModel expense) async {
    await _db.collection('expenses').add(expense.toMap());
  }

  // Delete an expense
  Future<void> deleteExpense(String expenseId) async {
    await _db.collection('expenses').doc(expenseId).delete();
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

  // Calculate expenses recap
  Map<String, double> calculateExpensesRecap(List<ExpenseModel> expenses) {
    double daily = 0;
    double weekly = 0;
    double monthly = 0;
    double yearly = 0;

    DateTime now = DateTime.now();
    DateTime today = DateTime(now.year, now.month, now.day);
    
    int weekdayDiff = now.weekday - 1;
    DateTime startOfWeek = today.subtract(Duration(days: weekdayDiff));
    DateTime startOfMonth = DateTime(now.year, now.month, 1);
    DateTime startOfYear = DateTime(now.year, 1, 1);

    for (var exp in expenses) {
      DateTime expDate = exp.createdAt;

      if (expDate.isAfter(today) || expDate.isAtSameMomentAs(today)) {
        daily += exp.amount;
      }
      if (expDate.isAfter(startOfWeek) || expDate.isAtSameMomentAs(startOfWeek)) {
        weekly += exp.amount;
      }
      if (expDate.isAfter(startOfMonth) || expDate.isAtSameMomentAs(startOfMonth)) {
        monthly += exp.amount;
      }
      if (expDate.isAfter(startOfYear) || expDate.isAtSameMomentAs(startOfYear)) {
        yearly += exp.amount;
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
