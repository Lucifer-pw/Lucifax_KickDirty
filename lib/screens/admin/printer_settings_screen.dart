import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../utils/printer/printer_service.dart';
import '../../theme.dart';

class PrinterSettingsScreen extends StatefulWidget {
  const PrinterSettingsScreen({Key? key}) : super(key: key);

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
            ElevatedButton(
              onPressed: _loadDevices,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Segarkan'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceList() {
    return ListView.builder(
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
    );
  }
}
