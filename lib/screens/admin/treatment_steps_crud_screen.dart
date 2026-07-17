import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../theme.dart';
import '../../widgets/watermark.dart';

class TreatmentStepsCrudScreen extends StatefulWidget {
  const TreatmentStepsCrudScreen({Key? key}) : super(key: key);

  @override
  State<TreatmentStepsCrudScreen> createState() => _TreatmentStepsCrudScreenState();
}

class _TreatmentStepsCrudScreenState extends State<TreatmentStepsCrudScreen> {
  final _stepNumberController = TextEditingController();
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _orderController = TextEditingController();
  String _selectedIcon = 'search';

  final List<Map<String, dynamic>> _iconPresets = [
    {'name': 'search', 'icon': Icons.search, 'label': 'Cari / Analisis'},
    {'name': 'clean_hands', 'icon': Icons.clean_hands_outlined, 'label': 'Cuci Tangan / Deep Clean'},
    {'name': 'sunny', 'icon': Icons.wb_sunny_outlined, 'label': 'Matahari / Pengeringan'},
    {'name': 'spa', 'icon': Icons.spa_outlined, 'label': 'Daun / Desinfektan'},
    {'name': 'verified', 'icon': Icons.verified_outlined, 'label': 'Verified / QC'},
    {'name': 'water', 'icon': Icons.water_drop_outlined, 'label': 'Air'},
    {'name': 'brush', 'icon': Icons.brush_outlined, 'label': 'Sikat'},
    {'name': 'info', 'icon': Icons.info_outline, 'label': 'Info'},
  ];

  @override
  void dispose() {
    _stepNumberController.dispose();
    _titleController.dispose();
    _descController.dispose();
    _orderController.dispose();
    super.dispose();
  }

  // Seed default steps if collection is empty
  Future<void> _seedDefaultSteps() async {
    final query = await FirebaseFirestore.instance.collection('treatment_steps').get();
    if (query.docs.isEmpty) {
      final defaults = [
        {
          'stepNumber': '1',
          'title': 'Penerimaan & Analisis',
          'desc': 'Sepatu diperiksa secara menyeluruh untuk noda, bahan, dan potensi resiko sebelum mulai dicuci.',
          'iconName': 'search',
          'order': 1,
        },
        {
          'stepNumber': '2',
          'title': 'Pembersihan Deep Clean',
          'desc': 'Menggunakan pembersih premium khusus (shoes cleaner) & sikat khusus sesuai jenis bahan sepatu.',
          'iconName': 'clean_hands',
          'order': 2,
        },
        {
          'stepNumber': '3',
          'title': 'Pengeringan Alami',
          'desc': 'Sepatu dikeringkan secara perlahan di ruang khusus bersuhu stabil agar lem & material tetap awet.',
          'iconName': 'sunny',
          'order': 3,
        },
        {
          'stepNumber': '4',
          'title': 'Detoks & Desinfektan',
          'desc': 'Pemberian semprotan anti-bakteri, anti-jamur, serta pewangi sepatu parfum premium agar segar kembali.',
          'iconName': 'spa',
          'order': 4,
        },
        {
          'stepNumber': '5',
          'title': 'Quality Control & Packing',
          'desc': 'Pemeriksaan akhir kesempurnaan hasil laundry sebelum sepatu dikemas rapi & siap diambil.',
          'iconName': 'verified',
          'order': 5,
        },
      ];
      for (var step in defaults) {
        await FirebaseFirestore.instance.collection('treatment_steps').add(step);
      }
    }
  }

  IconData _getIconData(String name) {
    final match = _iconPresets.firstWhere(
      (item) => item['name'] == name,
      orElse: () => _iconPresets.first,
    );
    return match['icon'] as IconData;
  }

  void _showFormDialog({Map<String, dynamic>? step, String? docId}) {
    final isEdit = step != null;
    if (isEdit) {
      _stepNumberController.text = step['stepNumber'] ?? '';
      _titleController.text = step['title'] ?? '';
      _descController.text = step['desc'] ?? '';
      _orderController.text = (step['order'] ?? 0).toString();
      _selectedIcon = step['iconName'] ?? 'search';
    } else {
      _stepNumberController.clear();
      _titleController.clear();
      _descController.clear();
      _orderController.clear();
      _selectedIcon = 'search';
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: AppTheme.white,
              title: Text(
                isEdit ? 'Edit Langkah Perawatan' : 'Tambah Langkah Perawatan',
                style: TextStyle(color: AppTheme.darkBlueText, fontWeight: FontWeight.bold, fontSize: 16),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: _stepNumberController,
                      decoration: InputDecoration(
                        labelText: 'Nomor Langkah',
                        hintText: 'Contoh: 1',
                        labelStyle: TextStyle(color: AppTheme.textGray),
                      ),
                      style: TextStyle(color: AppTheme.darkBlueText),
                    ),
                    SizedBox(height: 12),
                    TextField(
                      controller: _titleController,
                      decoration: InputDecoration(
                        labelText: 'Judul Langkah',
                        hintText: 'Contoh: Penerimaan & Analisis',
                        labelStyle: TextStyle(color: AppTheme.textGray),
                      ),
                      style: TextStyle(color: AppTheme.darkBlueText),
                    ),
                    SizedBox(height: 12),
                    TextField(
                      controller: _descController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: 'Deskripsi',
                        hintText: 'Contoh: Sepatu diperiksa...',
                        labelStyle: TextStyle(color: AppTheme.textGray),
                      ),
                      style: TextStyle(color: AppTheme.darkBlueText),
                    ),
                    SizedBox(height: 12),
                    TextField(
                      controller: _orderController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Urutan Tampilan',
                        hintText: 'Contoh: 1',
                        labelStyle: TextStyle(color: AppTheme.textGray),
                      ),
                      style: TextStyle(color: AppTheme.darkBlueText),
                    ),
                    SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      dropdownColor: AppTheme.white,
                      value: _selectedIcon,
                      decoration: InputDecoration(
                        labelText: 'Pilih Ikon',
                        labelStyle: TextStyle(color: AppTheme.textGray),
                      ),
                      items: _iconPresets.map((item) {
                        return DropdownMenuItem<String>(
                          value: item['name'] as String,
                          child: Row(
                            children: [
                              Icon(item['icon'] as IconData, color: AppTheme.primaryBlue, size: 20),
                              SizedBox(width: 8),
                              Text(item['label'] as String, style: TextStyle(color: AppTheme.darkBlueText, fontSize: 13)),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setStateDialog(() {
                            _selectedIcon = val;
                          });
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Batal', style: TextStyle(color: AppTheme.textGray)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final stepNumber = _stepNumberController.text.trim();
                    final title = _titleController.text.trim();
                    final desc = _descController.text.trim();
                    final order = int.tryParse(_orderController.text.trim()) ?? 0;

                    if (stepNumber.isEmpty || title.isEmpty || desc.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Semua field wajib diisi!')),
                      );
                      return;
                    }

                    try {
                      final data = {
                        'stepNumber': stepNumber,
                        'title': title,
                        'desc': desc,
                        'order': order,
                        'iconName': _selectedIcon,
                      };

                      if (isEdit && docId != null) {
                        await FirebaseFirestore.instance.collection('treatment_steps').doc(docId).update(data);
                      } else {
                        await FirebaseFirestore.instance.collection('treatment_steps').add(data);
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
                  child: Text('Simpan', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _confirmDelete(String docId, String title) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppTheme.white,
          title: Text('Hapus Langkah', style: TextStyle(color: AppTheme.darkBlueText, fontWeight: FontWeight.bold, fontSize: 16)),
          content: Text('Apakah Anda yakin ingin menghapus langkah "$title"?', style: TextStyle(color: AppTheme.darkBlueText)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Batal', style: TextStyle(color: AppTheme.textGray)),
            ),
            ElevatedButton(
              onPressed: () async {
                try {
                  await FirebaseFirestore.instance.collection('treatment_steps').doc(docId).delete();
                  if (context.mounted) Navigator.pop(context);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Gagal menghapus: $e')),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              child: Text('Hapus', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    _seedDefaultSteps();

    return Scaffold(
      backgroundColor: AppTheme.isDarkMode ? Colors.grey[900] : Colors.grey[50],
      appBar: AppBar(
        title: Text('Kelola Langkah Perawatan'),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('treatment_steps').orderBy('order').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Text(
                      'Belum ada langkah perawatan.\nKlik ikon + untuk menambah.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.textGray),
                    ),
                  );
                }

                final docs = snapshot.data!.docs;

                return ListView.builder(
                  padding: EdgeInsets.all(16),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final stepNumber = data['stepNumber'] ?? '';
                    final title = data['title'] ?? '';
                    final desc = data['desc'] ?? '';
                    final iconName = data['iconName'] ?? 'search';
                    final order = data['order'] ?? 0;

                    return Card(
                      color: AppTheme.white,
                      margin: EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      elevation: 0,
                      child: ListTile(
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        leading: CircleAvatar(
                          backgroundColor: AppTheme.primaryBlue.withOpacity(0.1),
                          child: Icon(_getIconData(iconName), color: AppTheme.primaryBlue, size: 20),
                        ),
                        title: Text(
                          'Langkah $stepNumber: $title (Urutan: $order)',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.darkBlueText),
                        ),
                        subtitle: Padding(
                          padding: EdgeInsets.only(top: 4.0),
                          child: Text(
                            desc,
                            style: TextStyle(fontSize: 12, color: AppTheme.textGray, height: 1.3),
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(Icons.edit_outlined, color: AppTheme.primaryBlue, size: 20),
                              onPressed: () => _showFormDialog(step: data, docId: doc.id),
                            ),
                            IconButton(
                              icon: Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                              onPressed: () => _confirmDelete(doc.id, title),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Center(child: Watermark()),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showFormDialog(),
        backgroundColor: AppTheme.primaryBlue,
        child: Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}
