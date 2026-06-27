import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/order_model.dart';

class WhatsAppService {
  static final _db = FirebaseFirestore.instance;

  /// Uploads PDF bytes to tmpfiles.org and returns the direct download link
  static Future<String?> uploadPdfToTmpFiles(Uint8List pdfBytes, String filename) async {
    try {
      final boundary = '----WebKitFormBoundary7MA4YWxkTrZu0gW';
      final client = HttpClient();
      final request = await client.postUrl(Uri.parse('https://tmpfiles.org/api/v1/upload'));
      
      request.headers.set('content-type', 'multipart/form-data; boundary=$boundary');
      
      // Construct boundary body
      final header = '--$boundary\r\n'
          'Content-Disposition: form-data; name="file"; filename="$filename"\r\n'
          'Content-Type: application/pdf\r\n\r\n';
      final footer = '\r\n--$boundary--\r\n';
      
      final headerBytes = utf8.encode(header);
      final footerBytes = utf8.encode(footer);
      
      request.contentLength = headerBytes.length + pdfBytes.length + footerBytes.length;
      
      request.add(headerBytes);
      request.add(pdfBytes);
      request.add(footerBytes);
      
      final response = await request.close();
      if (response.statusCode != 200) {
        return null;
      }
      
      final responseBody = await response.transform(utf8.decoder).join();
      final json = jsonDecode(responseBody);
      if (json['status'] == 'success') {
        final rawUrl = json['data']['url'];
        // Tmpfiles returns a viewer link. Replace the domain prefix to get direct download URL
        if (rawUrl != null && rawUrl.toString().contains('tmpfiles.org/')) {
          return rawUrl.toString().replaceFirst('tmpfiles.org/', 'tmpfiles.org/dl/');
        }
        return rawUrl;
      }
    } catch (_) {}
    return null;
  }
  
  /// Fetches gateway configuration from Firestore
  static Future<Map<String, dynamic>?> getGatewayConfig() async {
    try {
      final doc = await _db.collection('app_config').doc('whatsapp_config').get();
      if (doc.exists) {
        return doc.data();
      }
    } catch (_) {}
    return null;
  }

  /// Sends a text message or a document via the configured Gateway
  static Future<bool> sendNotification({
    required String phone,
    required String message,
    String? fileUrl,
    String? filename,
  }) async {
    final config = await getGatewayConfig();
    if (config == null || config['useAutomation'] != true) {
      return false; // Fallback to manual mode
    }

    final provider = config['provider'] ?? 'manual';
    final token = config['apiToken'] ?? '';

    if (provider == 'manual' || token.isEmpty) return false;

    // Sanitize phone number (remove spaces, symbols, and convert 08xx to 628xx)
    String cleanPhone = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanPhone.startsWith('0')) {
      cleanPhone = '62${cleanPhone.substring(1)}';
    }

    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 15);
      
      if (provider == 'fonnte') {
        final request = await client.postUrl(Uri.parse('https://api.fonnte.com/send'));
        request.headers.set('Authorization', token);
        request.headers.set('content-type', 'application/json');
        
        final Map<String, dynamic> body = {
          'target': cleanPhone,
          'message': message,
        };
        if (fileUrl != null) {
          body['url'] = fileUrl;
          if (filename != null) {
            body['filename'] = filename;
          }
        }
        
        request.write(jsonEncode(body));
        final response = await request.close();
        final resStr = await response.transform(utf8.decoder).join();
        return response.statusCode == 200;
      } else if (provider == 'wablas') {
        final baseUrl = config['gatewayUrl'] ?? 'https://api.wablas.com';
        final endpoint = fileUrl != null ? '/api/send-document' : '/api/send-message';
        final url = Uri.parse('$baseUrl$endpoint');
        
        final request = await client.postUrl(url);
        request.headers.set('Authorization', token);
        request.headers.set('content-type', 'application/json');
        
        final Map<String, dynamic> body = {
          'phone': cleanPhone,
          'message': message,
        };
        if (fileUrl != null) {
          body['document'] = fileUrl;
          if (filename != null) {
            body['fileName'] = filename;
          }
        }
        
        request.write(jsonEncode(body));
        final response = await request.close();
        return response.statusCode == 200;
      }
    } catch (_) {}
    return false;
  }

  /// Sends automatic status/payment notification to WhatsApp
  static Future<void> sendAutomaticStatusNotification(OrderModel order, String eventType) async {
    String statusText = '';
    if (eventType == 'diterima') {
      statusText = 'telah kami terima dan segera diproses.';
    } else if (eventType == 'sedang_diproses') {
      statusText = 'sedang dalam proses pencucian/servis.';
    } else if (eventType == 'selesai') {
      statusText = 'telah SELESAI dan siap diambil.';
    } else if (eventType == 'diambil') {
      statusText = 'telah diserahkan ke pelanggan. Terima kasih atas kepercayaan Anda!';
    } else if (eventType == 'dibayar') {
      statusText = 'pembayarannya dinyatakan LUNAS. Terima kasih!';
    }

    String paymentText = order.paymentStatus == 'sudah_bayar' ? 'Lunas' : 'Belum Lunas';

    String message = 'Halo Kak *${order.customerName}*,\n\n'
        'Sepatu Anda dengan nomor invoice *${order.id}* $statusText\n'
        'Detail sepatu:\n'
        '${order.items.map((item) => '- ${item.itemName} (${item.serviceName})').join('\n')}\n\n'
        'Total Biaya: *Rp ${order.totalAmount.toStringAsFixed(0)}* (${paymentText})\n\n'
        'Powered by KickDirty';

    await sendNotification(phone: order.customerPhone, message: message);
  }
}
