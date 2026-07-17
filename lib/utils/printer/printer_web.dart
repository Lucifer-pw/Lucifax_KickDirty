import 'dart:async';
import 'printer_service.dart';

PrinterService getPrinterService() => PrinterWebService();

class PrinterWebService extends PrinterService {
  final _statusController = StreamController<bool>.broadcast();

  @override
  Future<bool> isBluetoothSupported() async => false;

  @override
  Future<List<BluetoothPrinterDevice>> getPairedDevices() async => [];

  @override
  Future<bool> connect(String address) async => false;

  @override
  Future<void> disconnect() async {}

  @override
  Future<bool> isConnected() async => false;

  @override
  Stream<bool> get connectionStatusStream => _statusController.stream;

  @override
  Future<void> printThermal(List<int> bytes) async {}

  @override
  Future<String?> getConnectedAddress() async => null;
}
