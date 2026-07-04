import 'dart:html' as html;
import 'dart:async';

String getDeviceDetails() {
  final userAgent = html.window.navigator.userAgent;
  final platform = html.window.navigator.platform ?? '';
  return 'Web ($platform) - $userAgent';
}

Future<String?> getDeviceGpsLocation() async {
  try {
    final position = await html.window.navigator.geolocation.getCurrentPosition();
    final lat = position.coords?.latitude;
    final lng = position.coords?.longitude;
    if (lat != null && lng != null) {
      return 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
    }
  } catch (e) {
    // Geolocation error or permission denied
  }
  return null;
}
