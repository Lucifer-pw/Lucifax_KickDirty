import 'dart:async';
import 'dart:typed_data';
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'printer_service.dart';

PrinterService getPrinterService() => PrinterIoService();

class PrinterIoService extends PrinterService {
  final BlueThermalPrinter _bluetooth = BlueThermalPrinter.instance;
  final _statusController = StreamController<bool>.broadcast();
  static const String _prefAddressKey = 'connected_printer_address';

  PrinterIoService() {
    // Monitor connection status changes if possible
    _bluetooth.onStateChanged().listen((state) {
      if (state == BlueThermalPrinter.CONNECTED) {
        _statusController.add(true);
      } else {
        _statusController.add(false);
      }
    });

    // Try auto-reconnect on startup
    _autoReconnect();
  }

  Future<void> _autoReconnect() async {
    final address = await getConnectedAddress();
    if (address != null && address.isNotEmpty) {
      try {
        final connected = await isConnected();
        if (!connected) {
          final devices = await _bluetooth.getBondedDevices();
          final device = devices.firstWhere(
            (d) => d.address == address,
            orElse: () => throw Exception('Device not paired anymore'),
          );
          await _bluetooth.connect(device);
          _statusController.add(true);
        }
      } catch (_) {
        _statusController.add(false);
      }
    }
  }

  @override
  Future<bool> isBluetoothSupported() async {
    try {
      final isAvailable = await _bluetooth.isAvailable ?? false;
      return isAvailable;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<BluetoothPrinterDevice>> getPairedDevices() async {
    try {
      final devices = await _bluetooth.getBondedDevices();
      return devices
          .map((d) => BluetoothPrinterDevice(d.name ?? 'Unknown Device', d.address ?? ''))
          .toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<bool> connect(String address) async {
    try {
      final devices = await _bluetooth.getBondedDevices();
      final device = devices.firstWhere((d) => d.address == address);
      
      // If already connected to another device, disconnect first
      final alreadyConnected = await isConnected();
      if (alreadyConnected) {
        await disconnect();
      }

      await _bluetooth.connect(device);
      
      // Save address to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefAddressKey, address);
      
      _statusController.add(true);
      return true;
    } catch (_) {
      _statusController.add(false);
      return false;
    }
  }

  @override
  Future<void> disconnect() async {
    try {
      await _bluetooth.disconnect();
      // Remove address from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefAddressKey);
      _statusController.add(false);
    } catch (_) {}
  }

  @override
  Future<bool> isConnected() async {
    try {
      final connected = await _bluetooth.isConnected ?? false;
      return connected;
    } catch (_) {
      return false;
    }
  }

  @override
  Stream<bool> get connectionStatusStream => _statusController.stream;

  @override
  Future<void> printThermal(List<int> bytes) async {
    try {
      final connected = await isConnected();
      if (connected) {
        // Send image bytes to thermal printer using printImageBytes
        await _bluetooth.printImageBytes(Uint8List.fromList(bytes));
        // Add extra line feed and paper cut if necessary
        await _bluetooth.printNewLine();
        await _bluetooth.printNewLine();
      }
    } catch (_) {}
  }

  @override
  Future<String?> getConnectedAddress() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefAddressKey);
  }
}
