import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/database_service.dart';
import '../../theme.dart';
import '../../widgets/watermark.dart';

class LogisticsCrudScreen extends StatefulWidget {
  final bool isTab;
  const LogisticsCrudScreen({Key? key, this.isTab = false}) : super(key: key);

  @override
  State<LogisticsCrudScreen> createState() => _LogisticsCrudScreenState();
}

class _LogisticsCrudScreenState extends State<LogisticsCrudScreen> {
  final _nameController = TextEditingController();
  final _feeController = TextEditingController();
  bool _requiresAddress = false;

  @override
  void dispose() {
    _nameController.dispose();
    _feeController.dispose();
    super.dispose();
  }

  void _showFormDialog({Map<String, dynamic>? method}) {
    final isEdit = method != null;
    final screenContext = context;
    
    if (isEdit) {
      _nameController.text = method['name'] ?? '';
      _feeController.text = (method['fee'] ?? 0.0).toStringAsFixed(0);
      _requiresAddress = method['requiresAddress'] ?? false;
    } else {
      _nameController.clear();
      _feeController.clear();
      _requiresAddress = false;
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: Text(isEdit ? 'Edit Metode Logistik' : 'Tambah Metode Logistik'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Nama Metode',
                        hintText: 'Contoh: Kurir Instan / COD',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _feeController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Tarif Flat (Rp)',
                        hintText: 'Contoh: 15000',
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Memerlukan Alamat', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      subtitle: const Text('Tampilkan input alamat saat customer memilih ini', style: TextStyle(fontSize: 11)),
                      value: _requiresAddress,
                      activeColor: AppTheme.primaryBlue,
                      onChanged: (val) {
                        setStateDialog(() {
                          _requiresAddress = val;
                        });
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
                    final name = _nameController.text.trim();
                    final fee = double.tryParse(_feeController.text.trim()) ?? 0.0;

                    if (name.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Nama metode tidak boleh kosong!')),
                      );
                      return;
                    }

                    try {
                      final dbService = Provider.of<DatabaseService>(screenContext, listen: false);
                      if (isEdit) {
                        await dbService.updateLogisticsMethod(method['id'], name, fee, _requiresAddress);
                      } else {
                        await dbService.addLogisticsMethod(name, fee, _requiresAddress);
                      }
                      if (context.mounted) Navigator.pop(context);
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Gagal menyimpan: $e')),
                        );
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryBlue),
                  child: const Text('Simpan', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _confirmDelete(String id, String name) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Hapus Metode Logistik'),
          content: Text('Apakah Anda yakin ingin menghapus metode "$name"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () async {
                final dbService = Provider.of<DatabaseService>(context, listen: false);
                await dbService.deleteLogisticsMethod(id);
                if (context.mounted) Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              child: const Text('Hapus', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final dbService = Provider.of<DatabaseService>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kelola Logistik & Tarif'),
        leading: widget.isTab
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: dbService.getLogisticsMethods(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final methods = snapshot.data ?? [];

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Daftar Metode Pengantaran',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.darkBlueText),
                ),
                const SizedBox(height: 12),
                if (methods.isEmpty)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 40.0),
                      child: Text('Belum ada metode pengantaran.', style: TextStyle(color: AppTheme.textGray)),
                    ),
                  )
                else
                  ...methods.map((method) {
                    final name = method['name'] ?? '';
                    final fee = (method['fee'] ?? 0.0) as double;
                    final requiresAddress = method['requiresAddress'] ?? false;
                    final id = method['id'] as String;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: AppTheme.cardShadow,
                        border: Border.all(color: AppTheme.lightGray),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: requiresAddress ? Colors.blue.withOpacity(0.1) : Colors.green.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              requiresAddress ? Icons.local_shipping_outlined : Icons.store_outlined,
                              color: requiresAddress ? Colors.blue : Colors.green,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.darkBlueText),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Tarif: Rp ${fee.toStringAsFixed(0).replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (Match m) => "${m[1]}.")}',
                                  style: const TextStyle(fontSize: 12, color: AppTheme.textGray),
                                ),
                                if (requiresAddress)
                                  Container(
                                    margin: const EdgeInsets.only(top: 4),
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'Butuh Alamat',
                                      style: TextStyle(fontSize: 9, color: Colors.blue, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, color: Colors.orange, size: 20),
                            onPressed: () => _showFormDialog(method: method),
                          ),
                          // Prevent deleting core built-in methods to avoid db breaking
                          if (id != 'drop_off_only' && id != 'pickup_delivery')
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                              onPressed: () => _confirmDelete(id, name),
                            ),
                        ],
                      ),
                    );
                  }).toList(),
                const SizedBox(height: 24),
                const Center(child: Watermark()),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showFormDialog(),
        backgroundColor: AppTheme.primaryBlue,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}
