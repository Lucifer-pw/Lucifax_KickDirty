import 'platform_helper_non_web.dart'
    if (dart.library.html) 'platform_helper_web.dart';

String getDevice() {
  return getDeviceDetails();
}
