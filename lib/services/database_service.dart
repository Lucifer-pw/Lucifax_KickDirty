import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/service_model.dart';
import '../models/order_model.dart';
import '../models/expense_model.dart';
import '../models/category_model.dart';
import '../models/voucher_model.dart';
import 'whatsapp_service.dart';

class DatabaseService with ChangeNotifier {
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  // Helper to trigger background automated WA notification
  void _triggerWA(String orderId, String eventType) {
    _db.collection('orders').doc(orderId).get().then((doc) {
      if (doc.exists) {
        final order = OrderModel.fromMap(doc.data() as Map<String, dynamic>, doc.id);
        WhatsAppService.sendAutomaticStatusNotification(order, eventType);
      }
    }).catchError((e) {
      if (kDebugMode) print("Error triggering automatic WA: $e");
    });
  }

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

    // Calculate points earned dynamically based on services total (excluding delivery fee)
    int rupiahPerPoint = 10000;
    try {
      final configDoc = await FirebaseFirestore.instance.collection('app_config').doc('business_config').get();
      if (configDoc.exists) {
        rupiahPerPoint = configDoc.data()?['rupiahPerPoint'] ?? 10000;
      }
    } catch (_) {}

    double servicesTotal = order.items.fold(0.0, (sum, item) => sum + item.price);
    int pointsEarned = (servicesTotal / rupiahPerPoint).floor();
    
    Map<String, DateTime> timeline = Map.from(order.statusTimeline);
    if (!timeline.containsKey(order.status)) {
      timeline[order.status] = DateTime.now();
    }
    if (order.paymentStatus == 'sudah_bayar' && !timeline.containsKey('sudah_bayar')) {
      timeline['sudah_bayar'] = DateTime.now();
    }

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
      estimatedCompletion: order.estimatedCompletion,
      mapsLink: order.mapsLink,
      voucherCode: order.voucherCode,
      voucherDiscount: order.voucherDiscount,
      statusTimeline: timeline,
      createdAt: order.createdAt,
      updatedAt: order.updatedAt,
    );

    // 3. Write document to Firestore using set (idempotent if invoiceId is used as document key)
    await _db.collection('orders').doc(invoiceId).set(finalOrder.toMap());

    // 4. Award points if paymentStatus is sudah_bayar, or handle point deduction
    if (finalOrder.paymentStatus == 'sudah_bayar' || finalOrder.pointsRedeemed > 0) {
      await _awardPoints(finalOrder);
    }

    // Trigger background automated WA notification
    WhatsAppService.sendAutomaticStatusNotification(finalOrder, 'diterima');

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
      'statusTimeline.$newStatus': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _triggerWA(orderId, newStatus);
  }

  // Update order status with after photo
  Future<void> updateOrderStatusWithPhoto(String orderId, String newStatus, List<String> afterPhotos) async {
    await _db.collection('orders').doc(orderId).update({
      'status': newStatus,
      'photoAfter': afterPhotos,
      'statusTimeline.$newStatus': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _triggerWA(orderId, newStatus);
  }

  // Update order status with estimated completion
  Future<void> updateOrderStatusWithEstimation(String orderId, String newStatus, String estimation) async {
    await _db.collection('orders').doc(orderId).update({
      'status': newStatus,
      'estimatedCompletion': estimation,
      'statusTimeline.$newStatus': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _triggerWA(orderId, newStatus);
  }

  // Update estimated completion only
  Future<void> updateOrderEstimation(String orderId, String estimation) async {
    await _db.collection('orders').doc(orderId).update({
      'estimatedCompletion': estimation,
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

    final updateData = {
      'paymentStatus': newPaymentStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (newPaymentStatus == 'sudah_bayar') {
      updateData['statusTimeline.sudah_bayar'] = FieldValue.serverTimestamp();
    }
    await _db.collection('orders').doc(orderId).update(updateData);

    if (newPaymentStatus == 'sudah_bayar') {
      _triggerWA(orderId, 'dibayar');
    }
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

  // ==========================================
  // REAL-TIME CHAT METHODS
  // ==========================================

  // Get stream of all active chat rooms (Admin view)
  Stream<List<Map<String, dynamic>>> getChatRooms() {
    return _db
        .collection('chat_rooms')
        .orderBy('lastMessageTime', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => doc.data()).toList();
    });
  }

  // Get stream of messages in a room
  Stream<List<Map<String, dynamic>>> getChatMessages(String customerId) {
    return _db
        .collection('chat_rooms')
        .doc(customerId)
        .collection('messages')
        .orderBy('timestamp', descending: false)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    });
  }

  // Send message
  Future<void> sendChatMessage({
    required String customerId,
    required String customerName,
    required String customerPhone,
    required String senderId,
    required String senderName,
    required String message,
    required bool isAdmin,
  }) async {
    final timestamp = FieldValue.serverTimestamp();

    // 1. Add message document
    await _db
        .collection('chat_rooms')
        .doc(customerId)
        .collection('messages')
        .add({
      'senderId': senderId,
      'senderName': senderName,
      'message': message,
      'timestamp': timestamp,
    });

    // 2. Set/Update room document with unread indicators
    final roomData = {
      'customerId': customerId,
      'customerName': customerName,
      'customerPhone': customerPhone,
      'lastMessage': message,
      'lastMessageTime': timestamp,
    };

    if (isAdmin) {
      roomData['unreadCountCustomer'] = FieldValue.increment(1);
    } else {
      roomData['unreadCountAdmin'] = FieldValue.increment(1);
    }

    await _db.collection('chat_rooms').doc(customerId).set(roomData, SetOptions(merge: true));

    if (!isAdmin) {
      _triggerAutoReply(customerId);
    }
  }

  // Trigger automated chat welcome response from the Owner
  void _triggerAutoReply(String customerId) {
    _db.collection('app_config').doc('chat_config').get().then((doc) {
      final bool enabled = doc.exists && (doc.data()?['autoReplyEnabled'] == true);
      if (enabled) {
        final autoReplyText = doc.data()?['autoReplyText'] ?? 'Halo! Terima kasih telah menghubungi KickDirty. Pesan Anda telah kami terima dan akan segera kami balas. Jam Operasional: 09:00 - 21:00.';
        
        // Prevent duplicate spamming by checking if we sent an auto-reply recently
        _db.collection('chat_rooms')
            .doc(customerId)
            .collection('messages')
            .orderBy('timestamp', descending: true)
            .limit(5)
            .get()
            .then((snap) {
          bool shouldSend = true;
          final now = DateTime.now();
          for (var d in snap.docs) {
            if (d.data()['senderId'] == 'owner_auto_reply') {
              final ts = d.data()['timestamp'] as Timestamp?;
              if (ts != null && now.difference(ts.toDate()).inMinutes < 5) {
                shouldSend = false;
                break;
              }
            }
          }
          if (shouldSend) {
            _db.collection('chat_rooms').doc(customerId).collection('messages').add({
              'senderId': 'owner_auto_reply',
              'senderName': 'KickDirty Bot',
              'message': autoReplyText,
              'timestamp': FieldValue.serverTimestamp(),
            });
            _db.collection('chat_rooms').doc(customerId).update({
              'lastMessage': autoReplyText,
              'lastMessageTime': FieldValue.serverTimestamp(),
              'unreadCountCustomer': FieldValue.increment(1),
            });
          }
        });
      }
    }).catchError((_) {});
  }

  // Reset unread count for admin/owner
  Future<void> clearUnreadCountAdmin(String customerId) async {
    try {
      await _db.collection('chat_rooms').doc(customerId).update({
        'unreadCountAdmin': 0,
      });
    } catch (_) {}
  }

  // Reset unread count for customer
  Future<void> clearUnreadCountCustomer(String customerId) async {
    try {
      await _db.collection('chat_rooms').doc(customerId).update({
        'unreadCountCustomer': 0,
      });
    } catch (_) {}
  }

  // ==========================================
  // DYNAMIC LOGISTICS METHODS CRUD
  // ==========================================

  // Get stream of all logistics methods
  Stream<List<Map<String, dynamic>>> getLogisticsMethods() {
    return _db.collection('logistics_methods').orderBy('createdAt', descending: false).snapshots().map((snapshot) {
      if (snapshot.docs.isEmpty) {
        // Auto-seed default methods to Firestore if empty
        _seedDefaultLogistics();
      }
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    });
  }

  // Seed default logistics helper
  void _seedDefaultLogistics() {
    final batch = _db.batch();
    
    final ref1 = _db.collection('logistics_methods').doc('drop_off_only');
    batch.set(ref1, {
      'name': 'Drop-Off & Ambil Sendiri',
      'fee': 0.0,
      'requiresAddress': false,
      'createdAt': FieldValue.serverTimestamp(),
    });

    final ref2 = _db.collection('logistics_methods').doc('pickup_delivery');
    batch.set(ref2, {
      'name': 'Penjemputan & Pengantaran (Kurir)',
      'fee': 15000.0,
      'requiresAddress': true,
      'createdAt': FieldValue.serverTimestamp(),
    });

    batch.commit().catchError((_) {});
  }

  // Add logistics method
  Future<void> addLogisticsMethod(String name, double fee, bool requiresAddress) async {
    await _db.collection('logistics_methods').add({
      'name': name,
      'fee': fee,
      'requiresAddress': requiresAddress,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // Update logistics method
  Future<void> updateLogisticsMethod(String id, String name, double fee, bool requiresAddress) async {
    await _db.collection('logistics_methods').doc(id).update({
      'name': name,
      'fee': fee,
      'requiresAddress': requiresAddress,
    });
  }

  // Delete logistics method
  Future<void> deleteLogisticsMethod(String id) async {
    await _db.collection('logistics_methods').doc(id).delete();
  }

  // ==========================================
  // CATEGORIES CRUD
  // ==========================================

  // Get stream of all categories
  Stream<List<CategoryModel>> getCategories() {
    return _db.collection('categories').orderBy('createdAt', descending: false).snapshots().map((snapshot) {
      if (snapshot.docs.isEmpty) {
        _seedDefaultCategory();
      }
      return snapshot.docs.map((doc) => CategoryModel.fromMap(doc.data(), doc.id)).toList();
    });
  }

  // Get stream of active categories only
  Stream<List<CategoryModel>> getActiveCategories() {
    return _db.collection('categories')
        .where('isActive', isEqualTo: true)
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => CategoryModel.fromMap(doc.data(), doc.id)).toList();
    });
  }

  // Seed default category helper
  void _seedDefaultCategory() {
    _db.collection('categories').add({
      'name': 'Sepatu',
      'description': 'Layanan cuci dan perawatan sepatu',
      'isActive': true,
      'createdAt': FieldValue.serverTimestamp(),
    }).catchError((_) {});
  }

  // Add category
  Future<void> addCategory(CategoryModel category) async {
    await _db.collection('categories').add(category.toMap());
  }

  // Update category
  Future<void> updateCategory(CategoryModel category) async {
    await _db.collection('categories').doc(category.id).update(category.toMap());
  }

  // Delete category (only if no services reference it)
  Future<bool> deleteCategory(String categoryId) async {
    final servicesCheck = await _db.collection('services').where('categoryId', isEqualTo: categoryId).limit(1).get();
    if (servicesCheck.docs.isNotEmpty) {
      return false; // Cannot delete - has associated services
    }
    await _db.collection('categories').doc(categoryId).delete();
    return true;
  }

  // Toggle category active status
  Future<void> toggleCategoryActive(String categoryId, bool isActive) async {
    await _db.collection('categories').doc(categoryId).update({'isActive': isActive});
  }

  // Get services filtered by category
  Stream<List<ServiceModel>> getServicesByCategory(String categoryId) {
    return _db.collection('services')
        .where('categoryId', isEqualTo: categoryId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => ServiceModel.fromMap(doc.data(), doc.id)).toList();
    });
  }

  // Get active services filtered by category
  Stream<List<ServiceModel>> getActiveServicesByCategory(String categoryId) {
    return _db.collection('services')
        .where('categoryId', isEqualTo: categoryId)
        .where('isActive', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => ServiceModel.fromMap(doc.data(), doc.id)).toList();
    });
  }

  // Toggle service active status
  Future<void> toggleServiceActive(String serviceId, bool isActive) async {
    await _db.collection('services').doc(serviceId).update({'isActive': isActive});
  }

  // ==========================================
  // VOUCHERS CRUD
  // ==========================================

  // Get stream of all vouchers
  Stream<List<VoucherModel>> getVouchers() {
    return _db.collection('vouchers').orderBy('createdAt', descending: true).snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => VoucherModel.fromMap(doc.data(), doc.id)).toList();
    });
  }

  // Get active vouchers (for customer view)
  Stream<List<VoucherModel>> getActiveVouchers() {
    return _db.collection('vouchers')
        .where('isActive', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      final now = DateTime.now();
      return snapshot.docs
          .map((doc) => VoucherModel.fromMap(doc.data(), doc.id))
          .where((v) {
            if (v.validFrom != null && now.isBefore(v.validFrom!)) return false;
            if (v.validTo != null && now.isAfter(v.validTo!)) return false;
            return true;
          })
          .toList();
    });
  }

  // Add voucher
  Future<void> addVoucher(VoucherModel voucher) async {
    await _db.collection('vouchers').add(voucher.toMap());
  }

  // Update voucher
  Future<void> updateVoucher(VoucherModel voucher) async {
    await _db.collection('vouchers').doc(voucher.id).update(voucher.toMap());
  }

  // Delete voucher
  Future<void> deleteVoucher(String voucherId) async {
    await _db.collection('vouchers').doc(voucherId).delete();
  }

  // Toggle voucher active status
  Future<void> toggleVoucherActive(String voucherId, bool isActive) async {
    await _db.collection('vouchers').doc(voucherId).update({'isActive': isActive});
  }

  // Validate a voucher code and return the voucher if valid
  Future<VoucherModel?> validateVoucher(String code, double orderTotal) async {
    final snapshot = await _db.collection('vouchers')
        .where('code', isEqualTo: code.toUpperCase().trim())
        .where('isActive', isEqualTo: true)
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) return null;

    final voucher = VoucherModel.fromMap(snapshot.docs.first.data(), snapshot.docs.first.id);
    final now = DateTime.now();

    if (voucher.validFrom != null && now.isBefore(voucher.validFrom!)) return null;
    if (voucher.validTo != null && now.isAfter(voucher.validTo!)) return null;
    if (orderTotal < voucher.minOrder) return null;

    return voucher;
  }
}
