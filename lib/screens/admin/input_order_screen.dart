import 'dart:math';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../models/order_model.dart';
import '../../models/service_model.dart';
import '../../models/category_model.dart';
import '../../models/voucher_model.dart';
import '../../services/database_service.dart';
import '../../services/image_service.dart';
import '../../theme.dart';

class InputOrderScreen extends StatefulWidget {
  final bool isTab;
  final VoidCallback? onOrderSubmitted;
  const InputOrderScreen({Key? key, this.isTab = false, this.onOrderSubmitted}) : super(key: key);

  @override
  State<InputOrderScreen> createState() => _InputOrderScreenState();
}

class _InputOrderScreenState extends State<InputOrderScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _notesController = TextEditingController();

  // Temporary list of items being ordered
  final List<OrderItem> _items = [];

  // Controllers for adding an item
  final _itemNameController = TextEditingController();
  ServiceModel? _selectedService;
  List<ServiceModel> _availableServices = [];
  CategoryModel? _selectedCategory;
  List<CategoryModel> _availableCategories = [];
  VoucherModel? _appliedVoucher;
  final _voucherController = TextEditingController();

  // New features state
  String _selectedCustomerId = '';
  int _selectedCustomerPoints = 0;
  bool _usePointsRedemption = false;

  String _deliveryType = 'drop_off_only';
  final _deliveryAddressController = TextEditingController();
  final _deliveryFeeController = TextEditingController(text: '0');

  List<String> _photoBeforeList = [];

  // Idempotency token generated once when screen is initialized
  late String _idempotencyToken;
  bool _isSubmitting = false;

  late Stream<List<CategoryModel>> _categoriesStream;
  late Stream<List<ServiceModel>> _servicesStream;
  late Stream<List<Map<String, dynamic>>> _logisticsStream;
  late Stream<List<VoucherModel>> _vouchersStream;

  @override
  void initState() {
    super.initState();
    final dbService = Provider.of<DatabaseService>(context, listen: false);
    _categoriesStream = dbService.getActiveCategories();
    _servicesStream = dbService.getServices();
    _logisticsStream = dbService.getLogisticsMethods();
    _vouchersStream = dbService.getActiveVouchers();
    _generateIdempotencyToken();
  }

  void _generateIdempotencyToken() {
    final random = Random();
    _idempotencyToken = "KD-TX-${DateTime.now().microsecondsSinceEpoch}-${random.nextInt(999999)}";
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _notesController.dispose();
    _itemNameController.dispose();
    _deliveryAddressController.dispose();
    _deliveryFeeController.dispose();
    _voucherController.dispose();
    super.dispose();
  }

  void _addItem() {
    if (_itemNameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nama Merk Sepatu wajib diisi')),
      );
      return;
    }
    if (_selectedService == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih jenis layanan terlebih dahulu')),
      );
      return;
    }

    setState(() {
      _items.add(
        OrderItem(
          itemName: _itemNameController.text,
          serviceId: _selectedService!.id,
          serviceName: _selectedService!.name,
          categoryId: _selectedCategory?.id ?? '',
          categoryName: _selectedCategory?.name ?? '',
          price: _selectedService!.price,
        ),
      );
      _itemNameController.clear();
      _selectedService = null;
      _selectedCategory = null;
    });
  }

  void _removeItem(int index) {
    setState(() {
      _items.removeAt(index);
    });
  }

  void _resetForm() {
    _nameController.clear();
    _phoneController.clear();
    _notesController.clear();
    _itemNameController.clear();
    _deliveryAddressController.clear();
    _deliveryFeeController.text = '0';
    _voucherController.clear();
    setState(() {
      _items.clear();
      _selectedService = null;
      _selectedCategory = null;
      _selectedCustomerId = '';
      _selectedCustomerPoints = 0;
      _usePointsRedemption = false;
      _deliveryType = 'drop_off_only';
      _photoBeforeList = [];
      _appliedVoucher = null;
      _generateIdempotencyToken();
    });
  }

  double get _itemsPrice => _items.fold(0, (sum, item) => sum + item.price);
  
  double get _deliveryFee => double.tryParse(_deliveryFeeController.text) ?? 0.0;

  double get _voucherDiscount {
    if (_appliedVoucher == null) return 0.0;
    return _appliedVoucher!.calculateDiscount(_itemsPrice);
  }

  double get _totalPrice {
    double total = _itemsPrice + _deliveryFee - _voucherDiscount;
    if (_usePointsRedemption && _selectedCustomerPoints >= 10) {
      total -= 25000;
    }
    return total < 0 ? 0.0 : total;
  }

  void _showQrisDialog(String invoiceId, OrderModel order) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Pembayaran QRIS', textAlign: TextAlign.center),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Invoice: $invoiceId', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                'Total: Rp ${_totalPrice.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.')}',
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
                'Tunjukkan QRIS ini kepada pelanggan untuk discan & bayar.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppTheme.textGray),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                // Update paymentStatus to sudah_bayar
                await Provider.of<DatabaseService>(context, listen: false)
                    .updateOrderPaymentStatus(invoiceId, 'sudah_bayar');
                if (mounted) {
                  Navigator.pop(context); // Close dialog
                  _resetForm(); // Reset form state
                  if (widget.onOrderSubmitted != null) {
                    widget.onOrderSubmitted!();
                  } else {
                    Navigator.pop(context); // Go back to admin panel
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Pesanan $invoiceId berhasil dibuat & dibayar!')),
                  );
                }
              },
              child: const Text('Sudah Bayar / Lunas', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context); // Close dialog
                _resetForm(); // Reset form state
                if (widget.onOrderSubmitted != null) {
                  widget.onOrderSubmitted!();
                } else {
                  Navigator.pop(context); // Go back to admin panel
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Pesanan $invoiceId disimpan (Belum Bayar)')),
                );
              },
              child: const Text('Bayar Nanti (Belum Bayar)', style: TextStyle(color: AppTheme.textGray)),
            ),
          ],
        );
      },
    );
  }

  Future<List<Map<String, String>>> _fetchAllCustomers() async {
    Map<String, Map<String, String>> merged = {};

    // 1. Fetch from 'users'
    try {
      final usersSnap = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'customer')
          .get();
      for (var doc in usersSnap.docs) {
        final data = doc.data();
        final phone = data['phoneNumber']?.toString().trim() ?? '';
        final name = data['name']?.toString().trim() ?? '';
        final points = (data['loyaltyPoints'] ?? 0).toString();
        if (phone.isNotEmpty) {
          merged[phone] = {
            'name': name,
            'phone': phone,
            'customerId': doc.id,
            'loyaltyPoints': points,
          };
        }
      }
    } catch (e) {
      if (kDebugMode) print("Error fetching users: $e");
    }

    // 2. Fetch from 'customers'
    try {
      final customersSnap = await FirebaseFirestore.instance
          .collection('customers')
          .get();
      for (var doc in customersSnap.docs) {
        final data = doc.data();
        final phone = data['phone']?.toString().trim() ?? '';
        final name = data['name']?.toString().trim() ?? '';
        final points = (data['loyaltyPoints'] ?? 0).toString();
        final uid = data['uid']?.toString() ?? '';
        if (phone.isNotEmpty) {
          if (merged.containsKey(phone)) {
            final existing = merged[phone]!;
            if ((existing['customerId'] == null || existing['customerId']!.isEmpty) && uid.isNotEmpty) {
              existing['customerId'] = uid;
            }
            int existingPts = int.tryParse(existing['loyaltyPoints'] ?? '0') ?? 0;
            int newPts = int.tryParse(points) ?? 0;
            if (newPts > existingPts) {
              existing['loyaltyPoints'] = points;
            }
          } else {
            merged[phone] = {
              'name': name,
              'phone': phone,
              'customerId': uid,
              'loyaltyPoints': points,
            };
          }
        }
      }
    } catch (e) {
      if (kDebugMode) print("Error fetching customers: $e");
    }

    // 3. Fetch from 'orders'
    try {
      final ordersSnap = await FirebaseFirestore.instance
          .collection('orders')
          .orderBy('createdAt', descending: true)
          .limit(200)
          .get();
      for (var doc in ordersSnap.docs) {
        final data = doc.data();
        final phone = data['customerPhone']?.toString().trim() ?? '';
        final name = data['customerName']?.toString().trim() ?? '';
        final custId = data['customerId']?.toString() ?? '';
        if (phone.isNotEmpty && name.isNotEmpty) {
          if (merged.containsKey(phone)) {
            final existing = merged[phone]!;
            if ((existing['customerId'] == null || existing['customerId']!.isEmpty) && custId.isNotEmpty) {
              existing['customerId'] = custId;
            }
          } else {
            merged[phone] = {
              'name': name,
              'phone': phone,
              'customerId': custId,
              'loyaltyPoints': '0',
            };
          }
        }
      }
    } catch (e) {
      if (kDebugMode) print("Error fetching orders: $e");
    }

    return merged.values.toList();
  }

  Future<void> _showEditCustomerDialog(BuildContext context, String currentName, String currentPhone, String customerId, int currentPoints, VoidCallback onUpdated) async {
    final nameController = TextEditingController(text: currentName);
    final phoneController = TextEditingController(text: currentPhone);
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit Informasi Pelanggan'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Nama Pelanggan'),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Nama wajib diisi' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: phoneController,
                  decoration: const InputDecoration(labelText: 'Nomor WhatsApp'),
                  keyboardType: TextInputType.phone,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Nomor WA wajib diisi';
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                final newName = nameController.text.trim();
                final newPhone = phoneController.text.trim();

                try {
                  // If phone number changed, we need to delete the old document and create a new one
                  if (newPhone != currentPhone) {
                    await FirebaseFirestore.instance.collection('customers').doc(currentPhone).delete();
                  }

                  // Set new/updated doc
                  await FirebaseFirestore.instance.collection('customers').doc(newPhone).set({
                    'name': newName,
                    'phone': newPhone,
                    'loyaltyPoints': currentPoints,
                    if (customerId.isNotEmpty) 'uid': customerId,
                    'updatedAt': FieldValue.serverTimestamp(),
                  });

                  // If user account exists, we can also update their name in 'users' collection
                  if (customerId.isNotEmpty) {
                    await FirebaseFirestore.instance.collection('users').doc(customerId).update({
                      'name': newName,
                      'phoneNumber': newPhone,
                    });
                  }

                  Navigator.pop(context); // Close edit dialog
                  onUpdated();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Informasi pelanggan berhasil diperbarui')),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Gagal memperbarui: $e')),
                  );
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryBlue),
              child: const Text('Simpan'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showDeleteCustomerDialog(BuildContext context, String name, String phone, VoidCallback onDeleted) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Hapus Pelanggan'),
          content: Text('Apakah Anda yakin ingin menghapus pelanggan "$name" (+$phone) dari daftar?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Hapus'),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      try {
        await FirebaseFirestore.instance.collection('customers').doc(phone).delete();
        onDeleted();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pelanggan berhasil dihapus')),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menghapus: $e')),
        );
      }
    }
  }

  Future<void> _showCustomerSearchDialog() async {
    Future<List<Map<String, String>>> customersFuture = _fetchAllCustomers();
    showDialog(
      context: context,
      builder: (context) {
        String searchQuery = "";
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Cari Pelanggan Terdaftar'),
              content: SizedBox(
                width: double.maxFinite,
                height: 350,
                child: Column(
                  children: [
                    TextField(
                      decoration: const InputDecoration(
                        hintText: 'Cari nama atau nomor WA...',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (val) {
                        setStateDialog(() {
                          searchQuery = val.toLowerCase();
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: FutureBuilder<List<Map<String, String>>>(
                        future: customersFuture,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
                            return const Center(child: Text('Belum ada pelanggan terdaftar.'));
                          }

                          final docs = snapshot.data!.where((item) {
                            final name = item['name']?.toLowerCase() ?? '';
                            final phone = item['phone'] ?? '';
                            return name.contains(searchQuery) || phone.contains(searchQuery);
                          }).toList();

                          if (docs.isEmpty) {
                            return const Center(child: Text('Pelanggan tidak ditemukan.'));
                          }

                          return ListView.separated(
                            itemCount: docs.length,
                            separatorBuilder: (_, __) => const Divider(),
                            itemBuilder: (context, index) {
                              final item = docs[index];
                              final name = item['name'] ?? '';
                              final phone = item['phone'] ?? '';
                              final points = int.tryParse(item['loyaltyPoints'] ?? '0') ?? 0;
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: AppTheme.primaryBlue.withOpacity(0.08),
                                  child: const Icon(Icons.person, color: AppTheme.primaryBlue),
                                ),
                                title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text('WA: +$phone • Poin: $points'),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit, color: Colors.blue, size: 20),
                                      onPressed: () async {
                                        await _showEditCustomerDialog(context, name, phone, item['customerId'] ?? '', points, () {
                                          setStateDialog(() {
                                            customersFuture = _fetchAllCustomers();
                                          });
                                        });
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                                      onPressed: () async {
                                        await _showDeleteCustomerDialog(context, name, phone, () {
                                          setStateDialog(() {
                                            customersFuture = _fetchAllCustomers();
                                          });
                                        });
                                      },
                                    ),
                                  ],
                                ),
                                onTap: () {
                                  setState(() {
                                    _nameController.text = name;
                                    _phoneController.text = phone;
                                    _selectedCustomerId = item['customerId'] ?? '';
                                    _selectedCustomerPoints = points;
                                    _usePointsRedemption = false; // Reset first
                                  });
                                  Navigator.pop(context); // Close dialog
                                },
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Batal'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _submitOrder() async {
    if (!_formKey.currentState!.validate()) return;
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tambahkan minimal 1 sepatu ke dalam pesanan')),
      );
      return;
    }
    if (_photoBeforeList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Foto kondisi awal (Before) wajib diunggah minimal 1 foto!')),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final dbService = Provider.of<DatabaseService>(context, listen: false);

      // Fetch customer's maps link if selected
      String customerMapsLink = '';
      if (_selectedCustomerId.isNotEmpty) {
        try {
          final userSnap = await FirebaseFirestore.instance.collection('users').doc(_selectedCustomerId).get();
          if (userSnap.exists) {
            customerMapsLink = userSnap.data()?['mapsLink'] ?? '';
          }
        } catch (_) {}
      }

      // Fetch dynamic logistics config to determine if address/fee should be populated
      bool requiresAddress = false;
      try {
        final doc = await FirebaseFirestore.instance.collection('logistics_methods').doc(_deliveryType).get();
        if (doc.exists) {
          requiresAddress = doc.data()?['requiresAddress'] == true;
        }
      } catch (_) {}

      // Generate invoice ID deterministically using helper
      String invoiceId = await dbService.generateInvoiceId();

      OrderModel order = OrderModel(
        id: invoiceId,
        idempotencyToken: _idempotencyToken,
        customerName: _nameController.text.trim(),
        customerPhone: _phoneController.text.trim(),
        customerId: _selectedCustomerId,
        items: _items,
        totalAmount: _totalPrice,
        status: 'diterima',
        paymentStatus: 'belum_bayar',
        qrisImage: 'assets/qris_pembayaran.jpeg',
        paymentProof: '',
        notes: _notesController.text.trim(),
        deliveryType: _deliveryType,
        deliveryAddress: requiresAddress ? _deliveryAddressController.text.trim() : '',
        deliveryFee: _deliveryFee,
        photoBefore: _photoBeforeList,
        photoAfter: const [],
        pointsRedeemed: _usePointsRedemption ? 10 : 0,
        mapsLink: customerMapsLink,
        voucherCode: _appliedVoucher?.code ?? '',
        voucherDiscount: _voucherDiscount,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Save order (idempotency token protects against duplicates)
      String finalInvoiceId = await dbService.addOrder(order);

      // Save/update customer database record
      try {
        await FirebaseFirestore.instance
            .collection('customers')
            .doc(_phoneController.text.trim())
            .set({
          'name': _nameController.text.trim(),
          'phone': _phoneController.text.trim(),
          if (_selectedCustomerId.isNotEmpty) 'uid': _selectedCustomerId,
          'lastOrderAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (e) {
        if (kDebugMode) print("Error saving customer record: $e");
      }

      if (mounted) {
        _showQrisDialog(finalInvoiceId, order);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal membuat pesanan: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dbService = Provider.of<DatabaseService>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Input Pesanan Baru'),
        automaticallyImplyLeading: !widget.isTab,
      ),
      body: StreamBuilder<List<CategoryModel>>(
        stream: _categoriesStream,
        builder: (context, catSnapshot) {
          if (catSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          _availableCategories = catSnapshot.data ?? [];

          return StreamBuilder<List<ServiceModel>>(
            stream: _servicesStream,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              _availableServices = snapshot.data ?? [];

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Customer details card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Informasi Pelanggan', style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _nameController,
                            decoration: InputDecoration(
                              hintText: 'Nama Pelanggan',
                              prefixIcon: const Icon(Icons.person_outline),
                              suffixIcon: IconButton(
                                icon: const Icon(Icons.contact_phone_outlined, color: AppTheme.primaryBlue),
                                tooltip: 'Cari pelanggan terdaftar',
                                onPressed: _showCustomerSearchDialog,
                              ),
                            ),
                            validator: (v) => v == null || v.isEmpty ? 'Nama pelanggan wajib diisi' : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(
                              hintText: 'Nomor WhatsApp (Contoh: 628123456789)',
                              prefixIcon: Icon(Icons.phone_outlined),
                            ),
                            validator: (v) {
                              if (v == null || v.isEmpty) return 'Nomor WhatsApp wajib diisi';
                              if (!v.startsWith('62')) return 'Harus diawali dengan 62 (Kode Negara)';
                              return null;
                            },
                          ),
                          if (_selectedCustomerId.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Chip(
                              label: Text('Pelanggan Terhubung (Poin: $_selectedCustomerPoints)'),
                              deleteIcon: const Icon(Icons.clear, size: 18),
                              onDeleted: () {
                                setState(() {
                                  _selectedCustomerId = '';
                                  _selectedCustomerPoints = 0;
                                  _usePointsRedemption = false;
                                });
                              },
                            ),
                          ],
                          if (_selectedCustomerPoints >= 10) ...[
                            const SizedBox(height: 12),
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
                                      'Loyalty Poin: $_selectedCustomerPoints\nTukarkan 10 Poin (Diskon Rp 25.000)',
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.brown),
                                    ),
                                  ),
                                  Switch(
                                    value: _usePointsRedemption,
                                    activeColor: Colors.amber,
                                    onChanged: (val) {
                                      setState(() {
                                        _usePointsRedemption = val;
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 2. Add Item Form Card (Tambah Layanan)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Tambah Layanan', style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _itemNameController,
                            decoration: const InputDecoration(
                              hintText: 'Nama / Model Barang (Contoh: Adidas Samba, Tas Fjallraven)',
                              prefixIcon: Icon(Icons.shopping_bag_outlined),
                            ),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<CategoryModel>(
                            value: _selectedCategory,
                            hint: const Text('Pilih Kategori Jasa'),
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.category_outlined),
                            ),
                            items: _availableCategories.map((cat) {
                              return DropdownMenuItem<CategoryModel>(
                                value: cat,
                                child: Text(cat.name),
                              );
                            }).toList(),
                            onChanged: (val) {
                              setState(() {
                                _selectedCategory = val;
                                _selectedService = null;
                              });
                            },
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<ServiceModel>(
                            value: _selectedService,
                            hint: const Text('Pilih Layanan'),
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.dry_cleaning_outlined),
                            ),
                            items: _availableServices
                                .where((s) => s.isActive && s.categoryId == _selectedCategory?.id)
                                .map((service) {
                              return DropdownMenuItem<ServiceModel>(
                                value: service,
                                child: Text('${service.name} (Rp ${service.price.toStringAsFixed(0)})'),
                              );
                            }).toList(),
                            onChanged: _selectedCategory == null ? null : (val) {
                              setState(() {
                                _selectedService = val;
                              });
                            },
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _addItem,
                              icon: const Icon(Icons.add, color: AppTheme.primaryBlue),
                              label: const Text('Tambahkan Produk', style: TextStyle(color: AppTheme.primaryBlue)),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: AppTheme.primaryBlue),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 3. List of added items
                  if (_items.isNotEmpty) ...[
                    Text('Daftar Sepatu di Keranjang', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _items.length,
                      itemBuilder: (context, idx) {
                        final item = _items[idx];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryBlue.withOpacity(0.08),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.check, color: AppTheme.primaryBlue),
                            ),
                            title: Text(item.itemName, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text('${item.categoryName} - ${item.serviceName}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                  Text('Rp ${item.price.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                    onPressed: () => _removeItem(idx),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                  ],

                  // 4. Photo Documentation Card (foto kondisi awal Before)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Foto Kondisi Awal (Before)', style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 8),
                          const Text(
                            'Ambil foto kondisi sepatu saat diserahkan (misal noda, robek, pudar) sebagai bukti.',
                            style: TextStyle(color: AppTheme.textGray, fontSize: 11),
                          ),
                          const SizedBox(height: 16),
                          if (_photoBeforeList.isNotEmpty) ...[
                            SizedBox(
                              height: 100,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                itemCount: _photoBeforeList.length,
                                itemBuilder: (context, index) {
                                  final img = _photoBeforeList[index];
                                  final isBase64 = img.startsWith('data:image');
                                  return Stack(
                                    children: [
                                      Container(
                                        width: 100,
                                        height: 100,
                                        margin: const EdgeInsets.only(right: 8),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(8),
                                          image: DecorationImage(
                                            image: isBase64
                                                ? MemoryImage(base64Decode(img.split(',')[1]))
                                                : FileImage(File(img)) as ImageProvider,
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        top: 0,
                                        right: 8,
                                        child: GestureDetector(
                                          onTap: () {
                                            setState(() {
                                              _photoBeforeList.removeAt(index);
                                            });
                                          },
                                          child: CircleAvatar(
                                            radius: 12,
                                            backgroundColor: Colors.black.withOpacity(0.5),
                                            child: const Icon(Icons.close, size: 14, color: Colors.white),
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () async {
                                    final img = await ImageService.pickImageFromCamera();
                                    if (img != null) {
                                      setState(() {
                                        _photoBeforeList.add(img);
                                      });
                                    }
                                  },
                                  icon: const Icon(Icons.camera_alt_outlined, color: AppTheme.primaryBlue),
                                  label: const Text('Kamera', style: TextStyle(color: AppTheme.primaryBlue)),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: AppTheme.primaryBlue),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () async {
                                    final img = await ImageService.pickImageFromGallery();
                                    if (img != null) {
                                      setState(() {
                                        _photoBeforeList.add(img);
                                      });
                                    }
                                  },
                                  icon: const Icon(Icons.photo_outlined, color: AppTheme.primaryBlue),
                                  label: const Text('Galeri', style: TextStyle(color: AppTheme.primaryBlue)),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: AppTheme.primaryBlue),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 5. Delivery & Logistics Card (Logistik & pengantaran)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: StreamBuilder<List<Map<String, dynamic>>>(
                        stream: _logisticsStream,
                        builder: (context, logSnapshot) {
                          final methods = logSnapshot.data ?? [];
                          
                          if (methods.isNotEmpty && !methods.any((m) => m['id'] == _deliveryType)) {
                            _deliveryType = methods.first['id'];
                          }

                          final selectedMethod = methods.firstWhere(
                            (m) => m['id'] == _deliveryType,
                            orElse: () => {'requiresAddress': false, 'fee': 0.0},
                          );
                          final bool requiresAddress = selectedMethod['requiresAddress'] == true;

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Logistik & Pengantaran', style: Theme.of(context).textTheme.titleMedium),
                              const SizedBox(height: 16),
                              DropdownButtonFormField<String>(
                                isExpanded: true,
                                value: _deliveryType.isEmpty && methods.isNotEmpty ? methods.first['id'] : _deliveryType,
                                decoration: const InputDecoration(
                                  prefixIcon: Icon(Icons.local_shipping_outlined),
                                ),
                                items: methods.map((m) {
                                  final fee = (m['fee'] ?? 0.0) as double;
                                  final feeStr = fee > 0 ? ' (Rp ${fee.toStringAsFixed(0)})' : '';
                                  return DropdownMenuItem<String>(
                                    value: m['id'] as String,
                                    child: Text(
                                      '${m['name']}$feeStr',
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    final newMethod = methods.firstWhere((m) => m['id'] == val);
                                    setState(() {
                                      _deliveryType = val;
                                      _deliveryFeeController.text = (newMethod['fee'] ?? 0.0).toStringAsFixed(0);
                                    });
                                  }
                                },
                              ),
                              if (requiresAddress) ...[
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _deliveryAddressController,
                                  maxLines: 2,
                                  decoration: const InputDecoration(
                                    hintText: 'Alamat lengkap penjemputan/pengantaran',
                                    prefixIcon: Icon(Icons.location_on_outlined),
                                  ),
                                  validator: (v) => requiresAddress && (v == null || v.isEmpty)
                                      ? 'Alamat wajib diisi untuk metode ini'
                                      : null,
                                ),
                              ],
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _deliveryFeeController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Biaya Ongkir (Rp)',
                                  prefixIcon: Icon(Icons.monetization_on_outlined),
                                ),
                                onChanged: (val) {
                                  setState(() {}); // Recalculate total
                                },
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 6. Voucher Card (Voucher diskon)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Voucher Diskon', style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 12),
                          StreamBuilder<List<VoucherModel>>(
                            stream: _vouchersStream,
                            builder: (context, snapshot) {
                              final activeVouchers = snapshot.data ?? [];
                              final eligibleVouchers = activeVouchers.where((v) => _itemsPrice >= v.minOrder).toList();

                              // Auto de-apply if cart total drops below minOrder
                              if (_appliedVoucher != null && !eligibleVouchers.contains(_appliedVoucher)) {
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  setState(() {
                                    _appliedVoucher = null;
                                  });
                                });
                              }

                              if (activeVouchers.isEmpty) {
                                return const Text(
                                  'Tidak ada voucher aktif tersedia',
                                  style: TextStyle(fontSize: 12, color: AppTheme.textGray, fontStyle: FontStyle.italic),
                                );
                              }

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  DropdownButtonFormField<String>(
                                    isExpanded: true,
                                    value: _appliedVoucher?.id,
                                    hint: const Text('Pilih Voucher Diskon', style: TextStyle(fontSize: 12)),
                                    decoration: const InputDecoration(
                                      prefixIcon: Icon(Icons.confirmation_number_outlined),
                                    ),
                                    items: eligibleVouchers.map((v) {
                                      final discStr = v.discountType == 'percentage'
                                          ? 'Diskon ${v.discountValue.toStringAsFixed(0)}%'
                                          : 'Diskon Rp ${v.discountValue.toStringAsFixed(0).replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (Match m) => "${m[1]}.")}';
                                      return DropdownMenuItem<String>(
                                        value: v.id,
                                        child: Text(
                                          '${v.name} ($discStr)',
                                          style: const TextStyle(fontSize: 12),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      );
                                    }).toList(),
                                    onChanged: (val) {
                                      setState(() {
                                        _appliedVoucher = eligibleVouchers.firstWhere((v) => v.id == val);
                                      });
                                    },
                                  ),
                                  if (eligibleVouchers.isEmpty && activeVouchers.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      'Belanja belum memenuhi syarat minimum voucher (Min. belanja Rp ${activeVouchers.map((v) => v.minOrder).reduce((a, b) => a < b ? a : b).toStringAsFixed(0).replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (Match m) => "${m[1]}.")})',
                                      style: const TextStyle(fontSize: 11, color: Colors.orange, fontStyle: FontStyle.italic),
                                    ),
                                  ],
                                  if (_appliedVoucher != null) ...[
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        const Icon(Icons.check_circle, color: Colors.green, size: 18),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            'Terpasang: ${_appliedVoucher!.name} (-Rp ${_voucherDiscount.toStringAsFixed(0).replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (Match m) => "${m[1]}.")})',
                                            style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 13),
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.close, color: Colors.redAccent, size: 18),
                                          onPressed: () {
                                            setState(() {
                                              _appliedVoucher = null;
                                            });
                                          },
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 7. Notes Card (catatan Tambahan)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Catatan Tambahan', style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _notesController,
                            maxLines: 2,
                            decoration: const InputDecoration(
                              hintText: 'Tulis noda membandel, sobekan, atau request khusus...',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Total & submit section
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryBlue.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.12)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                               const Text('Total Pembayaran', style: TextStyle(color: AppTheme.textGray, fontSize: 12)),
                              const SizedBox(height: 4),
                              if (_voucherDiscount + (_usePointsRedemption && _selectedCustomerPoints >= 10 ? 25000 : 0.0) > 0) ...[
                                Text(
                                  'Rp ${(_itemsPrice + _deliveryFee).toStringAsFixed(0).replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (Match m) => "${m[1]}.")}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    decoration: TextDecoration.lineThrough,
                                    color: Colors.red,
                                  ),
                                ),
                                Text(
                                  'Diskon: -Rp ${(_voucherDiscount + (_usePointsRedemption && _selectedCustomerPoints >= 10 ? 25000 : 0.0)).toStringAsFixed(0).replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (Match m) => "${m[1]}.")}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.green,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                              Text(
                                'Rp ${_totalPrice.toStringAsFixed(0).replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (Match m) => "${m[1]}.")}',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.primaryBlue,
                                ),
                              ),
                            ],
                          ),
                        ),
                        ElevatedButton(
                          onPressed: _isSubmitting ? null : _submitOrder,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryBlue,
                            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                          ),
                          child: _isSubmitting
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                )
                              : const Text('Buat Pesanan'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
            },
          );
        },
      ),
    );
  }
}
