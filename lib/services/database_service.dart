import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import '../models/service_model.dart';
import '../models/order_model.dart';

class DatabaseService with ChangeNotifier {
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  // In-memory collections for local fallback
  final List<ServiceModel> _localServices = [];
  final List<OrderModel> _localOrders = [];

  final StreamController<List<ServiceModel>> _servicesController =
      StreamController<List<ServiceModel>>.broadcast();
  final StreamController<List<OrderModel>> _ordersController =
      StreamController<List<OrderModel>>.broadcast();

  DatabaseService() {
    if (Firebase.apps.isEmpty) {
      // Add default mock services
      _localServices.addAll([
        ServiceModel(
          id: 'svc1',
          name: 'Cuci Kering Setrika',
          price: 8000,
          description: 'Layanan cuci bersih dan setrika rapi.',
          createdAt: DateTime.now().subtract(const Duration(days: 5)),
        ),
        ServiceModel(
          id: 'svc2',
          name: 'Setrika Saja',
          price: 5000,
          description: 'Layanan setrika rapi per kilogram.',
          createdAt: DateTime.now().subtract(const Duration(days: 4)),
        ),
        ServiceModel(
          id: 'svc3',
          name: 'Cuci Selimut',
          price: 25000,
          description: 'Cuci bersih selimut / bed cover.',
          createdAt: DateTime.now().subtract(const Duration(days: 3)),
        ),
        ServiceModel(
          id: 'svc4',
          name: 'Cuci Sepatu Premium',
          price: 35000,
          description: 'Cuci detail sepatu premium.',
          createdAt: DateTime.now().subtract(const Duration(days: 2)),
        ),
      ]);

      // Add default mock orders
      _localOrders.addAll([
        OrderModel(
          id: 'KD-26062026-001',
          customerName: 'Budi Santoso',
          customerPhone: '081234567890',
          customerId: 'cust1',
          items: [
            OrderItem(
              itemName: 'Pakaian Harian (5 kg)',
              serviceId: 'svc1',
              serviceName: 'Cuci Kering Setrika',
              price: 8000,
            )
          ],
          totalAmount: 40000,
          status: 'sedang_diproses',
          paymentStatus: 'belum_bayar',
          qrisImage: '',
          notes: 'Jangan dicampur pakaian luntur',
          idempotencyToken: 'token1',
          createdAt: DateTime.now().subtract(const Duration(hours: 4)),
          updatedAt: DateTime.now().subtract(const Duration(hours: 4)),
        ),
        OrderModel(
          id: 'KD-25062026-002',
          customerName: 'Siti Rahma',
          customerPhone: '089876543210',
          customerId: 'cust2',
          items: [
            OrderItem(
              itemName: 'Sepatu Sneaker Nike',
              serviceId: 'svc4',
              serviceName: 'Cuci Sepatu Premium',
              price: 35000,
            )
          ],
          totalAmount: 35000,
          status: 'selesai',
          paymentStatus: 'sudah_bayar',
          qrisImage: '',
          notes: '',
          idempotencyToken: 'token2',
          createdAt: DateTime.now().subtract(const Duration(days: 1)),
          updatedAt: DateTime.now().subtract(const Duration(days: 1)),
        ),
        OrderModel(
          id: 'KD-25062026-003',
          customerName: 'Andi Wijaya',
          customerPhone: '085678901234',
          customerId: 'cust3',
          items: [
            OrderItem(
              itemName: 'Bed Cover King Size',
              serviceId: 'svc3',
              serviceName: 'Cuci Selimut',
              price: 25000,
            )
          ],
          totalAmount: 50000,
          status: 'diterima',
          paymentStatus: 'belum_bayar',
          qrisImage: '',
          notes: '',
          idempotencyToken: 'token3',
          createdAt: DateTime.now().subtract(const Duration(hours: 2)),
          updatedAt: DateTime.now().subtract(const Duration(hours: 2)),
        ),
      ]);
    }
  }

  void _notifyServices() {
    if (!_servicesController.isClosed) {
      _servicesController.add(List.from(_localServices));
    }
  }

  void _notifyOrders() {
    if (!_ordersController.isClosed) {
      _ordersController.add(List.from(_localOrders));
    }
  }

  // ==========================================
  // SERVICES CRUD
  // ==========================================

  // Get stream of all services
  Stream<List<ServiceModel>> getServices() {
    if (Firebase.apps.isNotEmpty) {
      return _db.collection('services').orderBy('createdAt', descending: true).snapshots().map((snapshot) {
        return snapshot.docs.map((doc) => ServiceModel.fromMap(doc.data(), doc.id)).toList();
      });
    } else {
      Timer.run(() => _notifyServices());
      return _servicesController.stream;
    }
  }

  // Add a new service
  Future<void> addService(ServiceModel service) async {
    if (Firebase.apps.isNotEmpty) {
      await _db.collection('services').add(service.toMap());
    } else {
      final newService = ServiceModel(
        id: 'svc_${DateTime.now().millisecondsSinceEpoch}',
        name: service.name,
        price: service.price,
        description: service.description,
        createdAt: service.createdAt,
      );
      _localServices.add(newService);
      _notifyServices();
      notifyListeners();
    }
  }

  // Update an existing service
  Future<void> updateService(ServiceModel service) async {
    if (Firebase.apps.isNotEmpty) {
      await _db.collection('services').doc(service.id).update(service.toMap());
    } else {
      final idx = _localServices.indexWhere((s) => s.id == service.id);
      if (idx != -1) {
        _localServices[idx] = service;
        _notifyServices();
        notifyListeners();
      }
    }
  }

  // Delete a service
  Future<void> deleteService(String serviceId) async {
    if (Firebase.apps.isNotEmpty) {
      await _db.collection('services').doc(serviceId).delete();
    } else {
      _localServices.removeWhere((s) => s.id == serviceId);
      _notifyServices();
      notifyListeners();
    }
  }

  // ==========================================
  // ORDERS MANAGEMENT
  // ==========================================

  // Get stream of all orders (Admin/Staff view)
  Stream<List<OrderModel>> getOrders() {
    if (Firebase.apps.isNotEmpty) {
      return _db.collection('orders').orderBy('createdAt', descending: true).snapshots().map((snapshot) {
        return snapshot.docs.map((doc) => OrderModel.fromMap(doc.data(), doc.id)).toList();
      });
    } else {
      Timer.run(() => _notifyOrders());
      return _ordersController.stream;
    }
  }

  // Get stream of customer orders
  Stream<List<OrderModel>> getCustomerOrders(String customerId) {
    if (Firebase.apps.isNotEmpty) {
      return _db
          .collection('orders')
          .where('customerId', isEqualTo: customerId)
          .orderBy('createdAt', descending: true)
          .snapshots()
          .map((snapshot) {
        return snapshot.docs.map((doc) => OrderModel.fromMap(doc.data(), doc.id)).toList();
      });
    } else {
      final filtered = _localOrders.where((o) => o.customerId == customerId).toList();
      filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final controller = StreamController<List<OrderModel>>();
      Timer.run(() {
        controller.add(filtered);
        controller.close();
      });
      return controller.stream;
    }
  }

  // Get stream of customer orders by WhatsApp phone number
  Stream<List<OrderModel>> getOrdersByPhone(String phoneNumber) {
    if (Firebase.apps.isNotEmpty) {
      return _db
          .collection('orders')
          .where('customerPhone', isEqualTo: phoneNumber)
          .orderBy('createdAt', descending: true)
          .snapshots()
          .map((snapshot) {
        return snapshot.docs.map((doc) => OrderModel.fromMap(doc.data(), doc.id)).toList();
      });
    } else {
      final filtered = _localOrders.where((o) => o.customerPhone == phoneNumber).toList();
      filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final controller = StreamController<List<OrderModel>>();
      Timer.run(() {
        controller.add(filtered);
        controller.close();
      });
      return controller.stream;
    }
  }

  // Generate unique invoice ID: KD-DDMMYYYY-XXX
  Future<String> generateInvoiceId() async {
    DateTime now = DateTime.now();
    String day = now.day.toString().padLeft(2, '0');
    String month = now.month.toString().padLeft(2, '0');
    String year = now.year.toString();
    String dateStr = "$day$month$year"; // e.g. 26062026

    if (Firebase.apps.isNotEmpty) {
      DateTime startOfDay = DateTime(now.year, now.month, now.day);
      DateTime endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59);

      QuerySnapshot todayOrders = await _db
          .collection('orders')
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
          .get();

      int count = todayOrders.docs.length + 1;
      String sequence = count.toString().padLeft(3, '0');

      return "KD-$dateStr-$sequence";
    } else {
      DateTime startOfDay = DateTime(now.year, now.month, now.day);
      DateTime endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59);
      final todayCount = _localOrders
          .where((o) => o.createdAt.isAfter(startOfDay) && o.createdAt.isBefore(endOfDay))
          .length;
      String sequence = (todayCount + 1).toString().padLeft(3, '0');
      return "KD-$dateStr-$sequence";
    }
  }

  // Add Order with Idempotency Mechanism
  Future<String> addOrder(OrderModel order) async {
    if (Firebase.apps.isNotEmpty) {
      if (order.idempotencyToken.isNotEmpty) {
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
      }

      String invoiceId = order.id.isNotEmpty ? order.id : await generateInvoiceId();
      await _db.collection('orders').doc(invoiceId).set(order.toMap());
      return invoiceId;
    } else {
      if (order.idempotencyToken.isNotEmpty) {
        final existing = _localOrders.where((o) => o.idempotencyToken == order.idempotencyToken);
        if (existing.isNotEmpty) {
          if (kDebugMode) {
            print("Duplicate request detected (Local). Skipping order creation for token: ${order.idempotencyToken}");
          }
          return existing.first.id;
        }
      }

      String invoiceId = order.id.isNotEmpty ? order.id : await generateInvoiceId();
      final newOrder = OrderModel(
        id: invoiceId,
        idempotencyToken: order.idempotencyToken,
        customerName: order.customerName,
        customerPhone: order.customerPhone,
        customerId: order.customerId.isNotEmpty ? order.customerId : 'cust_${DateTime.now().millisecondsSinceEpoch}',
        items: order.items,
        totalAmount: order.totalAmount,
        status: order.status,
        paymentStatus: order.paymentStatus,
        qrisImage: order.qrisImage,
        notes: order.notes,
        createdAt: order.createdAt,
        updatedAt: DateTime.now(),
      );
      _localOrders.add(newOrder);
      _notifyOrders();
      notifyListeners();
      return invoiceId;
    }
  }

  // Update order status
  Future<void> updateOrderStatus(String orderId, String newStatus) async {
    if (Firebase.apps.isNotEmpty) {
      await _db.collection('orders').doc(orderId).update({
        'status': newStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      final idx = _localOrders.indexWhere((o) => o.id == orderId);
      if (idx != -1) {
        final updated = OrderModel(
          id: _localOrders[idx].id,
          idempotencyToken: _localOrders[idx].idempotencyToken,
          customerName: _localOrders[idx].customerName,
          customerPhone: _localOrders[idx].customerPhone,
          customerId: _localOrders[idx].customerId,
          items: _localOrders[idx].items,
          totalAmount: _localOrders[idx].totalAmount,
          status: newStatus,
          paymentStatus: _localOrders[idx].paymentStatus,
          qrisImage: _localOrders[idx].qrisImage,
          notes: _localOrders[idx].notes,
          createdAt: _localOrders[idx].createdAt,
          updatedAt: DateTime.now(),
        );
        _localOrders[idx] = updated;
        _notifyOrders();
        notifyListeners();
      }
    }
  }

  // Update order payment status
  Future<void> updateOrderPaymentStatus(String orderId, String newPaymentStatus) async {
    if (Firebase.apps.isNotEmpty) {
      await _db.collection('orders').doc(orderId).update({
        'paymentStatus': newPaymentStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      final idx = _localOrders.indexWhere((o) => o.id == orderId);
      if (idx != -1) {
        final updated = OrderModel(
          id: _localOrders[idx].id,
          idempotencyToken: _localOrders[idx].idempotencyToken,
          customerName: _localOrders[idx].customerName,
          customerPhone: _localOrders[idx].customerPhone,
          customerId: _localOrders[idx].customerId,
          items: _localOrders[idx].items,
          totalAmount: _localOrders[idx].totalAmount,
          status: _localOrders[idx].status,
          paymentStatus: newPaymentStatus,
          qrisImage: _localOrders[idx].qrisImage,
          notes: _localOrders[idx].notes,
          createdAt: _localOrders[idx].createdAt,
          updatedAt: DateTime.now(),
        );
        _localOrders[idx] = updated;
        _notifyOrders();
        notifyListeners();
      }
    }
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

    int weekdayDiff = now.weekday - 1;
    DateTime startOfWeek = today.subtract(Duration(days: weekdayDiff));

    DateTime startOfMonth = DateTime(now.year, now.month, 1);

    DateTime startOfYear = DateTime(now.year, 1, 1);

    for (var order in orders) {
      if (order.paymentStatus != 'sudah_bayar') continue;

      DateTime orderDate = order.createdAt;

      // Daily
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

  @override
  void dispose() {
    _servicesController.close();
    _ordersController.close();
    super.dispose();
  }
}
