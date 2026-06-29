import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/category_model.dart';
import '../../services/database_service.dart';
import '../../theme.dart';
import 'service_crud_screen.dart';

class CategoryCrudScreen extends StatefulWidget {
  const CategoryCrudScreen({Key? key}) : super(key: key);

  @override
  State<CategoryCrudScreen> createState() => _CategoryCrudScreenState();
}

class _CategoryCrudScreenState extends State<CategoryCrudScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  void _showCategoryDialog([CategoryModel? category]) {
    if (category != null) {
      _nameController.text = category.name;
      _descController.text = category.description;
    } else {
      _nameController.clear();
      _descController.clear();
    }

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(category == null ? 'Tambah Kategori Jasa' : 'Ubah Kategori Jasa'),
          content: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(hintText: 'Nama Kategori (Contoh: Sepatu, Tas, Helm)'),
                    validator: (v) => v == null || v.isEmpty ? 'Nama wajib diisi' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _descController,
                    maxLines: 2,
                    decoration: const InputDecoration(hintText: 'Deskripsi Kategori'),
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
                final desc = _descController.text;

                if (category == null) {
                  await dbService.addCategory(
                    CategoryModel(
                      id: '',
                      name: name,
                      description: desc,
                      isActive: true,
                      createdAt: DateTime.now(),
                    ),
                  );
                } else {
                  await dbService.updateCategory(
                    CategoryModel(
                      id: category.id,
                      name: name,
                      description: desc,
                      isActive: category.isActive,
                      createdAt: category.createdAt,
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

  void _confirmDelete(CategoryModel category) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus Kategori?'),
        content: Text('Apakah Anda yakin ingin menghapus kategori "${category.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal', style: TextStyle(color: AppTheme.textGray)),
          ),
          ElevatedButton(
            onPressed: () async {
              final dbService = Provider.of<DatabaseService>(context, listen: false);
              final success = await dbService.deleteCategory(category.id);
              if (mounted) {
                Navigator.pop(context);
                if (!success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Gagal menghapus! Kategori masih memiliki layanan aktif.')),
                  );
                }
              }
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
        title: const Text('Kelola Kategori Jasa'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCategoryDialog(),
        backgroundColor: AppTheme.primaryBlue,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: StreamBuilder<List<CategoryModel>>(
        stream: dbService.getCategories(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Terjadi kesalahan: ${snapshot.error}'));
          }

          final categories = snapshot.data ?? [];
          if (categories.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.category_outlined, size: 64, color: AppTheme.textGray),
                  const SizedBox(height: 16),
                  Text('Belum ada kategori jasa', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  const Text('Klik + untuk menambahkan kategori baru', style: TextStyle(color: AppTheme.textGray)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final cat = categories[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ServiceCrudScreen(
                          categoryId: cat.id,
                          categoryName: cat.name,
                        ),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: (cat.isActive ? AppTheme.primaryBlue : Colors.grey).withOpacity(0.08),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.category,
                            color: cat.isActive ? AppTheme.primaryBlue : Colors.grey,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                cat.name,
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: cat.isActive ? AppTheme.darkBlueText : Colors.grey,
                                    ),
                              ),
                              if (cat.description.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  cat.description,
                                  style: TextStyle(
                                    color: cat.isActive ? Colors.black87 : Colors.grey,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          children: [
                            Switch(
                              value: cat.isActive,
                              onChanged: (val) async {
                                await dbService.toggleCategoryActive(cat.id, val);
                              },
                              activeColor: AppTheme.primaryBlue,
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined, color: AppTheme.primaryBlue, size: 20),
                                  onPressed: () => _showCategoryDialog(cat),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                  onPressed: () => _confirmDelete(cat),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
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
