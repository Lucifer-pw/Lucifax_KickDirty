import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../theme.dart';

class Watermark extends StatefulWidget {
  final Color? textColor;
  Watermark({Key? key, this.textColor}) : super(key: key);

  @override
  State<Watermark> createState() => _WatermarkState();
}

class _WatermarkState extends State<Watermark> {
  String _version = "1.0.0";

  @override
  void initState() {
    super.initState();
    _loadVersionInfo();
  }

  Future<void> _loadVersionInfo() async {
    try {
      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      setState(() {
        _version = packageInfo.version;
      });
    } catch (_) {
      // Keep default if failing (e.g. on web or testing platforms before compile)
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.textColor ?? AppTheme.textGray;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "Powered by Lucifax",
            style: TextStyle(
              color: color.withOpacity(0.8),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.1,
            ),
          ),
          SizedBox(height: 2),
          Text(
            "Version $_version",
            style: TextStyle(
              color: color.withOpacity(0.5),
              fontSize: 10,
              fontWeight: FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}
