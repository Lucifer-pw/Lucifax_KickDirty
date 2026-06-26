import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/order_model.dart';
import '../../models/service_model.dart';
import '../../services/database_service.dart';
import '../../theme.dart';

class InputOrderScreen extends StatefulWidget {
  const InputOrderScreen({Key? key}) : super(key: key);

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

  double get _totalPrice => _items.fold(0, (sum, item) => sum + item.price);

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
                  Navigator.pop(context); // Go back to admin panel
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
                Navigator.pop(context); // Go back to admin panel
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
        customerId: '', // Optionally linked
        items: _items,
        totalAmount: _totalPrice,
        status: 'diterima',
        paymentStatus: 'belum_bayar',
        qrisImage: 'assets/qris_pembayaran.jpeg',
        notes: _notesController.text.trim(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Save order (idempotency token protects against duplicates)
      String finalInvoiceId = await dbService.addOrder(order);

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
                            decoration: const InputDecoration(
                              hintText: 'Nama Pelanggan',
                              prefixIcon: Icon(Icons.person_outline),
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
