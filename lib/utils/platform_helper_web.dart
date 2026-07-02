import 'dart:html' as html;

String getDeviceDetails() {
  final userAgent = html.window.navigator.userAgent;
  final platform = html.window.navigator.platform ?? '';
  return 'Web ($platform) - $userAgent';
}
