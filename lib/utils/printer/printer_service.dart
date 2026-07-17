import 'printer_stub.dart'
    if (dart.library.html) 'printer_web.dart'
    if (dart.library.io) 'printer_io.dart';

abstract class PrinterService {
  static PrinterService? _instance;
  static PrinterService get instance {
    _instance ??= getPrinterService();
    return _instance!;
  }

  Future<bool> isBluetoothSupported();
  Future<List<BluetoothPrinterDevice>> getPairedDevices();
  Future<bool> connect(String address);
  Future<void> disconnect();
  Future<bool> isConnected();
  Stream<bool> get connectionStatusStream;
  Future<void> printThermal(List<int> bytes);
  Future<String?> getConnectedAddress();
}

class BluetoothPrinterDevice {
  final String name;
  final String address;
  BluetoothPrinterDevice(this.name, this.address);
}
