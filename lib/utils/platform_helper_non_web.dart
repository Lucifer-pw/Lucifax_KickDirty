import 'dart:io';

String getDeviceDetails() {
  return 'Mobile/Desktop (${Platform.operatingSystem} ${Platform.operatingSystemVersion})';
}

Future<String?> getDeviceGpsLocation() async {
  return null;
}
