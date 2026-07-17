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
import '../../utils/error_helper.dart';
import '../../utils/platform_helper.dart';
import '../../widgets/map_picker_widget.dart';
import 'package:url_launcher/url_launcher.dart';

class InputOrderScreen extends StatefulWidget {
  final bool isTab;
  final VoidCallback? onOrderSubmitted;
  InputOrderScreen({Key? key, this.isTab = false, this.onOrderSubmitted}) : super(key: key);

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
  final _mapsLinkController = TextEditingController();
  final _deliveryFeeController = TextEditingController(text: '0');
  bool _isGpsLoading = false;

  Map<String, double>? _parseLatLng(String url) {
    if (url.isEmpty) return null;
    
    // Try query=lat,lng or q=lat,lng
    final regExp = RegExp(r'(?:query|q|place)=([+-]?\d+\.\d+)\s*,\s*([+-]?\d+\.\d+)');
    final match = regExp.firstMatch(url);
    if (match != null && match.groupCount >= 2) {
      final lat = double.tryParse(match.group(1)!);
      final lng = double.tryParse(match.group(2)!);
      if (lat != null && lng != null) {
        return {'latitude': lat, 'longitude': lng};
      }
    }
    
    // Try @lat,lng
    final regExpAt = RegExp(r'@([+-]?\d+\.\d+)\s*,\s*([+-]?\d+\.\d+)');
    final matchAt = regExpAt.firstMatch(url);
    if (matchAt != null && matchAt.groupCount >= 2) {
      final lat = double.tryParse(matchAt.group(1)!);
      final lng = double.tryParse(matchAt.group(2)!);
      if (lat != null && lng != null) {
        return {'latitude': lat, 'longitude': lng};
      }
    }

    // Try raw coordinates (e.g. -7.556,110.825)
    final regExpRaw = RegExp(r'^([+-]?\d+\.\d+)\s*,\s*([+-]?\d+\.\d+)$');
    final matchRaw = regExpRaw.firstMatch(url.trim());
    if (matchRaw != null && matchRaw.groupCount >= 2) {
      final lat = double.tryParse(matchRaw.group(1)!);
      final lng = double.tryParse(matchRaw.group(2)!);
      if (lat != null && lng != null) {
        return {'latitude': lat, 'longitude': lng};
      }
    }

    return null;
  }

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
        SnackBar(content: Text('Nama Merk Sepatu wajib diisi')),
      );
      return;
    }
    if (_selectedService == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Pilih jenis layanan terlebih dahulu')),
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
    return _appliedVoucher!.calculateDiscount(_itemsPrice, itemQty: _items.length);
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
          title: Text('Pembayaran QRIS', textAlign: TextAlign.center),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Invoice: $invoiceId', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text(
                'Total: Rp ${_totalPrice.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.')}',
                style: TextStyle(fontSize: 16, color: AppTheme.primaryBlue, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 16),
              // QRIS Image
              Image.asset(
                'assets/qris_pembayaran.jpeg',
                height: 250,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => Container(
                  height: 150,
                  color: AppTheme.lightGray,
                  child: Center(child: Icon(Icons.qr_code, size: 80, color: AppTheme.textGray)),
                ),
              ),
              SizedBox(height: 12),
              Text(
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
              child: Text('Sudah Bayar / Lunas', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
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
              child: Text('Bayar Nanti (Belum Bayar)', style: TextStyle(color: AppTheme.textGray)),
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
          title: Text('Edit Informasi Pelanggan'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: InputDecoration(labelText: 'Nama Pelanggan'),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Nama wajib diisi' : null,
                ),
                SizedBox(height: 12),
                TextFormField(
                  controller: phoneController,
                  decoration: InputDecoration(labelText: 'Nomor WhatsApp'),
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
              child: Text('Batal'),
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
                    SnackBar(content: Text('Informasi pelanggan berhasil diperbarui')),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Gagal memperbarui: ${getCleanErrorMessage(e)}')),
                  );
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryBlue),
              child: Text('Simpan'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showDeleteCustomerDialog(BuildContext context, String name, String phone, String customerId, VoidCallback onDeleted) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Hapus Pelanggan'),
          content: Text('Apakah Anda yakin ingin menghapus pelanggan "$name" (+$phone) dari daftar?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Batal'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: Text('Hapus'),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      try {
        // 1. Delete from customers collection
        await FirebaseFirestore.instance.collection('customers').doc(phone).delete();
        
        // 2. Delete from users collection if registered customer
        if (customerId.isNotEmpty) {
          await FirebaseFirestore.instance.collection('users').doc(customerId).delete();
        }

        onDeleted();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Pelanggan berhasil dihapus')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal menghapus: ${getCleanErrorMessage(e)}')),
          );
        }
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
              title: Text('Cari Pelanggan Terdaftar'),
              content: SizedBox(
                width: double.maxFinite,
                height: 350,
                child: Column(
                  children: [
                    TextField(
                      decoration: InputDecoration(
                        hintText: 'Cari nama atau nomor WA...',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (val) {
                        setStateDialog(() {
                          searchQuery = val.toLowerCase();
                        });
                      },
                    ),
                    SizedBox(height: 12),
                    Expanded(
                      child: FutureBuilder<List<Map<String, String>>>(
                        future: customersFuture,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return Center(child: CircularProgressIndicator());
                          }
                          if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
                            return Center(child: Text('Belum ada pelanggan terdaftar.'));
                          }

                          final docs = snapshot.data!.where((item) {
                            final name = item['name']?.toLowerCase() ?? '';
                            final phone = item['phone'] ?? '';
                            return name.contains(searchQuery) || phone.contains(searchQuery);
                          }).toList();

                          if (docs.isEmpty) {
                            return Center(child: Text('Pelanggan tidak ditemukan.'));
                          }

                          return ListView.separated(
                            itemCount: docs.length,
                            separatorBuilder: (_, __) => Divider(),
                            itemBuilder: (context, index) {
                              final item = docs[index];
                              final name = item['name'] ?? '';
                              final phone = item['phone'] ?? '';
                              final points = int.tryParse(item['loyaltyPoints'] ?? '0') ?? 0;
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: AppTheme.primaryBlue.withOpacity(0.08),
                                  child: Icon(Icons.person, color: AppTheme.primaryBlue),
                                ),
                                title: Text(name, style: TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text('WA: +$phone • Poin: $points'),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: Icon(Icons.edit, color: Colors.blue, size: 20),
                                      onPressed: () async {
                                        await _showEditCustomerDialog(context, name, phone, item['customerId'] ?? '', points, () {
                                          setStateDialog(() {
                                            customersFuture = _fetchAllCustomers();
                                          });
                                        });
                                      },
                                    ),
                                    IconButton(
                                      icon: Icon(Icons.delete, color: Colors.red, size: 20),
                                      onPressed: () async {
                                        await _showDeleteCustomerDialog(
                                          context, 
                                          name, 
                                          phone, 
                                          item['customerId'] ?? '', 
                                          () {
                                            setStateDialog(() {
                                              customersFuture = _fetchAllCustomers();
                                            });
                                          },
                                        );
                                      },
                                    ),
                                  ],
                                ),
                                onTap: () {
                                   final customerId = item['customerId'] ?? '';
                                   setState(() {
                                     _nameController.text = name;
                                     _phoneController.text = phone;
                                     _selectedCustomerId = customerId;
                                     _selectedCustomerPoints = points;
                                     _usePointsRedemption = false; // Reset first
                                     _deliveryAddressController.text = '';
                                     _mapsLinkController.text = '';
                                   });
                                   if (customerId.isNotEmpty) {
                                     FirebaseFirestore.instance
                                         .collection('users')
                                         .doc(customerId)
                                         .get()
                                         .then((userSnap) {
                                       if (userSnap.exists) {
                                         final address = userSnap.data()?['addressDetail'] as String? ?? '';
                                         final mapLink = userSnap.data()?['mapsLink'] as String? ?? '';
                                         setState(() {
                                           if (address.isNotEmpty) {
                                             _deliveryAddressController.text = address;
                                           }
                                           if (mapLink.isNotEmpty) {
                                             _mapsLinkController.text = mapLink;
                                           }
                                         });
                                       }
                                     }).catchError((_) {});
                                   }
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
                  child: Text('Batal'),
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
        SnackBar(content: Text('Tambahkan minimal 1 sepatu ke dalam pesanan')),
      );
      return;
    }
    if (_photoBeforeList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Foto kondisi awal (Before) wajib diunggah minimal 1 foto!')),
      );
      return;
    }

    int totalSize = _photoBeforeList.fold(0, (sum, img) => sum + (img.length * 3 / 4).round());
    if (totalSize > 850 * 1024) {
      showDialog(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange),
              SizedBox(width: 8),
              Text('Ukuran Total Foto Terlalu Besar'),
            ],
          ),
          content: Text(
            'Total ukuran ${_photoBeforeList.length} foto sebelum cuci adalah ${(totalSize / 1024).toStringAsFixed(1)} KB.\n\n'
            'Batas maksimal total untuk semua foto adalah 850 KB agar dapat disimpan di database. '
            'Silakan hapus sebagian foto atau gunakan foto berukuran lebih kecil.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final dbService = Provider.of<DatabaseService>(context, listen: false);

      // Fetch customer's maps link
      String customerMapsLink = _mapsLinkController.text.trim();

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
        status: 'dibayar',
        paymentStatus: 'belum_bayar',
        qrisImage: 'assets/qris_pembayaran.jpeg',
        paymentProof: '',
        notes: _notesController.text.trim(),
        deliveryType: _deliveryType,
        deliveryAddress: requiresAddress ? _deliveryAddressController.text.trim() : '',
        deliveryFee: _deliveryFee,
        photoBefore: _photoBeforeList,
        photoAfter: [],
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

        // If customer is registered, also sync address and map link to user document
        if (_selectedCustomerId.isNotEmpty) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(_selectedCustomerId)
              .update({
            'addressDetail': _deliveryAddressController.text.trim(),
            'mapsLink': customerMapsLink,
          });
        }
      } catch (e) {
        if (kDebugMode) print("Error saving customer record: $e");
      }

      if (mounted) {
        _showQrisDialog(finalInvoiceId, order);
      }
    } catch (e) {
      final errorStr = e.toString().toLowerCase();
      if (errorStr.contains('exceeds') || errorStr.contains('too large') || errorStr.contains('size') || errorStr.contains('limit')) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orange),
                  SizedBox(width: 8),
                  Text('Ukuran Foto Terlalu Besar'),
                ],
              ),
              content: Text(
                'Gagal membuat pesanan karena total ukuran foto kondisi awal (Before) yang Anda unggah terlalu besar (melebihi batas database).\n\n'
                'Silakan kurangi jumlah foto atau gunakan foto dengan resolusi lebih rendah.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('OK'),
                ),
              ],
            );
          },
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal membuat pesanan: ${getCleanErrorMessage(e)}')),
        );
      }
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
        title: Text('Input Pesanan Baru'),
        automaticallyImplyLeading: !widget.isTab,
      ),
      body: StreamBuilder<List<CategoryModel>>(
        stream: _categoriesStream,
        builder: (context, catSnapshot) {
          if (catSnapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }
          _availableCategories = catSnapshot.data ?? [];

          return StreamBuilder<List<ServiceModel>>(
            stream: _servicesStream,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Center(child: CircularProgressIndicator());
              }
              _availableServices = snapshot.data ?? [];

          return SingleChildScrollView(
            padding: EdgeInsets.all(16.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Customer details card
                  Card(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Informasi Pelanggan', style: Theme.of(context).textTheme.titleMedium),
                          SizedBox(height: 16),
                          TextFormField(
                            controller: _nameController,
                            decoration: InputDecoration(
                              hintText: 'Nama Pelanggan',
                              prefixIcon: Icon(Icons.person_outline),
                              suffixIcon: IconButton(
                                icon: Icon(Icons.contact_phone_outlined, color: AppTheme.primaryBlue),
                                tooltip: 'Cari pelanggan terdaftar',
                                onPressed: _showCustomerSearchDialog,
                              ),
                            ),
                            validator: (v) => v == null || v.isEmpty ? 'Nama pelanggan wajib diisi' : null,
                          ),
                          SizedBox(height: 12),
                          TextFormField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            decoration: InputDecoration(
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
                            SizedBox(height: 8),
                            Chip(
                              label: Text('Pelanggan Terhubung (Poin: $_selectedCustomerPoints)'),
                              deleteIcon: Icon(Icons.clear, size: 18),
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
                            SizedBox(height: 12),
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.amber.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.amber.withOpacity(0.3)),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.stars, color: Colors.amber),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Loyalty Poin: $_selectedCustomerPoints\nTukarkan 10 Poin (Diskon Rp 25.000)',
                                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.brown),
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
                  SizedBox(height: 16),

                  // 2. Add Item Form Card (Tambah Layanan)
                  Card(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Tambah Layanan', style: Theme.of(context).textTheme.titleMedium),
                          SizedBox(height: 16),
                          TextFormField(
                            controller: _itemNameController,
                            decoration: InputDecoration(
                              hintText: 'Nama / Model Barang (Contoh: Adidas Samba, Tas Fjallraven)',
                              prefixIcon: Icon(Icons.shopping_bag_outlined),
                            ),
                          ),
                          SizedBox(height: 12),
                          DropdownButtonFormField<CategoryModel>(
                            value: _selectedCategory,
                            hint: Text('Pilih Kategori Jasa'),
                            decoration: InputDecoration(
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
                          SizedBox(height: 12),
                          DropdownButtonFormField<ServiceModel>(
                            value: _selectedService,
                            hint: Text('Pilih Layanan'),
                            decoration: InputDecoration(
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
                          SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _addItem,
                              icon: Icon(Icons.add, color: AppTheme.primaryBlue),
                              label: Text('Tambahkan Produk', style: TextStyle(color: AppTheme.primaryBlue)),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: AppTheme.primaryBlue),
                                padding: EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: 16),

                  // 3. List of added items
                  if (_items.isNotEmpty) ...[
                    Text('Daftar Sepatu di Keranjang', style: Theme.of(context).textTheme.titleMedium),
                    SizedBox(height: 8),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: NeverScrollableScrollPhysics(),
                      itemCount: _items.length,
                      itemBuilder: (context, idx) {
                        final item = _items[idx];
                        return Card(
                          margin: EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: Container(
                              padding: EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryBlue.withOpacity(0.08),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.check, color: AppTheme.primaryBlue),
                            ),
                            title: Text(item.itemName, style: TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text('${item.categoryName} - ${item.serviceName}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                  Text('Rp ${item.price.toStringAsFixed(0)}', style: TextStyle(fontWeight: FontWeight.bold)),
                                  IconButton(
                                    icon: Icon(Icons.delete_outline, color: Colors.redAccent),
                                    onPressed: () => _removeItem(idx),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    SizedBox(height: 16),
                  ],

                  // 4. Photo Documentation Card (foto kondisi awal Before)
                  Card(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Foto Kondisi Awal (Before)', style: Theme.of(context).textTheme.titleMedium),
                          SizedBox(height: 8),
                          Text(
                            'Ambil foto kondisi sepatu saat diserahkan (misal noda, robek, pudar) sebagai bukti.',
                            style: TextStyle(color: AppTheme.textGray, fontSize: 11),
                          ),
                          SizedBox(height: 16),
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
                                        margin: EdgeInsets.only(right: 8),
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
                                            child: Icon(Icons.close, size: 14, color: Colors.white),
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                            SizedBox(height: 16),
                          ],
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () async {
                                    final img = await ImageService.pickImageFromCamera(context: context);
                                    if (img != null) {
                                      setState(() {
                                        _photoBeforeList.add(img);
                                      });
                                    }
                                  },
                                  icon: Icon(Icons.camera_alt_outlined, color: AppTheme.primaryBlue),
                                  label: Text('Kamera', style: TextStyle(color: AppTheme.primaryBlue)),
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(color: AppTheme.primaryBlue),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                ),
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () async {
                                    final img = await ImageService.pickImageFromGallery(context: context);
                                    if (img != null) {
                                      setState(() {
                                        _photoBeforeList.add(img);
                                      });
                                    }
                                  },
                                  icon: Icon(Icons.photo_outlined, color: AppTheme.primaryBlue),
                                  label: Text('Galeri', style: TextStyle(color: AppTheme.primaryBlue)),
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(color: AppTheme.primaryBlue),
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
                  SizedBox(height: 16),

                  // 5. Delivery & Logistics Card (Logistik & pengantaran)
                  Card(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
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
                              SizedBox(height: 16),
                              DropdownButtonFormField<String>(
                                isExpanded: true,
                                value: _deliveryType.isEmpty && methods.isNotEmpty ? methods.first['id'] : _deliveryType,
                                decoration: InputDecoration(
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
                                SizedBox(height: 12),
                                TextFormField(
                                  controller: _deliveryAddressController,
                                  maxLines: 2,
                                  decoration: InputDecoration(
                                    labelText: 'Detail Alamat',
                                    hintText: 'Alamat lengkap penjemputan/pengantaran',
                                    prefixIcon: Icon(Icons.location_on_outlined),
                                  ),
                                  validator: (v) => requiresAddress && (v == null || v.isEmpty)
                                      ? 'Alamat wajib diisi untuk metode ini'
                                      : null,
                                ),
                                SizedBox(height: 12),
                                TextFormField(
                                  controller: _mapsLinkController,
                                  decoration: InputDecoration(
                                    labelText: 'Link / Koordinat Google Maps',
                                    hintText: 'https://maps.google.com/... atau -7.556,110.825',
                                    prefixIcon: Icon(Icons.map_outlined),
                                    suffixIcon: IconButton(
                                      icon: Icon(Icons.pin_drop, color: AppTheme.primaryBlue),
                                      tooltip: 'Pilih di Peta secara Manual',
                                      onPressed: () async {
                                        final result = await Navigator.push<Map<String, String>>(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => MapPickerScreen(
                                              initialMapsLink: _mapsLinkController.text,
                                            ),
                                          ),
                                        );
                                        if (result != null) {
                                          setState(() {
                                            _mapsLinkController.text = result['mapsLink'] ?? '';
                                            if (result['address'] != null && result['address']!.isNotEmpty) {
                                              _deliveryAddressController.text = result['address']!;
                                            }
                                          });
                                        }
                                      },
                                    ),
                                    helperText: 'Buka Google Maps -> Cari Lokasi -> Bagikan -> Salin Link, atau masukkan koordinat manual.',
                                    helperMaxLines: 2,
                                  ),
                                  onChanged: (val) {
                                    setState(() {});
                                  },
                                ),
                                SizedBox(height: 8),

                                // Minimap preview
                                Builder(
                                  builder: (context) {
                                    final coords = _parseLatLng(_mapsLinkController.text);
                                    if (coords == null) {
                                      return Container(
                                        padding: EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.amber.withOpacity(0.05),
                                          borderRadius: BorderRadius.circular(16),
                                          border: Border.all(color: Colors.amber.withOpacity(0.2)),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(Icons.info_outline, color: Colors.amber[700], size: 20),
                                            SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                'Lokasi GPS belum dikunci/dimasukkan (disarankan agar kurir tidak tersesat)',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.amber[800],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }
                                    
                                    return Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Pratinjau Peta Lokasi Pengiriman:',
                                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.darkBlueText),
                                        ),
                                        SizedBox(height: 4),
                                        GestureDetector(
                                          onTap: () async {
                                            final currentLink = _mapsLinkController.text.trim();
                                            if (currentLink.startsWith('http') && await canLaunchUrl(Uri.parse(currentLink))) {
                                              await launchUrl(Uri.parse(currentLink));
                                            } else {
                                              final mapUrl = 'https://www.google.com/maps/search/?api=1&query=${coords['latitude']},${coords['longitude']}';
                                              if (await canLaunchUrl(Uri.parse(mapUrl))) {
                                                await launchUrl(Uri.parse(mapUrl));
                                              }
                                            }
                                          },
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(16),
                                            child: Container(
                                              height: 150,
                                              width: double.infinity,
                                              color: Colors.grey[200],
                                              child: Stack(
                                                children: [
                                                  Image.network(
                                                    'https://static-maps.yandex.ru/1.x/?ll=${coords['longitude']},${coords['latitude']}&z=15&size=450,150&l=map&pt=${coords['longitude']},${coords['latitude']},pm2rdm',
                                                    fit: BoxFit.cover,
                                                    width: double.infinity,
                                                    height: double.infinity,
                                                    errorBuilder: (context, error, stackTrace) {
                                                      return Container(
                                                        color: Colors.grey[300],
                                                        child: Center(
                                                          child: Column(
                                                            mainAxisAlignment: MainAxisAlignment.center,
                                                            children: [
                                                              Icon(Icons.map_outlined, color: Colors.grey, size: 36),
                                                              SizedBox(height: 4),
                                                              Text(
                                                                'Peta tidak dapat dimuat',
                                                                style: TextStyle(color: Colors.grey, fontSize: 12),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      );
                                                    },
                                                  ),
                                                  Positioned(
                                                    bottom: 8,
                                                    right: 8,
                                                    child: Container(
                                                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                      decoration: BoxDecoration(
                                                        color: Colors.black.withOpacity(0.6),
                                                        borderRadius: BorderRadius.circular(8),
                                                      ),
                                                      child: Row(
                                                        children: [
                                                          Icon(Icons.open_in_new, color: Colors.white, size: 10),
                                                          SizedBox(width: 4),
                                                          Text(
                                                            'Buka Google Maps',
                                                            style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                                SizedBox(height: 8),

                                // Button to pick location manually
                                SizedBox(
                                  width: double.infinity,
                                  child: TextButton.icon(
                                    onPressed: () async {
                                      final result = await Navigator.push<Map<String, String>>(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => MapPickerScreen(
                                            initialMapsLink: _mapsLinkController.text,
                                          ),
                                        ),
                                      );
                                      if (result != null) {
                                        setState(() {
                                          _mapsLinkController.text = result['mapsLink'] ?? '';
                                          if (result['address'] != null && result['address']!.isNotEmpty) {
                                            _deliveryAddressController.text = result['address']!;
                                          }
                                        });
                                      }
                                    },
                                    icon: Icon(Icons.pin_drop, color: Colors.red),
                                    label: Text(
                                      'Pilih Lokasi Manual via Peta',
                                      style: TextStyle(
                                        color: Colors.red,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    style: TextButton.styleFrom(
                                      backgroundColor: Colors.red.withOpacity(0.08),
                                      padding: EdgeInsets.symmetric(vertical: 14),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(height: 8),

                                // Button to lock GPS Location
                                SizedBox(
                                  width: double.infinity,
                                  child: TextButton.icon(
                                    onPressed: _isGpsLoading
                                        ? null
                                        : () async {
                                            setState(() {
                                              _isGpsLoading = true;
                                            });
                                            try {
                                              final link = await getGpsLocation();
                                              if (link != null) {
                                                setState(() {
                                                  _mapsLinkController.text = link;
                                                });
                                                if (context.mounted) {
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    SnackBar(
                                                      content: Text('Lokasi GPS berhasil dikunci!'),
                                                    ),
                                                  );
                                                }
                                              } else {
                                                if (context.mounted) {
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    SnackBar(
                                                      content: Text('Gagal mendapatkan lokasi. Pastikan GPS aktif.'),
                                                    ),
                                                  );
                                                }
                                              }
                                            } catch (e) {
                                              if (context.mounted) {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  SnackBar(content: Text('Gagal mengunci lokasi: ${getCleanErrorMessage(e)}')),
                                                );
                                              }
                                            } finally {
                                              setState(() {
                                                _isGpsLoading = false;
                                              });
                                            }
                                          },
                                    icon: _isGpsLoading
                                        ? SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: AppTheme.primaryBlue,
                                            ),
                                          )
                                        : Icon(Icons.gps_fixed, color: AppTheme.primaryBlue),
                                    label: Text(
                                      _isGpsLoading ? 'Mengunci Lokasi...' : 'Kunci Lokasi Otomatis via GPS',
                                      style: TextStyle(
                                        color: AppTheme.primaryBlue,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    style: TextButton.styleFrom(
                                      backgroundColor: AppTheme.lightBlueBackground,
                                      padding: EdgeInsets.symmetric(vertical: 14),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                              SizedBox(height: 12),
                              TextFormField(
                                controller: _deliveryFeeController,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
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
                  SizedBox(height: 16),

                  // 6. Voucher Card (Voucher diskon)
                  Card(
                    child: Padding(
padding: EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Voucher Diskon', style: Theme.of(context).textTheme.titleMedium),
                          SizedBox(height: 12),
                          StreamBuilder<List<VoucherModel>>(
                            stream: _vouchersStream,
                            builder: (context, snapshot) {
                              if (snapshot.hasError) {
                                if (kDebugMode) print("Vouchers Stream Error: ${snapshot.error}");
                                return Text('Gagal memuat voucher: ${getCleanErrorMessage(snapshot.error)}', style: TextStyle(fontSize: 11, color: Colors.red));
                              }
                              final activeVouchers = snapshot.data ?? [];
                              final eligibleVouchers = activeVouchers.where((v) => _itemsPrice >= v.minOrder && _items.length >= v.minQty).toList();

                              if (activeVouchers.isEmpty) {
                                return Text(
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
                                    hint: Text('Pilih Voucher Diskon', style: TextStyle(fontSize: 12)),
                                    decoration: InputDecoration(
                                      prefixIcon: Icon(Icons.confirmation_number_outlined),
                                    ),
                                    items: activeVouchers.map((v) {
                                      final isEligible = eligibleVouchers.contains(v);
                                      final discStr = v.discountType == 'percentage'
                                          ? 'Diskon ${v.discountValue.toStringAsFixed(0)}%'
                                          : 'Diskon Rp ${v.discountValue.toStringAsFixed(0).replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (Match m) => "${m[1]}.")}';
                                      return DropdownMenuItem<String>(
                                        value: v.id,
                                        child: Text(
                                          isEligible ? '${v.name} ($discStr)' : '${v.name} ($discStr) (Belum memenuhi syarat)',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: isEligible ? AppTheme.darkBlueText : Colors.grey,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      );
                                    }).toList(),
                                    onChanged: (val) {
                                      setState(() {
                                        _appliedVoucher = activeVouchers.firstWhere((v) => v.id == val);
                                      });
                                    },
                                  ),
                                  if (_appliedVoucher != null) ...[
                                    SizedBox(height: 10),
                                    Row(
                                      children: [
                                        Icon(
                                          eligibleVouchers.contains(_appliedVoucher) ? Icons.check_circle : Icons.warning_amber_rounded,
                                          color: eligibleVouchers.contains(_appliedVoucher) ? Colors.green : Colors.orange,
                                          size: 18,
                                        ),
                                        SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            eligibleVouchers.contains(_appliedVoucher)
                                                ? 'Terpasang: ${_appliedVoucher!.name} (-Rp ${_voucherDiscount.toStringAsFixed(0).replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (Match m) => "${m[1]}.")})'
                                                : 'Voucher tidak aktif: Belum memenuhi syarat ' + 
                                                  (_appliedVoucher!.minOrder > 0 ? '(Min. belanja Rp ${_appliedVoucher!.minOrder.toStringAsFixed(0).replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (Match m) => "${m[1]}.")}) ' : '') + 
                                                  (_appliedVoucher!.minQty > 0 ? '(Min. ${_appliedVoucher!.minQty} pasang sepatu)' : ''),
                                            style: TextStyle(
                                              color: eligibleVouchers.contains(_appliedVoucher) ? Colors.green : Colors.orange,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                        IconButton(
                                          icon: Icon(Icons.close, color: Colors.redAccent, size: 18),
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
                  SizedBox(height: 16),

                  // 7. Notes Card (catatan Tambahan)
                  Card(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Catatan Tambahan', style: Theme.of(context).textTheme.titleMedium),
                          SizedBox(height: 8),
                          TextFormField(
                            controller: _notesController,
                            maxLines: 2,
                            decoration: InputDecoration(
                              hintText: 'Tulis noda membandel, sobekan, atau request khusus...',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: 24),

                  // Total & submit section
                  Container(
                    padding: EdgeInsets.all(20),
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
                               Text('Total Pembayaran', style: TextStyle(color: AppTheme.textGray, fontSize: 12)),
                              SizedBox(height: 4),
                              if (_voucherDiscount + (_usePointsRedemption && _selectedCustomerPoints >= 10 ? 25000 : 0.0) > 0) ...[
                                Text(
                                  'Rp ${(_itemsPrice + _deliveryFee).toStringAsFixed(0).replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (Match m) => "${m[1]}.")}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    decoration: TextDecoration.lineThrough,
                                    color: Colors.red,
                                  ),
                                ),
                                Text(
                                  'Diskon: -Rp ${(_voucherDiscount + (_usePointsRedemption && _selectedCustomerPoints >= 10 ? 25000 : 0.0)).toStringAsFixed(0).replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (Match m) => "${m[1]}.")}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.green,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                              Text(
                                'Rp ${_totalPrice.toStringAsFixed(0).replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (Match m) => "${m[1]}.")}',
                                style: TextStyle(
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
                            padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                          ),
                          child: _isSubmitting
                              ? SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                )
                              : Text('Buat Pesanan'),
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
