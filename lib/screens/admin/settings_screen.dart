import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../theme.dart';
import '../../widgets/watermark.dart';
import 'staff_permissions_screen.dart';
import 'owner_billing_history_screen.dart';
import 'logistics_crud_screen.dart';
import 'category_crud_screen.dart';
import 'voucher_crud_screen.dart';

class AdminSettingsScreen extends StatefulWidget {
  const AdminSettingsScreen({Key? key}) : super(key: key);

  @override
  State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen> {
  final _shopNameController = TextEditingController();
  final _shopPhoneController = TextEditingController();
  
  bool _isLoading = false;
  Map<String, bool> _staffPerms = {};

  @override
  void initState() {
    super.initState();
    _loadShopConfig();
  }

  @override
  void dispose() {
    _shopNameController.dispose();
    _shopPhoneController.dispose();
    super.dispose();
  }

  Future<void> _loadShopConfig() async {
    setState(() => _isLoading = true);
    try {
      final doc = await FirebaseFirestore.instance.collection('app_config').doc('business_config').get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        _shopNameController.text = data['shopName'] ?? 'KickDirty';
        _shopPhoneController.text = data['shopPhone'] ?? '6281328580511';
      } else {
        _shopNameController.text = 'KickDirty';
        _shopPhoneController.text = '6281328580511';
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _saveShopConfig() async {
    final name = _shopNameController.text.trim();
    final phone = _shopPhoneController.text.trim();

    if (name.isEmpty || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nama Toko dan No. HP/WA Toko tidak boleh kosong!')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await FirebaseFirestore.instance.collection('app_config').doc('business_config').set({
        'shopName': name,
        'shopPhone': phone,
      }, SetOptions(merge: true));
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profil Toko berhasil disimpan!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menyimpan: $e')),
        );
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  bool _hasPerm(String key, String role) {
    if (role == 'owner' || role == 'developer') return true;
    return _staffPerms[key] == true;
  }

  @override
  Widget build(BuildContext context) {
    final role = Provider.of<AuthService>(context, listen: false).currentUserModel?.role ?? 'staff';

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('app_config').doc('staff_permissions').snapshots(),
      builder: (context, permSnapshot) {
        if (permSnapshot.hasData && permSnapshot.data!.exists) {
          _staffPerms = Map<String, bool>.from(
            (permSnapshot.data!.data() as Map<String, dynamic>? ?? {})
                .map((k, v) => MapEntry(k, v == true)),
          );
        }

        final showBusiness = _hasPerm('canAccessBusinessSettings', role);
        final showWA = _hasPerm('canAccessWhatsAppSettings', role);
        final showBot = _hasPerm('canAccessChatBotSettings', role);
        final showStaffPerms = role == 'owner' || role == 'developer';

        return Scaffold(
          appBar: AppBar(
            title: const Text('Pengaturan'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Section: Profil Toko
                      _buildSectionTitle('Profil Toko'),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppTheme.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: AppTheme.cardShadow,
                          border: Border.all(color: AppTheme.lightGray),
                        ),
                        child: Column(
                          children: [
                            TextField(
                              controller: _shopNameController,
                              decoration: const InputDecoration(
                                labelText: 'Nama Toko',
                                hintText: 'Contoh: KickDirty',
                                prefixIcon: Icon(Icons.store, color: AppTheme.primaryBlue),
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _shopPhoneController,
                              keyboardType: TextInputType.phone,
                              decoration: const InputDecoration(
                                labelText: 'No. HP/WA Toko',
                                hintText: 'Contoh: 6281328580511',
                                helperText: 'Gunakan kode negara (62...) tanpa tanda + atau spasi',
                                prefixIcon: Icon(Icons.phone, color: AppTheme.primaryBlue),
                              ),
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _saveShopConfig,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.primaryBlue,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                child: const Text('Simpan Profil Toko', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 24),
                      _buildSectionTitle('Konfigurasi & Sistem'),
                      const SizedBox(height: 12),

                      // Section: Config List
                      Container(
                        decoration: BoxDecoration(
                          color: AppTheme.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: AppTheme.cardShadow,
                          border: Border.all(color: AppTheme.lightGray),
                        ),
                        child: Column(
                          children: [
                            if (showBusiness) ...[
                              _buildSettingTile(
                                title: 'Poin & Ongkir',
                                subtitle: 'Atur poin loyalitas & tarif default',
                                icon: Icons.stars_outlined,
                                color: Colors.deepOrange,
                                onTap: () => _showBusinessSettingsDialog(context),
                              ),
                              const Divider(height: 1, indent: 56),
                              _buildSettingTile(
                                title: 'Kelola Kategori & Layanan',
                                subtitle: 'CRUD kategori & harga cuci jasa',
                                icon: Icons.category_outlined,
                                color: Colors.indigo,
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => const CategoryCrudScreen()),
                                  );
                                },
                              ),
                              const Divider(height: 1, indent: 56),
                              _buildSettingTile(
                                title: 'Kelola Voucher Diskon',
                                subtitle: 'CRUD voucher & potongan belanja',
                                icon: Icons.confirmation_number_outlined,
                                color: Colors.orange,
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => const VoucherCrudScreen()),
                                  );
                                },
                              ),
                              const Divider(height: 1, indent: 56),
                              _buildSettingTile(
                                title: 'Kelola Metode Logistik',
                                subtitle: 'CRUD pilihan & tarif pengiriman',
                                icon: Icons.local_shipping_outlined,
                                color: Colors.blue,
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => const LogisticsCrudScreen()),
                                  );
                                },
                              ),
                              const Divider(height: 1, indent: 56),
                            ],
                            if (showWA) ...[
                              _buildSettingTile(
                                title: 'Pengaturan WA Gateway',
                                subtitle: 'Fonnte / Wablas API Gateway integration',
                                icon: Icons.settings_phone,
                                color: Colors.teal,
                                onTap: () => _showWhatsAppSettingsDialog(context),
                              ),
                              const Divider(height: 1, indent: 56),
                            ],
                            if (showBot) ...[
                              _buildSettingTile(
                                title: 'Auto-Reply Chatbot',
                                subtitle: 'Balasan salam otomatis untuk pelanggan',
                                icon: Icons.android,
                                color: Colors.amber.shade700,
                                onTap: () => _showChatBotSettingsDialog(context),
                              ),
                              if (showStaffPerms) const Divider(height: 1, indent: 56),
                            ],
                            if (showStaffPerms) ...[
                              _buildSettingTile(
                                title: 'Hak Akses Staff',
                                subtitle: 'Kontrol fitur karyawan biasa (dinamis)',
                                icon: Icons.admin_panel_settings,
                                color: Colors.red,
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => const StaffPermissionsScreen()),
                                  );
                                },
                              ),
                              const Divider(height: 1, indent: 56),
                              _buildSettingTile(
                                title: 'Riwayat Billing Aplikasi',
                                subtitle: 'Riwayat pembayaran & bukti transfer bulanan',
                                icon: Icons.receipt_long,
                                color: Colors.purple,
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => const OwnerBillingHistoryScreen()),
                                  );
                                },
                              ),
                            ],
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 32),
                      const Center(child: Watermark()),
                    ],
                  ),
                ),
        );
      },
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.bold,
          color: AppTheme.darkBlueText,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildSettingTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 22),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.darkBlueText),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 11, color: AppTheme.textGray),
      ),
      trailing: const Icon(Icons.chevron_right, color: AppTheme.textGray, size: 18),
      onTap: onTap,
    );
  }

  // dialogs
  void _showWhatsAppSettingsDialog(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    Map<String, dynamic> data = {};
    try {
      final doc = await FirebaseFirestore.instance.collection('app_config').doc('whatsapp_config').get();
      if (doc.exists) {
        data = doc.data() ?? {};
      }
    } catch (_) {}

    if (mounted) Navigator.pop(context); // Close loading

    String provider = data['provider'] ?? 'manual';
    bool useAutomation = data['useAutomation'] ?? false;
    final tokenController = TextEditingController(text: data['apiToken'] ?? '');
    final urlController = TextEditingController(text: data['gatewayUrl'] ?? 'https://api.wablas.com');

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Pengaturan WA Gateway'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SwitchListTile(
                      title: const Text('Aktifkan Otomasi WA', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      subtitle: const Text('Kirim notifikasi & file PDF otomatis', style: TextStyle(fontSize: 11)),
                      value: useAutomation,
                      activeColor: AppTheme.primaryBlue,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (val) {
                        setStateDialog(() {
                          useAutomation = val;
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: provider,
                      decoration: const InputDecoration(labelText: 'Penyedia Gateway (Provider)'),
                      items: const [
                        DropdownMenuItem(value: 'manual', child: Text('Manual (Tautan WA)')),
                        DropdownMenuItem(value: 'fonnte', child: Text('Fonnte (Otomatis)')),
                        DropdownMenuItem(value: 'wablas', child: Text('Wablas (Otomatis)')),
                      ],
                      onChanged: (val) {
                        setStateDialog(() {
                          provider = val ?? 'manual';
                        });
                      },
                    ),
                    if (provider != 'manual') ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: tokenController,
                        decoration: const InputDecoration(
                          labelText: 'API Key / Token Otorisasi',
                          hintText: 'Masukkan token API gateway Anda',
                        ),
                      ),
                    ],
                    if (provider == 'wablas') ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: urlController,
                        decoration: const InputDecoration(
                          labelText: 'Wablas Domain URL',
                          hintText: 'https://api.wablas.com',
                        ),
                      ),
                    ],
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
                    await FirebaseFirestore.instance.collection('app_config').doc('whatsapp_config').set({
                      'provider': provider,
                      'useAutomation': useAutomation,
                      'apiToken': tokenController.text.trim(),
                      'gatewayUrl': urlController.text.trim(),
                    }, SetOptions(merge: true));
                    if (context.mounted) Navigator.pop(context);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Konfigurasi WhatsApp Gateway berhasil disimpan!')),
                      );
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

  void _showChatBotSettingsDialog(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    Map<String, dynamic> data = {};
    try {
      final doc = await FirebaseFirestore.instance.collection('app_config').doc('chat_config').get();
      if (doc.exists) {
        data = doc.data() ?? {};
      }
    } catch (_) {}

    if (mounted) Navigator.pop(context);

    bool autoReplyEnabled = data['autoReplyEnabled'] ?? false;
    final textController = TextEditingController(
      text: data['autoReplyText'] ??
          'Halo! Terima kasih telah menghubungi KickDirty. Pesan Anda telah kami terima dan akan segera kami balas. Jam Operasional: 09:00 - 21:00.',
    );

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Pengaturan Auto-Reply Chat'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SwitchListTile(
                      title: const Text('Aktifkan Pesan Otomatis', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      subtitle: const Text('Kirim salam otomatis ke pelanggan baru', style: TextStyle(fontSize: 11)),
                      value: autoReplyEnabled,
                      activeColor: AppTheme.primaryBlue,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (val) {
                        setStateDialog(() {
                          autoReplyEnabled = val;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: textController,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Isi Pesan Otomatis',
                        hintText: 'Tulis pesan balasan otomatis...',
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
                ElevatedButton(
                  onPressed: () async {
                    await FirebaseFirestore.instance.collection('app_config').doc('chat_config').set({
                      'autoReplyEnabled': autoReplyEnabled,
                      'autoReplyText': textController.text.trim(),
                    }, SetOptions(merge: true));
                    if (context.mounted) Navigator.pop(context);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Pengaturan Auto-Reply Chat berhasil disimpan!')),
                      );
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

  void _showBusinessSettingsDialog(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    Map<String, dynamic> data = {};
    try {
      final doc = await FirebaseFirestore.instance.collection('app_config').doc('business_config').get();
      if (doc.exists) {
        data = doc.data() ?? {};
      }
    } catch (_) {}

    if (mounted) Navigator.pop(context); // Close loading

    final deliveryFeeController = TextEditingController(text: (data['deliveryFee'] ?? 15000.0).toStringAsFixed(0));
    final rupiahPerPointController = TextEditingController(text: (data['rupiahPerPoint'] ?? 10000).toString());
    final pointsNeededController = TextEditingController(text: (data['pointsNeeded'] ?? 10).toString());
    final discountValueController = TextEditingController(text: (data['discountValue'] ?? 25000.0).toStringAsFixed(0));

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Pengaturan Poin & Ongkir'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: deliveryFeeController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Biaya Ongkir Kurir Flat (Rp)',
                    hintText: 'Contoh: 15000',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: rupiahPerPointController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Minimal Belanja per 1 Poin (Rp)',
                    hintText: 'Contoh: 10000',
                    helperText: 'Layanan jasa cuci saja, ongkir tidak dihitung poin',
                    helperMaxLines: 2,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: pointsNeededController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Poin untuk Klaim Diskon',
                    hintText: 'Contoh: 10',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: discountValueController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Nilai Diskon Potongan (Rp)',
                    hintText: 'Contoh: 25000',
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
            ElevatedButton(
              onPressed: () async {
                final double deliveryFee = double.tryParse(deliveryFeeController.text.trim()) ?? 15000.0;
                final int rupiahPerPoint = int.tryParse(rupiahPerPointController.text.trim()) ?? 10000;
                final int pointsNeeded = int.tryParse(pointsNeededController.text.trim()) ?? 10;
                final double discountValue = double.tryParse(discountValueController.text.trim()) ?? 25000.0;

                await FirebaseFirestore.instance.collection('app_config').doc('business_config').set({
                  'deliveryFee': deliveryFee,
                  'rupiahPerPoint': rupiahPerPoint,
                  'pointsNeeded': pointsNeeded,
                  'discountValue': discountValue,
                }, SetOptions(merge: true));

                if (context.mounted) Navigator.pop(context);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Konfigurasi Tarif & Poin berhasil disimpan!')),
                  );
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryBlue),
              child: const Text('Simpan', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }
}
