import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../theme.dart';
import '../../widgets/watermark.dart';

class FaqCrudScreen extends StatefulWidget {
  const FaqCrudScreen({Key? key}) : super(key: key);

  @override
  State<FaqCrudScreen> createState() => _FaqCrudScreenState();
}

class _FaqCrudScreenState extends State<FaqCrudScreen> {
  final _questionController = TextEditingController();
  final _answerController = TextEditingController();
  final _orderController = TextEditingController();

  @override
  void dispose() {
    _questionController.dispose();
    _answerController.dispose();
    _orderController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _seedDefaultFaqs();
  }

  // Seed default FAQs if empty
  Future<void> _seedDefaultFaqs() async {
    final query = await FirebaseFirestore.instance.collection('faqs').get();
    if (query.docs.isEmpty) {
      final defaults = [
        {
          'question': 'Berapa lama pengerjaan cuci sepatu?',
          'answer': 'Durasi pengerjaan standar adalah 2 hingga 3 hari kerja tergantung pada tingkat kekotoran dan jenis perawatan yang dipilih. Tersedia juga layanan Express (1 hari selesai) dengan tambahan biaya.',
          'order': 1,
        },
        {
          'question': 'Apakah aman untuk sepatu suede / nubuck?',
          'answer': 'Sangat aman. Kami menggunakan cairan pembersih khusus (suede cleaner) serta sikat khusus (horsehair brush) yang lembut untuk merawat material sensitif agar tekstur tidak rusak.',
          'order': 2,
        },
        {
          'question': 'Apakah ada garansi jika kurang bersih?',
          'answer': 'Ya! Kami memberikan garansi cuci ulang gratis 100% jika Anda merasa hasil pengerjaan kami kurang bersih. Cukup laporkan dalam waktu 24 jam setelah sepatu Anda terima.',
          'order': 3,
        },
        {
          'question': 'Bagaimana cara memesan layanan?',
          'answer': 'Sangat mudah! Daftar akun di web ini, lalu klik tombol "Pesan" pada jenis layanan yang Anda inginkan, masukkan detail pesanan, pilih logistik antar-jemput, dan selesiakan pembayaran.',
          'order': 4,
        },
      ];
      for (var faq in defaults) {
        await FirebaseFirestore.instance.collection('faqs').add(faq);
      }
    }
  }

  void _showFormDialog({Map<String, dynamic>? faq, String? docId}) {
    final isEdit = faq != null;
    if (isEdit) {
      _questionController.text = faq['question'] ?? '';
      _answerController.text = faq['answer'] ?? '';
      _orderController.text = (faq['order'] ?? 0).toString();
    } else {
      _questionController.clear();
      _answerController.clear();
      _orderController.clear();
    }

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppTheme.white,
          title: Text(
            isEdit ? 'Edit FAQ' : 'Tambah FAQ',
            style: TextStyle(color: AppTheme.darkBlueText, fontWeight: FontWeight.bold, fontSize: 16),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _questionController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'Pertanyaan',
                    hintText: 'Contoh: Berapa lama pengerjaan?',
                    labelStyle: TextStyle(color: AppTheme.textGray),
                  ),
                  style: TextStyle(color: AppTheme.darkBlueText),
                ),
                SizedBox(height: 12),
                TextField(
                  controller: _answerController,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: 'Jawaban',
                    hintText: 'Contoh: Durasi pengerjaan adalah...',
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
                final question = _questionController.text.trim();
                final answer = _answerController.text.trim();
                final order = int.tryParse(_orderController.text.trim()) ?? 0;

                if (question.isEmpty || answer.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Semua field wajib diisi!')),
                  );
                  return;
                }

                try {
                  final data = {
                    'question': question,
                    'answer': answer,
                    'order': order,
                  };

                  if (isEdit && docId != null) {
                    await FirebaseFirestore.instance.collection('faqs').doc(docId).update(data);
                  } else {
                    await FirebaseFirestore.instance.collection('faqs').add(data);
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
  }

  void _confirmDelete(String docId, String question) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppTheme.white,
          title: Text('Hapus FAQ', style: TextStyle(color: AppTheme.darkBlueText, fontWeight: FontWeight.bold, fontSize: 16)),
          content: Text('Apakah Anda yakin ingin menghapus FAQ "$question"?', style: TextStyle(color: AppTheme.darkBlueText)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Batal', style: TextStyle(color: AppTheme.textGray)),
            ),
            ElevatedButton(
              onPressed: () async {
                try {
                  await FirebaseFirestore.instance.collection('faqs').doc(docId).delete();
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

    return Scaffold(
      backgroundColor: AppTheme.isDarkMode ? Colors.grey[900] : Colors.grey[50],
      appBar: AppBar(
        title: Text('Kelola Tanya Jawab (FAQ)'),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('faqs').orderBy('order').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Text(
                      'Belum ada daftar FAQ.\nKlik ikon + untuk menambah.',
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
                    final question = data['question'] ?? '';
                    final answer = data['answer'] ?? '';
                    final order = data['order'] ?? 0;

                    return Card(
                      color: AppTheme.white,
                      margin: EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      elevation: 0,
                      child: ListTile(
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        title: Text(
                          '$question (Urutan: $order)',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.darkBlueText),
                        ),
                        subtitle: Padding(
                          padding: EdgeInsets.only(top: 6.0),
                          child: Text(
                            answer,
                            style: TextStyle(fontSize: 12, color: AppTheme.textGray, height: 1.3),
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(Icons.edit_outlined, color: AppTheme.primaryBlue, size: 20),
                              onPressed: () => _showFormDialog(faq: data, docId: doc.id),
                            ),
                            IconButton(
                              icon: Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                              onPressed: () => _confirmDelete(doc.id, question),
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
