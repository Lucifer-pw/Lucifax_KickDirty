import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/order_model.dart';
import '../../models/service_model.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/database_service.dart';
import '../../theme.dart';
import '../../widgets/watermark.dart';
import '../login_screen.dart';

class CustomerPortalScreen extends StatefulWidget {
  const CustomerPortalScreen({Key? key}) : super(key: key);

  @override
  State<CustomerPortalScreen> createState() => _CustomerPortalScreenState();
}

class _CustomerPortalScreenState extends State<CustomerPortalScreen> {
  void _showOrderServiceDialog() async {
    final dbService = Provider.of<DatabaseService>(context, listen: false);
    final authService = Provider.of<AuthService>(context, listen: false);
    final currentUser = authService.currentUserModel;

    if (currentUser == null) return;

    // Show loading dialog while fetching services list once
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    List<ServiceModel> services = [];
    int livePoints = 0;
    try {
      services = await dbService.getServices().first;
      final userSnap = await FirebaseFirestore.instance.collection('users').doc(currentUser.uid).get();
      if (userSnap.exists) {
        livePoints = (userSnap.data()?['loyaltyPoints'] as int?) ?? 0;
      }
    } catch (e) {
      print("Error fetching setup: $e");
    }

    if (mounted) {
      Navigator.pop(context); // Close loading dialog
    }

    if (services.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Layanan tidak tersedia. Silakan hubungi admin.')),
        );
      }
      return;
    }

    final nameController = TextEditingController();
    final notesController = TextEditingController();
    final addressController = TextEditingController();
    ServiceModel? selectedService = services.first;
    String deliveryType = 'drop_off_only';
    bool usePointsRedemption = false;
    final formKey = GlobalKey<FormState>();
    bool isSubmitting = false;

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateSheet) {
            double servicePrice = selectedService?.price ?? 0.0;
            double deliveryFee = deliveryType == 'pickup_delivery' ? 15000.0 : 0.0;
            double discount = usePointsRedemption ? 25000.0 : 0.0;
            double totalPrice = servicePrice + deliveryFee - discount;
            if (totalPrice < 0) totalPrice = 0.0;

            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                top: 24,
                left: 24,
                right: 24,
              ),
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: AppTheme.lightGray,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Pesan Layanan Cuci Sepatu',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryBlue,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Silakan masukkan detail sepatu Anda dan pilih jenis layanan.',
                        style: TextStyle(fontSize: 12, color: AppTheme.textGray),
                      ),
                      const SizedBox(height: 20),

                      // Item Name input
                      TextFormField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'Nama / Merek Sepatu',
                          hintText: 'Contoh: Adidas Samba, Nike Jordan',
                          prefixIcon: Icon(Icons.abc),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Nama/merek sepatu tidak boleh kosong';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Service selection dropdown
                      DropdownButtonFormField<ServiceModel>(
                        value: selectedService,
                        decoration: const InputDecoration(
                          labelText: 'Pilih Layanan',
                          prefixIcon: Icon(Icons.dry_cleaning),
                        ),
                        items: services.map((service) {
                          return DropdownMenuItem<ServiceModel>(
                            value: service,
                            child: Text(
                              '${service.name} - Rp ${service.price.toStringAsFixed(0).replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (Match m) => "${m[1]}.")}',
                              style: const TextStyle(fontSize: 14),
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          setStateSheet(() {
                            selectedService = val;
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      if (selectedService != null) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text(
                            selectedService!.description,
                            style: const TextStyle(fontSize: 11, color: AppTheme.textGray, fontStyle: FontStyle.italic),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Delivery Logistics Type selection
                      DropdownButtonFormField<String>(
                        value: deliveryType,
                        decoration: const InputDecoration(
                          labelText: 'Tipe Pengiriman / Penjemputan',
                          prefixIcon: Icon(Icons.local_shipping),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'drop_off_only', child: Text('Drop-Off & Ambil Sendiri')),
                          DropdownMenuItem(value: 'pickup_delivery', child: Text('Penjemputan & Pengantaran (Kurir)')),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setStateSheet(() {
                              deliveryType = val;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 16),

                      // Address input if pickup_delivery selected
                      if (deliveryType == 'pickup_delivery') ...[
                        TextFormField(
                          controller: addressController,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: 'Alamat Penjemputan & Pengantaran',
                            hintText: 'Masukkan alamat lengkap Anda...',
                            prefixIcon: Icon(Icons.location_on),
                          ),
                          validator: (value) {
                            if (deliveryType == 'pickup_delivery' && (value == null || value.trim().isEmpty)) {
                              return 'Alamat wajib diisi untuk penjemputan/pengantaran';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 8),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4),
                          child: Text(
                            'Biaya Kurir Flat: Rp 15.000',
                            style: TextStyle(fontSize: 12, color: AppTheme.primaryBlue, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Loyalty Points redemption
                      if (livePoints >= 10) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.amber.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.amber.withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.stars, color: Colors.amber),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Anda memiliki $livePoints Poin!\nTukarkan 10 Poin (Diskon Rp 25.000)',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.brown),
                                ),
                              ),
                              Switch(
                                value: usePointsRedemption,
                                activeColor: Colors.amber,
                                onChanged: (val) {
                                  setStateSheet(() {
                                    usePointsRedemption = val;
                                  });
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Notes input
                      TextFormField(
                        controller: notesController,
                        decoration: const InputDecoration(
                          labelText: 'Catatan (Opsional)',
                          hintText: 'Contoh: Kotor sekali di bagian sol, tali dilepas',
                          prefixIcon: Icon(Icons.edit_note),
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 16),

                      // Order Summary Pricing
                      if (selectedService != null) ...[
                        const Divider(),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Harga Layanan:', style: TextStyle(fontSize: 13, color: AppTheme.textGray)),
                            Text('Rp ${servicePrice.toStringAsFixed(0).replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (Match m) => "${m[1]}.")}', style: const TextStyle(fontSize: 13)),
                          ],
                        ),
                        if (deliveryType == 'pickup_delivery') ...[
                          const SizedBox(height: 4),
                          const Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Ongkos Kirim:', style: TextStyle(fontSize: 13, color: AppTheme.textGray)),
                              Text('Rp 15.000', style: TextStyle(fontSize: 13)),
                            ],
                          ),
                        ],
                        if (usePointsRedemption) ...[
                          const SizedBox(height: 4),
                          const Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Diskon Poin:', style: TextStyle(fontSize: 13, color: Colors.green)),
                              Text('-Rp 25.000', style: TextStyle(fontSize: 13, color: Colors.green, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ],
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Total Pembayaran:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                            Text(
                              'Rp ${totalPrice.toStringAsFixed(0).replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (Match m) => "${m[1]}.")}',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue),
                            ),
                          ],
                        ),
                        const Divider(),
                        const SizedBox(height: 20),
                      ],

                      // Submit button
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: isSubmitting
                              ? null
                              : () async {
                                  if (!formKey.currentState!.validate() || selectedService == null) return;

                                  setStateSheet(() {
                                    isSubmitting = true;
                                  });

                                  try {
                                    // Generate a deterministic unique ID
                                    String invoiceId = await dbService.generateInvoiceId();

                                    OrderModel order = OrderModel(
                                      id: invoiceId,
                                      idempotencyToken: DateTime.now().millisecondsSinceEpoch.toString(),
                                      customerName: currentUser.name,
                                      customerPhone: currentUser.phoneNumber,
                                      customerId: currentUser.uid,
                                      items: [
                                        OrderItem(
                                          itemName: nameController.text.trim(),
                                          serviceId: selectedService!.id,
                                          serviceName: selectedService!.name,
                                          price: selectedService!.price,
                                        )
                                      ],
                                      totalAmount: totalPrice,
                                      status: 'diterima',
                                      paymentStatus: 'belum_bayar',
                                      qrisImage: 'assets/qris_pembayaran.jpeg',
                                      notes: notesController.text.trim(),
                                      deliveryType: deliveryType,
                                      deliveryAddress: deliveryType == 'pickup_delivery' ? addressController.text.trim() : '',
                                      deliveryFee: deliveryFee,
                                      photoBefore: const [],
                                      photoAfter: const [],
                                      pointsEarned: (totalPrice / 10000).floor(),
                                      pointsRedeemed: usePointsRedemption ? 10 : 0,
                                      createdAt: DateTime.now(),
                                      updatedAt: DateTime.now(),
                                    );

                                    // Save the order to Firestore
                                    await dbService.addOrder(order);

                                    // Save/update customer database record
                                    try {
                                      await FirebaseFirestore.instance
                                          .collection('customers')
                                          .doc(currentUser.phoneNumber)
                                          .set({
                                        'name': currentUser.name,
                                        'phone': currentUser.phoneNumber,
                                        'lastOrderAt': FieldValue.serverTimestamp(),
                                      }, SetOptions(merge: true));
                                    } catch (_) {}

                                    if (context.mounted) {
                                      Navigator.pop(context); // Close bottom sheet
                                      _showCustomerQrisDialog(invoiceId, order);
                                    }
                                  } catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Gagal membuat pesanan: $e')),
                                      );
                                    }
                                  } finally {
                                    setStateSheet(() {
                                      isSubmitting = false;
                                    });
                                  }
                                },
                          child: isSubmitting
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                )
                              : const Text('Buat Pesanan Sekarang'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showCustomerQrisDialog(String invoiceId, OrderModel order) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Pembayaran QRIS (Cashless)', textAlign: TextAlign.center),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Invoice: $invoiceId', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                'Total: Rp ${order.totalAmount.toStringAsFixed(0).replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (Match m) => "${m[1]}.")}',
                style: const TextStyle(fontSize: 16, color: AppTheme.primaryBlue, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              // QRIS Image
              Image.asset(
                'assets/qris_pembayaran.jpeg',
                height: 250,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => Container(
                  height: 150,
                  color: AppTheme.lightGray,
                  child: const Center(child: Icon(Icons.qr_code, size: 80, color: AppTheme.textGray)),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Silakan scan QRIS di atas untuk melakukan transfer pembayaran cashless.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppTheme.textGray),
              ),
              const SizedBox(height: 8),
              const Text(
                'Setelah membayar, silakan kirim bukti transfer ke WhatsApp toko.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppTheme.textGray, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          actions: [
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                // Open WhatsApp with confirmation template
                final message =
                    "Halo KickDirty, saya ingin mengirimkan bukti pembayaran untuk pesanan saya:\n\n"
                    "- Invoice: $invoiceId\n"
                    "- Layanan: ${order.items.map((item) => "${item.itemName} (${item.serviceName})").join(', ')}\n"
                    "- Total: Rp ${order.totalAmount.toStringAsFixed(0).replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (Match m) => "${m[1]}.")}\n\n"
                    "Berikut saya lampirkan bukti transfer pembayarannya.";
                
                const cleanPhone = "6281328580511";
                final uri = Uri.parse('https://wa.me/$cleanPhone?text=${Uri.encodeComponent(message)}');
                
                try {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                } catch (_) {
                  try {
                    await launchUrl(uri, mode: LaunchMode.platformDefault);
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Tidak dapat membuka WhatsApp: $e')),
                      );
                    }
                  }
                }
              },
              icon: const Icon(Icons.phone),
              label: const Text('Kirim Bukti Pembayaran'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context); // Close dialog
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Pesanan $invoiceId berhasil dibuat! Silakan pantau status pengerjaan Anda.')),
                );
              },
              child: const Text('Tutup', style: TextStyle(color: AppTheme.textGray)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final dbService = Provider.of<DatabaseService>(context);

    final currentUser = authService.currentUserModel;
    final String phoneNumber = currentUser?.phoneNumber ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('KickDirty Pelanggan'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_outlined, color: Colors.redAccent),
            onPressed: () async {
              await authService.signOut();
              if (mounted) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                );
              }
            },
          ),
        ],
      ),
      body: currentUser == null
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<List<OrderModel>>(
              // Query orders matching customer's WhatsApp number for seamless synchronization
              stream: dbService.getOrdersByPhone(phoneNumber),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Terjadi kesalahan: ${snapshot.error}'));
                }

                final allOrders = snapshot.data ?? [];

                // Filter Active vs Completed (Picked Up) orders
                final activeOrders = allOrders.where((o) => o.status != 'diambil').toList();
                final historyOrders = allOrders.where((o) => o.status == 'diambil').toList();

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Profile Card
                      _buildProfileCard(currentUser),
                      const SizedBox(height: 24),

                      // Active Orders (Real-time tracking)
                      Text('Lacak Cucian Sepatu (Real-Time)', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 12),
                      if (activeOrders.isEmpty)
                        _buildEmptyState('Tidak ada sepatu yang sedang dicuci saat ini.')
                      else
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: activeOrders.length,
                          itemBuilder: (context, index) {
                            return _buildActiveOrderCard(activeOrders[index]);
                          },
                        ),
                      const SizedBox(height: 24),

                      // History Orders
                      Text('Riwayat Cucian Selesai', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 12),
                      if (historyOrders.isEmpty)
                        _buildEmptyState('Belum ada riwayat pesanan selesai.')
                      else
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: historyOrders.length,
                          itemBuilder: (context, index) {
                            return _buildHistoryOrderCard(historyOrders[index]);
                          },
                        ),
                      const SizedBox(height: 32),
                      const Center(child: Watermark()),
                    ],
                  ),
                );
              },
            ),
      floatingActionButton: currentUser == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _showOrderServiceDialog,
              icon: const Icon(Icons.add_shopping_cart_outlined),
              label: const Text('Pesan Layanan'),
              backgroundColor: AppTheme.primaryBlue,
            ),
    );
  }

  Widget _buildProfileCard(UserModel initialUser) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(initialUser.uid).snapshots(),
      builder: (context, snapshot) {
        UserModel user = initialUser;
        if (snapshot.hasData && snapshot.data!.exists) {
          user = UserModel.fromMap(snapshot.data!.data() as Map<String, dynamic>, snapshot.data!.id);
        }
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.lightGray),
            boxShadow: AppTheme.cardShadow,
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue.withOpacity(0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.person, color: AppTheme.primaryBlue, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text(user.email, style: const TextStyle(color: AppTheme.textGray, fontSize: 12)),
                    if (user.phoneNumber.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text('WA: +${user.phoneNumber}', style: const TextStyle(color: AppTheme.textGray, fontSize: 12)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.orange.shade400, Colors.amber.shade600],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.amber.shade600.withOpacity(0.3),
                      blurRadius: 6,
                      offset: const Offset(0, 3),
                    )
                  ],
                ),
                child: Column(
                  children: [
                    const Icon(Icons.stars, color: Colors.white, size: 20),
                    const SizedBox(height: 2),
                    Text(
                      '${user.loyaltyPoints} Poin',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }
    );
  }

  Widget _buildEmptyState(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: AppTheme.lightBlueBackground.withOpacity(0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.lightGray),
      ),
      child: Column(
        children: [
          const Icon(Icons.info_outline, color: AppTheme.textGray, size: 32),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.textGray, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveOrderCard(OrderModel order) {
    String day = order.createdAt.day.toString().padLeft(2, '0');
    String month = order.createdAt.month.toString().padLeft(2, '0');
    String year = order.createdAt.year.toString();
    String formattedDate = "$day-$month-$year";

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  order.id,
                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryBlue, fontSize: 15),
                ),
                Text(formattedDate, style: const TextStyle(color: AppTheme.textGray, fontSize: 11)),
              ],
            ),
            const Divider(height: 20, color: AppTheme.lightGray),

            // Item Details
            ...order.items.map((item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(item.itemName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      Text(item.serviceName, style: const TextStyle(color: AppTheme.textGray, fontSize: 12)),
                    ],
                  ),
                )),
            
            // Delivery/Logistic Details
            if (order.deliveryType == 'pickup_delivery') ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.local_shipping_outlined, size: 16, color: AppTheme.primaryBlue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Pengantaran: Kurir • Ongkir: Rp ${order.deliveryFee.toStringAsFixed(0).replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (Match m) => "${m[1]}.")}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 24, top: 2),
                child: Text(
                  'Alamat: ${order.deliveryAddress}',
                  style: const TextStyle(fontSize: 11, color: AppTheme.textGray),
                ),
              ),
            ] else ...[
              const SizedBox(height: 8),
              const Row(
                children: [
                  Icon(Icons.storefront_outlined, size: 16, color: AppTheme.textGray),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Tipe: Drop-Off & Ambil Sendiri di Toko',
                      style: TextStyle(fontSize: 11, color: AppTheme.textGray),
                    ),
                  ),
                ],
              ),
            ],

            const Divider(height: 20, color: AppTheme.lightGray),

            // Photos Before-After Viewer
            if (order.photoBefore.isNotEmpty || order.photoAfter.isNotEmpty) ...[
              const Text(
                'Dokumentasi Foto Cucian',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.darkBlueText),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (order.photoBefore.isNotEmpty)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 6.0),
                        child: _buildBase64Image(order.photoBefore.first, 'Kondisi Awal (Before)'),
                      ),
                    ),
                  if (order.photoAfter.isNotEmpty)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 6.0),
                        child: _buildBase64Image(order.photoAfter.first, 'Hasil Cuci (After)'),
                      ),
                    )
                  else if (order.photoBefore.isNotEmpty)
                    const Expanded(
                      child: SizedBox(),
                    ),
                ],
              ),
              const Divider(height: 20, color: AppTheme.lightGray),
            ],

            // Payment and Total Info
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Total Biaya', style: TextStyle(color: AppTheme.textGray, fontSize: 10)),
                    Text(
                      'Rp ${order.totalAmount.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.')}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.darkBlueText),
                    ),
                  ],
                ),
                // Payment Status Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: order.paymentStatus == 'sudah_bayar'
                        ? Colors.green.withOpacity(0.12)
                        : Colors.red.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    order.paymentStatus == 'sudah_bayar' ? 'LUNAS' : 'BELUM BAYAR',
                    style: TextStyle(
                      color: order.paymentStatus == 'sudah_bayar' ? Colors.green : Colors.red,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ),
            if (order.paymentStatus == 'belum_bayar') ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _showCustomerQrisDialog(order.id, order),
                  icon: const Icon(Icons.qr_code_scanner, size: 16),
                  label: const Text('Bayar Sekarang (QRIS)', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primaryBlue,
                    side: const BorderSide(color: AppTheme.primaryBlue),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),

            // Progress Stepper Tracker
            _buildProgressStepper(order.status),
          ],
        ),
      ),
    );
  }

  Widget _buildBase64Image(String base64Str, String label, {double height = 110}) {
    try {
      String cleanBase64 = base64Str;
      if (base64Str.contains(',')) {
        cleanBase64 = base64Str.split(',')[1];
      }
      final bytes = base64Decode(cleanBase64);
      return GestureDetector(
        onTap: () => _showFullScreenImage(base64Str, label),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: height,
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border.all(color: AppTheme.lightGray),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.memory(
                  bytes,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => const Center(
                    child: Icon(Icons.broken_image, color: Colors.grey),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.black.withOpacity(0.6), Colors.transparent],
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Text(
                      label,
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      return Container(
        height: height,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.broken_image, color: Colors.grey),
      );
    }
  }

  void _showFullScreenImage(String base64Str, String title) {
    try {
      String cleanBase64 = base64Str;
      if (base64Str.contains(',')) {
        cleanBase64 = base64Str.split(',')[1];
      }
      final bytes = base64Decode(cleanBase64);
      showDialog(
        context: context,
        builder: (context) => Dialog(
          backgroundColor: Colors.black.withOpacity(0.9),
          insetPadding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                title: Text(title, style: const TextStyle(color: Colors.white)),
                leading: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: InteractiveViewer(
                    child: Image.memory(
                      bytes,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    } catch (_) {}
  }

  Widget _buildProgressStepper(String currentStatus) {
    int currentStep = 0;
    if (currentStatus == 'diterima') currentStep = 0;
    if (currentStatus == 'sedang_diproses') currentStep = 1;
    if (currentStatus == 'selesai') currentStep = 2;

    return Row(
      children: [
        _buildStep(0, 'Diterima', currentStep >= 0),
        _buildLine(currentStep >= 1),
        _buildStep(1, 'Diproses', currentStep >= 1),
        _buildLine(currentStep >= 2),
        _buildStep(2, 'Selesai', currentStep >= 2),
      ],
    );
  }

  Widget _buildStep(int stepIndex, String title, bool isCompleted) {
    return Expanded(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: isCompleted ? AppTheme.primaryBlue : AppTheme.lightGray,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isCompleted ? Icons.check : Icons.circle,
              color: Colors.white,
              size: 14,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 10,
              fontWeight: isCompleted ? FontWeight.bold : FontWeight.normal,
              color: isCompleted ? AppTheme.primaryBlue : AppTheme.textGray,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLine(bool isCompleted) {
    return Container(
      height: 2,
      width: 30,
      color: isCompleted ? AppTheme.primaryBlue : AppTheme.lightGray,
    );
  }

  Widget _buildHistoryOrderCard(OrderModel order) {
    String day = order.createdAt.day.toString().padLeft(2, '0');
    String month = order.createdAt.month.toString().padLeft(2, '0');
    String year = order.createdAt.year.toString();
    String formattedDate = "$day-$month-$year";

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: ListTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.done_all, color: Colors.green),
          ),
          title: Text(order.id, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                order.items.map((item) => item.itemName).join(', '),
                style: const TextStyle(fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(formattedDate, style: const TextStyle(fontSize: 10, color: AppTheme.textGray)),
            ],
          ),
          trailing: Text(
            'Rp ${order.totalAmount.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.')}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}
