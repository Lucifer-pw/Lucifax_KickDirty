import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../models/voucher_model.dart';
import '../../services/database_service.dart';
import '../../theme.dart';

class VoucherCrudScreen extends StatefulWidget {
  const VoucherCrudScreen({Key? key}) : super(key: key);

  @override
  State<VoucherCrudScreen> createState() => _VoucherCrudScreenState();
}

class _VoucherCrudScreenState extends State<VoucherCrudScreen> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _valueController = TextEditingController();
  final _minOrderController = TextEditingController();
  final _maxDiscountController = TextEditingController();

  String _discountType = 'fixed'; // 'fixed' | 'percentage'
  DateTime? _validFrom;
  DateTime? _validTo;

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _descController.dispose();
    _valueController.dispose();
    _minOrderController.dispose();
    _maxDiscountController.dispose();
    super.dispose();
  }

  void _showVoucherDialog([VoucherModel? voucher]) {
    if (voucher != null) {
      _codeController.text = voucher.code;
      _nameController.text = voucher.name;
      _descController.text = voucher.description;
      _discountType = voucher.discountType;
      _valueController.text = voucher.discountValue.toStringAsFixed(0);
      _minOrderController.text = voucher.minOrder.toStringAsFixed(0);
      _maxDiscountController.text = voucher.maxDiscount.toStringAsFixed(0);
      _validFrom = voucher.validFrom;
      _validTo = voucher.validTo;
    } else {
      _codeController.clear();
      _nameController.clear();
      _descController.clear();
      _discountType = 'fixed';
      _valueController.clear();
      _minOrderController.clear();
      _maxDiscountController.clear();
      _validFrom = null;
      _validTo = null;
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(voucher == null ? 'Tambah Voucher Baru' : 'Ubah Voucher'),
              content: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: _codeController,
                        decoration: const InputDecoration(hintText: 'Kode Voucher (Contoh: HEMAT10K)'),
                        textCapitalization: TextCapitalization.characters,
                        validator: (v) => v == null || v.isEmpty ? 'Kode wajib diisi' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(hintText: 'Nama Voucher (Contoh: Diskon Grand Opening)'),
                        validator: (v) => v == null || v.isEmpty ? 'Nama wajib diisi' : null,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _discountType,
                        decoration: const InputDecoration(labelText: 'Tipe Diskon'),
                        items: const [
                          DropdownMenuItem(value: 'fixed', child: Text('Nominal Tetap (Rp)')),
                          DropdownMenuItem(value: 'percentage', child: Text('Persentase (%)')),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() {
                              _discountType = val;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _valueController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          hintText: _discountType == 'fixed' ? 'Nilai Potongan (Rp)' : 'Persentase Diskon (%)',
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Nilai wajib diisi';
                          if (double.tryParse(v) == null) return 'Masukkan angka valid';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _minOrderController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(hintText: 'Minimal Belanja (Rp) - Opsional'),
                      ),
                      if (_discountType == 'percentage') ...[
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _maxDiscountController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(hintText: 'Maksimal Diskon (Rp) - Opsional'),
                        ),
                      ],
                      const SizedBox(height: 16),
                      // Date range selectors
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () async {
                                final d = await showDatePicker(
                                  context: context,
                                  initialDate: _validFrom ?? DateTime.now(),
                                  firstDate: DateTime(2025),
                                  lastDate: DateTime(2030),
                                );
                                if (d != null) {
                                  setDialogState(() {
                                    _validFrom = d;
                                  });
                                }
                              },
                              child: Text(_validFrom == null
                                  ? 'Mulai'
                                  : DateFormat('dd/MM/yy').format(_validFrom!)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () async {
                                final d = await showDatePicker(
                                  context: context,
                                  initialDate: _validTo ?? DateTime.now().add(const Duration(days: 7)),
                                  firstDate: DateTime(2025),
                                  lastDate: DateTime(2030),
                                );
                                if (d != null) {
                                  setDialogState(() {
                                    _validTo = d;
                                  });
                                }
                              },
                              child: Text(_validTo == null
                                  ? 'Berakhir'
                                  : DateFormat('dd/MM/yy').format(_validTo!)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Batal', style: TextStyle(color: AppTheme.textGray)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (!_formKey.currentState!.validate()) return;

                    final dbService = Provider.of<DatabaseService>(context, listen: false);
                    final code = _codeController.text.toUpperCase().trim();
                    final name = _nameController.text;
                    final desc = _descController.text;
                    final val = double.parse(_valueController.text);
                    final minOrder = double.tryParse(_minOrderController.text) ?? 0.0;
                    final maxDisc = double.tryParse(_maxDiscountController.text) ?? 0.0;

                    if (voucher == null) {
                      await dbService.addVoucher(
                        VoucherModel(
                          id: '',
                          code: code,
                          name: name,
                          description: desc,
                          discountType: _discountType,
                          discountValue: val,
                          minOrder: minOrder,
                          maxDiscount: maxDisc,
                          isActive: true,
                          validFrom: _validFrom,
                          validTo: _validTo,
                          createdAt: DateTime.now(),
                        ),
                      );
                    } else {
                      await dbService.updateVoucher(
                        VoucherModel(
                          id: voucher.id,
                          code: code,
                          name: name,
                          description: desc,
                          discountType: _discountType,
                          discountValue: val,
                          minOrder: minOrder,
                          maxDiscount: maxDisc,
                          isActive: voucher.isActive,
                          validFrom: _validFrom,
                          validTo: _validTo,
                          createdAt: voucher.createdAt,
                        ),
                      );
                    }

                    if (mounted) Navigator.pop(context);
                  },
                  child: const Text('Simpan'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _confirmDelete(String voucherId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus Voucher?'),
        content: const Text('Apakah Anda yakin ingin menghapus voucher ini?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal', style: TextStyle(color: AppTheme.textGray)),
          ),
          ElevatedButton(
            onPressed: () async {
              await Provider.of<DatabaseService>(context, listen: false).deleteVoucher(voucherId);
              if (mounted) Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dbService = Provider.of<DatabaseService>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kelola Voucher'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showVoucherDialog(),
        backgroundColor: AppTheme.primaryBlue,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: StreamBuilder<List<VoucherModel>>(
        stream: dbService.getVouchers(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Terjadi kesalahan: ${snapshot.error}'));
          }

          final vouchers = snapshot.data ?? [];
          if (vouchers.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.confirmation_num_outlined, size: 64, color: AppTheme.textGray),
                  const SizedBox(height: 16),
                  Text('Belum ada voucher dibuat', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  const Text('Klik + untuk membuat voucher diskon baru', style: TextStyle(color: AppTheme.textGray)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: vouchers.length,
            itemBuilder: (context, index) {
              final v = vouchers[index];
              final dateStr = (v.validFrom != null && v.validTo != null)
                  ? '${DateFormat('dd/MM/yy').format(v.validFrom!)} - ${DateFormat('dd/MM/yy').format(v.validTo!)}'
                  : 'Berlaku Selamanya';

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: (v.isActive ? AppTheme.primaryBlue : Colors.grey).withOpacity(0.08),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.confirmation_number,
                          color: v.isActive ? AppTheme.primaryBlue : Colors.grey,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: (v.isActive ? AppTheme.primaryBlue : Colors.grey).withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    v.code,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: v.isActive ? AppTheme.primaryBlue : Colors.grey,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    v.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: v.isActive ? AppTheme.darkBlueText : Colors.grey,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              v.discountType == 'percentage'
                                  ? 'Diskon ${v.discountValue.toStringAsFixed(0)}%'
                                  : 'Diskon Rp ${v.discountValue.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.')}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: v.isActive ? Colors.green : Colors.grey,
                                fontSize: 13,
                              ),
                            ),
                            if (v.minOrder > 0) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Min. belanja Rp ${v.minOrder.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.')}',
                                style: const TextStyle(fontSize: 11, color: AppTheme.textGray),
                              ),
                            ],
                            const SizedBox(height: 4),
                            Text(
                              'Periode: $dateStr',
                              style: const TextStyle(fontSize: 11, color: AppTheme.textGray),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        children: [
                          Switch(
                            value: v.isActive,
                            onChanged: (val) async {
                              await dbService.toggleVoucherActive(v.id, val);
                            },
                            activeColor: AppTheme.primaryBlue,
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined, color: AppTheme.primaryBlue, size: 20),
                                onPressed: () => _showVoucherDialog(v),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                onPressed: () => _confirmDelete(v.id),
                              ),
                            ],
                          ),
                        ],
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
