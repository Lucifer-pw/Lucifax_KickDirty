import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../utils/printer/printer_service.dart';
import '../../theme.dart';

class PrinterSettingsScreen extends StatefulWidget {
  final String? role;
  const PrinterSettingsScreen({Key? key, this.role}) : super(key: key);

  @override
  State<PrinterSettingsScreen> createState() => _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends State<PrinterSettingsScreen> {
  List<BluetoothPrinterDevice> _devices = [];
  bool _isLoading = false;
  String? _connectedAddress;
  bool _isSupported = true;

  @override
  void initState() {
    super.initState();
    _checkSupportAndLoad();
  }

  Future<void> _checkSupportAndLoad() async {
    setState(() => _isLoading = true);
    final supported = await PrinterService.instance.isBluetoothSupported();
    setState(() => _isSupported = supported);
    
    if (supported) {
      await _loadDevices();
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadDevices() async {
    setState(() => _isLoading = true);
    final devices = await PrinterService.instance.getPairedDevices();
    final connectedAddress = await PrinterService.instance.getConnectedAddress();
    final isConnected = await PrinterService.instance.isConnected();

    setState(() {
      _devices = devices;
      _connectedAddress = isConnected ? connectedAddress : null;
      _isLoading = false;
    });
  }

  Future<void> _connectDevice(String address) async {
    setState(() => _isLoading = true);
    final success = await PrinterService.instance.connect(address);
    setState(() => _isLoading = false);

    if (mounted) {
      if (success) {
        setState(() => _connectedAddress = address);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Printer thermal berhasil terhubung!')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal menghubungkan printer. Pastikan printer menyala.')),
        );
      }
    }
  }

  Future<void> _disconnectDevice() async {
    setState(() => _isLoading = true);
    await PrinterService.instance.disconnect();
    setState(() {
      _connectedAddress = null;
      _isLoading = false;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Printer terputus.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.white,
      appBar: AppBar(
        backgroundColor: AppTheme.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppTheme.darkBlueText),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Pengaturan Printer',
          style: TextStyle(color: AppTheme.darkBlueText, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.help_outline, color: AppTheme.primaryBlue),
            tooltip: 'Panduan Koneksi',
            onPressed: _showPrinterGuideDialog,
          ),
          if (_isSupported)
            IconButton(
              icon: Icon(Icons.refresh, color: AppTheme.primaryBlue),
              onPressed: _loadDevices,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : !_isSupported
              ? _buildUnsupportedWidget()
              : _devices.isEmpty
                  ? _buildEmptyWidget()
                  : _buildDeviceList(),
    );
  }

  Widget _buildUnsupportedWidget() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bluetooth_disabled, size: 64, color: AppTheme.textGray),
            const SizedBox(height: 16),
            Text(
              'Bluetooth Tidak Didukung',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.darkBlueText),
            ),
            const SizedBox(height: 8),
            Text(
              'Pencarian printer bluetooth thermal langsung hanya tersedia pada aplikasi HP Android (APK).\n\nUntuk pencetakan via Web, gunakan opsi pencetakan sistem/RawBT saat mencetak.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppTheme.textGray, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyWidget() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.print_disabled, size: 64, color: AppTheme.textGray),
            const SizedBox(height: 16),
            Text(
              'Tidak Ada Printer Berpasangan',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.darkBlueText),
            ),
            const SizedBox(height: 8),
            Text(
              'Pastikan Anda sudah memasangkan (pair) printer bluetooth Anda di menu Pengaturan Bluetooth HP Anda terlebih dahulu.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppTheme.textGray, height: 1.5),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: _loadDevices,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Segarkan'),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: _showPrinterGuideDialog,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primaryBlue,
                    side: BorderSide(color: AppTheme.primaryBlue),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Lihat Panduan'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceList() {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _devices.length,
            itemBuilder: (context, index) {
              final device = _devices[index];
              final isConnected = _connectedAddress == device.address;

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                elevation: 2,
                shadowColor: Colors.black.withOpacity(0.2),
                color: AppTheme.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: isConnected ? Colors.green.withOpacity(0.5) : AppTheme.lightGray,
                    width: isConnected ? 1.5 : 1,
                  ),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: Icon(
                    Icons.print,
                    color: isConnected ? Colors.green : AppTheme.textGray,
                    size: 28,
                  ),
                  title: Text(
                    device.name,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: AppTheme.darkBlueText,
                    ),
                  ),
                  subtitle: Text(
                    device.address,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.textGray,
                    ),
                  ),
                  trailing: SizedBox(
                    width: 100,
                    child: ElevatedButton(
                      onPressed: () {
                        if (isConnected) {
                          _disconnectDevice();
                        } else {
                          _connectDevice(device.address);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isConnected ? Colors.green : const Color(0xFFFF5722),
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                        isConnected ? 'Putus' : 'Hubung',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppTheme.white,
            border: Border(top: BorderSide(color: AppTheme.lightGray)),
          ),
          child: OutlinedButton.icon(
            onPressed: _showPrinterGuideDialog,
            icon: const Icon(Icons.help_outline),
            label: const Text('Bantuan: Cara Menghubungkan Printer Bluetooth'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.primaryBlue,
              side: BorderSide(color: AppTheme.primaryBlue),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
  }

  // --- Dynamic Printer Connection Guide ---
  static const List<String> defaultAndroidSteps = [
    'Nyalakan Bluetooth & Printer Thermal Anda.',
    'Buka Pengaturan HP -> Bluetooth, lalu pasangkan (pair) printer bluetooth Anda (biasanya nama printer: MPT-II, RPP02N, dll. PIN pairing: 0000 atau 1234).',
    'Unduh aplikasi Print Service di Google Play Store (Rekomendasi: ESC/POS Wi-Fi/BlueTooth Print Service atau RawBT).',
    'Buka aplikasi print service tersebut, lalu hubungkan (bind) dengan printer Bluetooth yang sudah dipasangkan.',
    'Aktifkan Print Service tersebut di HP Anda melalui menu Pengaturan HP -> Koneksi & Berbagi -> Pencetakan (Printing) -> aktifkan print service yang diunduh.',
    'Kembali ke aplikasi KickDirty, klik "Cetak" -> pilih "Format Thermal (58mm)" -> pilih printer service yang tadi diaktifkan -> klik ikon Print.',
  ];

  static const List<String> defaultIosSteps = [
    'Pastikan Printer Thermal Anda mendukung koneksi Bluetooth iOS.',
    'Nyalakan Bluetooth HP dan pasangkan printer thermal Anda di Pengaturan iOS.',
    'Unduh aplikasi pihak ketiga pencetakan di App Store seperti MobiPrint atau Bluetooth Print.',
    'Gunakan opsi "Kirim PDF" atau "Share" di riwayat pesanan KickDirty, lalu kirim ke aplikasi print helper tersebut untuk dicetak secara langsung.',
    'Atau jika printer mendukung AirPrint, Anda bisa langsung memilih printer dari daftar printer iOS saat menekan opsi Cetak Thermal.',
  ];

  void _showPrinterGuideDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('app_config').doc('printer_guide').snapshots(),
          builder: (context, snapshot) {
            List<String> androidSteps = defaultAndroidSteps;
            List<String> iosSteps = defaultIosSteps;

            if (snapshot.hasData && snapshot.data!.exists) {
              final data = snapshot.data!.data() as Map<String, dynamic>?;
              if (data != null) {
                if (data['androidSteps'] != null) {
                  androidSteps = List<String>.from(data['androidSteps']);
                }
                if (data['iosSteps'] != null) {
                  iosSteps = List<String>.from(data['iosSteps']);
                }
              }
            }

            return DefaultTabController(
              length: 2,
              child: AlertDialog(
                backgroundColor: AppTheme.white,
                title: Row(
                  children: [
                    Icon(Icons.bluetooth, color: AppTheme.primaryBlue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Koneksi Printer Bluetooth',
                        style: TextStyle(color: AppTheme.darkBlueText, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                    if (widget.role == 'developer')
                      IconButton(
                        icon: Icon(Icons.edit, color: AppTheme.primaryBlue, size: 20),
                        tooltip: 'Edit Panduan',
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (context) => _EditPrinterGuideDialog(
                              initialAndroidSteps: androidSteps,
                              initialIosSteps: iosSteps,
                            ),
                          );
                        },
                      ),
                  ],
                ),
                content: Container(
                  width: double.maxFinite,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TabBar(
                        labelColor: AppTheme.primaryBlue,
                        unselectedLabelColor: AppTheme.textGray,
                        indicatorColor: AppTheme.primaryBlue,
                        tabs: const [
                          Tab(text: 'Android (HP)', icon: Icon(Icons.android)),
                          Tab(text: 'iOS (iPhone)', icon: Icon(Icons.phone_iphone)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        height: 300,
                        child: TabBarView(
                          children: [
                            // Android Guide
                            androidSteps.isEmpty
                                ? const Center(child: Text('Belum ada panduan.'))
                                : ListView.builder(
                                    itemCount: androidSteps.length,
                                    itemBuilder: (context, index) {
                                      return _buildGuideStep('${index + 1}', androidSteps[index]);
                                    },
                                  ),
                            // iOS Guide
                            iosSteps.isEmpty
                                ? const Center(child: Text('Belum ada panduan.'))
                                : ListView.builder(
                                    itemCount: iosSteps.length,
                                    itemBuilder: (context, index) {
                                      return _buildGuideStep('${index + 1}', iosSteps[index]);
                                    },
                                  ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Tutup', style: TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildGuideStep(String number, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 9,
            backgroundColor: AppTheme.primaryBlue.withOpacity(0.12),
            child: Text(
              number,
              style: TextStyle(fontSize: 10, color: AppTheme.primaryBlue, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12, color: AppTheme.darkBlueText, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditPrinterGuideDialog extends StatefulWidget {
  final List<String> initialAndroidSteps;
  final List<String> initialIosSteps;

  const _EditPrinterGuideDialog({
    Key? key,
    required this.initialAndroidSteps,
    required this.initialIosSteps,
  }) : super(key: key);

  @override
  State<_EditPrinterGuideDialog> createState() => _EditPrinterGuideDialogState();
}

class _EditPrinterGuideDialogState extends State<_EditPrinterGuideDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late List<TextEditingController> _androidControllers;
  late List<TextEditingController> _iosControllers;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _androidControllers = widget.initialAndroidSteps
        .map((step) => TextEditingController(text: step))
        .toList();
    _iosControllers = widget.initialIosSteps
        .map((step) => TextEditingController(text: step))
        .toList();
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (var c in _androidControllers) {
      c.dispose();
    }
    for (var c in _iosControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _addStep(bool isAndroid) {
    setState(() {
      if (isAndroid) {
        _androidControllers.add(TextEditingController());
      } else {
        _iosControllers.add(TextEditingController());
      }
    });
  }

  void _removeStep(bool isAndroid, int index) {
    setState(() {
      if (isAndroid) {
        _androidControllers[index].dispose();
        _androidControllers.removeAt(index);
      } else {
        _iosControllers[index].dispose();
        _iosControllers.removeAt(index);
      }
    });
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      final androidSteps = _androidControllers
          .map((c) => c.text.trim())
          .where((text) => text.isNotEmpty)
          .toList();
      final iosSteps = _iosControllers
          .map((c) => c.text.trim())
          .where((text) => text.isNotEmpty)
          .toList();

      await FirebaseFirestore.instance.collection('app_config').doc('printer_guide').set({
        'androidSteps': androidSteps,
        'iosSteps': iosSteps,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menyimpan: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.white,
      title: Row(
        children: [
          Icon(Icons.edit_note, color: AppTheme.primaryBlue),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Edit Panduan Printer',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1E3A8A)),
            ),
          ),
        ],
      ),
      content: _isSaving
          ? const SizedBox(
              height: 200,
              child: Center(child: CircularProgressIndicator()),
            )
          : SizedBox(
              width: double.maxFinite,
              height: 400,
              child: Column(
                children: [
                  TabBar(
                    controller: _tabController,
                    labelColor: AppTheme.primaryBlue,
                    unselectedLabelColor: AppTheme.textGray,
                    indicatorColor: AppTheme.primaryBlue,
                    tabs: const [
                      Tab(text: 'Android Steps'),
                      Tab(text: 'iOS Steps'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildStepsList(true),
                        _buildStepsList(false),
                      ],
                    ),
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
          onPressed: _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryBlue,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: const Text('Simpan'),
        ),
      ],
    );
  }

  Widget _buildStepsList(bool isAndroid) {
    final controllers = isAndroid ? _androidControllers : _iosControllers;
    return ListView(
      children: [
        ...List.generate(controllers.length, (index) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: AppTheme.primaryBlue.withOpacity(0.12),
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(fontSize: 11, color: AppTheme.primaryBlue, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: controllers[index],
                    maxLines: null,
                    decoration: InputDecoration(
                      hintText: 'Masukkan langkah panduan...',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    style: TextStyle(fontSize: 13, color: AppTheme.darkBlueText),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                  onPressed: () => _removeStep(isAndroid, index),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _addStep(isAndroid),
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Tambah Langkah', style: TextStyle(fontSize: 12)),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.primaryBlue,
            side: BorderSide(color: AppTheme.primaryBlue),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ],
    );
  }
}
