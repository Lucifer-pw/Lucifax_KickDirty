import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import '../theme.dart';
import '../utils/platform_helper.dart';
import '../utils/error_helper.dart';

class MapPickerScreen extends StatefulWidget {
  final String initialMapsLink;
  
  MapPickerScreen({
    Key? key,
    this.initialMapsLink = '',
  }) : super(key: key);

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  final MapController _mapController = MapController();
  LatLng _currentCenter = LatLng(-7.556, 110.825); // Default: Solo, Indonesia
  String _address = 'Mencari alamat...';
  bool _isLoadingAddress = false;
  Timer? _debounceTimer;
  
  @override
  void initState() {
    super.initState();
    _parseInitialLocation();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _parseInitialLocation() {
    final link = widget.initialMapsLink.trim();
    if (link.isEmpty) {
      // Fetch GPS position immediately if no initial link
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _getCurrentLocation();
      });
      return;
    }
    
    // Parse coordinates from link
    final coords = _parseLatLng(link);
    if (coords != null) {
      _currentCenter = LatLng(coords['latitude']!, coords['longitude']!);
      _reverseGeocode(_currentCenter);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _getCurrentLocation();
      });
    }
  }

  Map<String, double>? _parseLatLng(String url) {
    if (url.isEmpty) return null;
    final regExp = RegExp(r'(?:query|q|place)=([+-]?\d+\.\d+)\s*,\s*([+-]?\d+\.\d+)');
    final match = regExp.firstMatch(url);
    if (match != null && match.groupCount >= 2) {
      final lat = double.tryParse(match.group(1)!);
      final lng = double.tryParse(match.group(2)!);
      if (lat != null && lng != null) return {'latitude': lat, 'longitude': lng};
    }
    
    final regExpAt = RegExp(r'@([+-]?\d+\.\d+)\s*,\s*([+-]?\d+\.\d+)');
    final matchAt = regExpAt.firstMatch(url);
    if (matchAt != null && matchAt.groupCount >= 2) {
      final lat = double.tryParse(matchAt.group(1)!);
      final lng = double.tryParse(matchAt.group(2)!);
      if (lat != null && lng != null) return {'latitude': lat, 'longitude': lng};
    }

    final regExpRaw = RegExp(r'^([+-]?\d+\.\d+)\s*,\s*([+-]?\d+\.\d+)$');
    final matchRaw = regExpRaw.firstMatch(url.trim());
    if (matchRaw != null && matchRaw.groupCount >= 2) {
      final lat = double.tryParse(matchRaw.group(1)!);
      final lng = double.tryParse(matchRaw.group(2)!);
      if (lat != null && lng != null) return {'latitude': lat, 'longitude': lng};
    }

    return null;
  }

  Future<void> _getCurrentLocation() async {
    setState(() {
      _isLoadingAddress = true;
      _address = 'Mencari lokasi GPS Anda...';
    });
    try {
      final link = await getGpsLocation();
      if (link != null) {
        final coords = _parseLatLng(link);
        if (coords != null) {
          final latLng = LatLng(coords['latitude']!, coords['longitude']!);
          setState(() {
            _currentCenter = latLng;
          });
          _mapController.move(latLng, 16.0);
          _reverseGeocode(latLng);
        }
      } else {
        setState(() {
          _address = 'Gagal mendeteksi GPS. Silakan geser peta secara manual.';
          _isLoadingAddress = false;
        });
      }
    } catch (e) {
      setState(() {
        _address = 'Gagal mendeteksi lokasi GPS: ${getCleanErrorMessage(e)}';
        _isLoadingAddress = false;
      });
    }
  }

  Future<void> _reverseGeocode(LatLng coords) async {
    setState(() {
      _isLoadingAddress = true;
      _address = 'Mencari alamat...';
    });
    
    try {
      final response = await http.get(
        Uri.parse('https://nominatim.openstreetmap.org/reverse?format=json&lat=${coords.latitude}&lon=${coords.longitude}&zoom=18&addressdetails=1'),
        headers: {'User-Agent': 'LucifaxKickDirtyApp/1.0.0 (contact: clasherdracax@gmail.com)'},
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final displayName = data['display_name'] as String?;
        if (displayName != null && displayName.isNotEmpty) {
          setState(() {
            _address = displayName;
            _isLoadingAddress = false;
          });
          return;
        }
      }
      
      setState(() {
        _address = '${coords.latitude.toStringAsFixed(6)}, ${coords.longitude.toStringAsFixed(6)}';
        _isLoadingAddress = false;
      });
    } catch (e) {
      setState(() {
        _address = '${coords.latitude.toStringAsFixed(6)}, ${coords.longitude.toStringAsFixed(6)}';
        _isLoadingAddress = false;
      });
    }
  }

  void _onMapPositionChanged(MapPosition position, bool hasGesture) {
    if (position.center == null || !hasGesture) return;
    
    _currentCenter = position.center!;
    
    // Debounce geocoding requests to prevent rate limit
    _debounceTimer?.cancel();
    _debounceTimer = Timer(Duration(milliseconds: 600), () {
      _reverseGeocode(_currentCenter);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Ubah Alamat / Titik Koordinat'),
        backgroundColor: Colors.grey[900],
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Stack(
        children: [
          // 1. Interactive Map View
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentCenter,
              initialZoom: 16.0,
              onPositionChanged: _onMapPositionChanged,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.lucifax.kickdirty',
              ),
            ],
          ),

          // 2. Fixed Center Pin
          Center(
            child: Container(
              margin: EdgeInsets.only(bottom: 40), // Offset to put bottom tip of marker at center
              child: Icon(
                Icons.location_on,
                color: Colors.red,
                size: 48,
                shadows: [
                  Shadow(
                    color: Colors.black38,
                    offset: Offset(0, 4),
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
          ),

          // 3. Top Address Details Box (matching user's screenshot layout)
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Card(
              color: Colors.black.withOpacity(0.85),
              elevation: 6,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Alamat yang Dipilih',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    SizedBox(height: 6),
                    if (_isLoadingAddress)
                      Row(
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Mencari alamat...',
                              style: TextStyle(color: Colors.white, fontSize: 13),
                            ),
                          ),
                        ],
                      )
                    else
                      Text(
                        _address,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          height: 1.3,
                        ),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ),
          ),

          // 4. Floating GPS Target Button
          Positioned(
            bottom: 96,
            right: 16,
            child: FloatingActionButton(
              onPressed: _getCurrentLocation,
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              mini: true,
              elevation: 4,
              child: Icon(Icons.my_location),
            ),
          ),

          // 5. Bottom Confirmation Button (matching user's layout)
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoadingAddress
                    ? null
                    : () {
                        // Return selected coordinates as a google maps search link and the geocoded address
                        final mapsLink = 'https://www.google.com/maps/search/?api=1&query=${_currentCenter.latitude},${_currentCenter.longitude}';
                        Navigator.pop(context, {
                          'mapsLink': mapsLink,
                          'address': _address,
                        });
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryBlue,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey[400],
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 4,
                ),
                child: Text(
                  'Konfirmasi Lokasi',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
