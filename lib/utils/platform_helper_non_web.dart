import 'dart:io';

String getDeviceDetails() {
  return 'Mobile/Desktop (${Platform.operatingSystem} ${Platform.operatingSystemVersion})';
}
