import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/service_model.dart';
import '../../services/database_service.dart';
import '../../theme.dart';

class ServiceCrudScreen extends StatefulWidget {
  final String categoryId;
  final String categoryName;
  const ServiceCrudScreen({
    Key? key,
    required this.categoryId,
    required this.categoryName,
  }) : super(key: key);

  @override
  State<ServiceCrudScreen> createState() => _ServiceCrudScreenState();
}

class _ServiceCrudScreenState extends State<ServiceCrudScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _descController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _descController.dispose();
    super.dispose();
  }

  void _showServiceDialog([ServiceModel? service]) {
    if (service != null) {
      _nameController.text = service.name;
      _priceController.text = service.price.toStringAsFixed(0);
      _descController.text = service.description;
    } else {
      _nameController.clear();
      _priceController.clear();
      _descController.clear();
    }

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(service == null ? 'Tambah Layanan' : 'Ubah Layanan'),
          content: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(hintText: 'Nama Layanan (Contoh: Deep Clean)'),
                    validator: (v) => v == null || v.isEmpty ? 'Nama wajib diisi' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _priceController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(hintText: 'Tarif / Harga (Rp)'),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Harga wajib diisi';
                      if (double.tryParse(v) == null) return 'Masukkan angka valid';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _descController,
                    maxLines: 2,
                    decoration: const InputDecoration(hintText: 'Deskripsi Singkat'),
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
                final name = _nameController.text;
                final price = double.parse(_priceController.text);
                final desc = _descController.text;

                if (service == null) {
                  // Add
                  await dbService.addService(
                    ServiceModel(
                      id: '',
                      name: name,
                      price: price,
                      description: desc,
                      categoryId: widget.categoryId,
                      categoryName: widget.categoryName,
                      isActive: true,
                      createdAt: DateTime.now(),
                    ),
                  );
                } else {
                  // Update
                  await dbService.updateService(
                    ServiceModel(
                      id: service.id,
                      name: name,
                      price: price,
                      description: desc,
                      categoryId: widget.categoryId,
                      categoryName: widget.categoryName,
                      isActive: service.isActive,
                      createdAt: service.createdAt,
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
  }

  void _confirmDelete(String serviceId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus Layanan?'),
        content: const Text('Apakah Anda yakin ingin menghapus layanan ini dari daftar?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal', style: TextStyle(color: AppTheme.textGray)),
          ),
          ElevatedButton(
            onPressed: () async {
              await Provider.of<DatabaseService>(context, listen: false).deleteService(serviceId);
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
        title: Text('Layanan ${widget.categoryName}'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showServiceDialog(),
        backgroundColor: AppTheme.primaryBlue,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: StreamBuilder<List<ServiceModel>>(
        stream: dbService.getServicesByCategory(widget.categoryId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Terjadi kesalahan: ${snapshot.error}'));
          }

          final services = snapshot.data ?? [];
          if (services.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.cleaning_services_outlined, size: 64, color: AppTheme.textGray),
                  const SizedBox(height: 16),
                  Text('Belum ada layanan ditambahkan', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  const Text('Klik tombol + di bawah untuk menambahkan', style: TextStyle(color: AppTheme.textGray)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: services.length,
            itemBuilder: (context, index) {
              final service = services[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      // Circular Icon background
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: (service.isActive ? AppTheme.primaryBlue : Colors.grey).withOpacity(0.08),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.local_laundry_service,
                          color: service.isActive ? AppTheme.primaryBlue : Colors.grey,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Text Info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    service.name,
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: service.isActive ? AppTheme.darkBlueText : Colors.grey,
                                        ),
                                  ),
                                ),
                                if (!service.isActive) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade100,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'Nonaktif',
                                      style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            if (service.description.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                service.description,
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: service.isActive ? Colors.black87 : Colors.grey,
                                    ),
                              ),
                            ],
                            const SizedBox(height: 8),
                            // Price Badge
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: (service.isActive ? AppTheme.secondaryBlue : Colors.grey).withOpacity(0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'Rp ${service.price.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.')}',
                                style: TextStyle(
                                  color: service.isActive ? AppTheme.primaryBlue : Colors.grey,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Actions (Switch for Active status, Edit, Delete)
                      Column(
                        children: [
                          Switch(
                            value: service.isActive,
                            onChanged: (value) async {
                              await dbService.toggleServiceActive(service.id, value);
                            },
                            activeColor: AppTheme.primaryBlue,
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined, color: AppTheme.primaryBlue, size: 20),
                                onPressed: () => _showServiceDialog(service),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                onPressed: () => _confirmDelete(service.id),
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
