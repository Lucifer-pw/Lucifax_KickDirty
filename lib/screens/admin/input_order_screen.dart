import 'dart:math';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../models/order_model.dart';
import '../../models/service_model.dart';
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

  @override
  void initState() {
    super.initState();
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
    super.dispose();
  }

  void _addItem() {
    if (_itemNameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nama/Merek Sepatu wajib diisi')),
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
          price: _selectedService!.price,
        ),
      );
      _itemNameController.clear();
      _selectedService = null;
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
    setState(() {
      _items.clear();
      _selectedService = null;
      _selectedCustomerId = '';
      _selectedCustomerPoints = 0;
      _usePointsRedemption = false;
      _deliveryType = 'drop_off_only';
      _photoBeforeList = [];
      _generateIdempotencyToken();
    });
  }

  double get _itemsPrice => _items.fold(0, (sum, item) => sum + item.price);
  
  double get _deliveryFee => double.tryParse(_deliveryFeeController.text) ?? 0.0;

  double get _totalPrice {
    double total = _itemsPrice;
    if (_deliveryType == 'pickup_delivery') {
      total += _deliveryFee;
    }
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

  Future<void> _showCustomerSearchDialog() async {
    final customersFuture = _fetchAllCustomers();
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

    setState(() {
      _isSubmitting = true;
    });

    try {
      final dbService = Provider.of<DatabaseService>(context, listen: false);

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
        notes: _notesController.text.trim(),
        deliveryType: _deliveryType,
        deliveryAddress: _deliveryType == 'pickup_delivery' ? _deliveryAddressController.text.trim() : '',
        deliveryFee: _deliveryType == 'pickup_delivery' ? _deliveryFee : 0.0,
        photoBefore: _photoBeforeList,
        photoAfter: const [],
        pointsRedeemed: _usePointsRedemption ? 10 : 0,
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
      body: StreamBuilder<List<ServiceModel>>(
        stream: dbService.getServices(),
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
                  // Customer details card
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

                  // Delivery & Logistics Card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Logistik & Pengantaran', style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            value: _deliveryType,
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.local_shipping_outlined),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'drop_off_only', child: Text('Drop-Off & Ambil Sendiri')),
                              DropdownMenuItem(value: 'pickup_delivery', child: Text('Penjemputan & Pengantaran (Kurir)')),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                setState(() {
                                  _deliveryType = val;
                                  if (val == 'pickup_delivery') {
                                    _deliveryFeeController.text = '15000';
                                  } else {
                                    _deliveryFeeController.text = '0';
                                  }
                                });
                              }
                            },
                          ),
                          if (_deliveryType == 'pickup_delivery') ...[
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _deliveryAddressController,
                              maxLines: 2,
                              decoration: const InputDecoration(
                                hintText: 'Alamat lengkap penjemputan/pengantaran',
                                prefixIcon: Icon(Icons.location_on_outlined),
                              ),
                              validator: (v) => _deliveryType == 'pickup_delivery' && (v == null || v.isEmpty)
                                  ? 'Alamat wajib diisi untuk kurir'
                                  : null,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _deliveryFeeController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                hintText: 'Ongkos Kirim / Delivery Fee (Rp)',
                                prefixIcon: Icon(Icons.monetization_on_outlined),
                              ),
                              onChanged: (val) {
                                setState(() {}); // Recalculate total
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Photo Documentation Card
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

                  // Add Item Form
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Tambah Sepatu & Layanan', style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _itemNameController,
                            decoration: const InputDecoration(
                              hintText: 'Merek & Model Sepatu (Contoh: Converse Chuck 70)',
                              prefixIcon: Icon(Icons.shopping_bag_outlined),
                            ),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<ServiceModel>(
                            value: _selectedService,
                            hint: const Text('Pilih Layanan'),
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.dry_cleaning_outlined),
                            ),
                            items: _availableServices.map((service) {
                              return DropdownMenuItem<ServiceModel>(
                                value: service,
                                child: Text('${service.name} (Rp ${service.price.toStringAsFixed(0)})'),
                              );
                            }).toList(),
                            onChanged: (val) {
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
                              label: const Text('Tambahkan Sepatu', style: TextStyle(color: AppTheme.primaryBlue)),
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

                  // List of added items
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
                            subtitle: Text(item.serviceName),
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

                  // Notes card
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
                              Text(
                                'Rp ${_totalPrice.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.')}',
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
      ),
    );
  }
}
