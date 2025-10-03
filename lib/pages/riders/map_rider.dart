import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:deliverydomo/pages/riders/widgets/appbar.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class MapRider extends StatefulWidget {
  final String? addressId;
  final String? userId;
  final String? phoneId;

  const MapRider({Key? key, this.addressId, this.userId, this.phoneId})
      : super(key: key);

  @override
  State<MapRider> createState() => _MapRiderState();
}

class _MapRiderState extends State<MapRider> {
  static const _orange = Color(0xFFFD8700);

  final _controller = Completer<GoogleMapController>();
  final Set<Marker> _markers = {};
  LatLng? _initialCenter;
  _AddressPin? _selected;

  StreamSubscription<Position>? _posSub;

  @override
  void initState() {
    super.initState();
    _prepareMarkers();
  }

  @override
  void dispose() {
    _posSub?.cancel();
    super.dispose();
  }

  Future<void> _prepareMarkers() async {
    final position = await _getCurrentLocation(logNow: true);
    if (position != null) {
      setState(() => _initialCenter = position);
      _startLocationLogging();
    }

    final fs = FirebaseFirestore.instance;
    final List<_AddressPin> pins = [];

    if (widget.addressId != null && widget.addressId!.isNotEmpty) {
      final snap =
          await fs.collection('addressuser').doc(widget.addressId).get();
      if (snap.exists) {
        final pin = _fromMap(snap.id, snap.data() ?? {});
        if (pin != null) pins.add(pin);
      }
    } else {
      Query<Map<String, dynamic>> q = fs.collection('addressuser');
      if (widget.userId != null && widget.userId!.isNotEmpty) {
        q = q.where('userId', isEqualTo: widget.userId);
      } else if (widget.phoneId != null && widget.phoneId!.isNotEmpty) {
        q = q.where('userId', isEqualTo: widget.phoneId);
      }
      final res = await q.get();
      for (final d in res.docs) {
        final pin = _fromMap(d.id, d.data());
        if (pin != null) pins.add(pin);
      }
    }

    final markers = <Marker>{};
    for (final pin in pins) {
      markers.add(
        Marker(
          markerId: MarkerId(pin.id),
          position: pin.position,
          infoWindow: InfoWindow(
            title: pin.title,
            snippet: pin.detail,
            onTap: () => _openInGoogleMaps(pin.position, pin.title),
          ),
          onTap: () => setState(() => _selected = pin),
          icon: BitmapDescriptor.defaultMarker,
        ),
      );
    }

    setState(() => _markers.addAll(markers));

    if (_initialCenter != null) {
      final controller = await _controller.future;
      controller.animateCamera(CameraUpdate.newLatLngZoom(_initialCenter!, 15));
    }
  }

  _AddressPin? _fromMap(String id, Map<String, dynamic> m) {
    final title = (m['label'] ?? m['name'] ?? 'ที่อยู่').toString();
    final detail = (m['address_text'] ?? m['detail'] ?? '').toString();
    final phone = (m['phone'] ?? '').toString();
    final geopoint = m['geopoint'];
    LatLng? position;
    if (geopoint is GeoPoint) {
      position = LatLng(geopoint.latitude, geopoint.longitude);
    }
    if (position == null) return null;
    return _AddressPin(
      id: id,
      title: title,
      detail: detail,
      phone: phone,
      position: position,
      isDefault: m['is_default'] ?? false,
    );
  }

  Future<void> _openInGoogleMaps(LatLng pos, String label) async {
    final url = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=${pos.latitude},${pos.longitude}&query_place_id=${Uri.encodeComponent(label)}');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  Future<LatLng?> _getCurrentLocation({bool logNow = false}) async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('[RIDER_LOC] ❌ Location service disabled');
        await Geolocator.openLocationSettings();
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        debugPrint('[RIDER_LOC] ❌ Permission deniedForever');
        await Geolocator.openAppSettings();
        return null;
      }
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        debugPrint('[RIDER_LOC] ❌ Permission not granted ($permission)');
        return null;
      }

      Position pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.best,
          timeLimit: const Duration(seconds: 8),
        );
      } on TimeoutException {
        debugPrint('[RIDER_LOC] ⏱️ Timeout, using lastKnown');
        final last = await Geolocator.getLastKnownPosition();
        if (last == null) return null;
        pos = last;
      }

      if (logNow) _logPosition('SINGLE', pos);
      return LatLng(pos.latitude, pos.longitude);
    } catch (e, st) {
      debugPrint('[RIDER_LOC] ❌ Error: $e\n$st');
      return null;
    }
  }

  void _startLocationLogging() async {
    await _posSub?.cancel();
    const settings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 5,
    );
    _posSub = Geolocator.getPositionStream(locationSettings: settings).listen(
      (pos) => _logPosition('STREAM', pos),
      onError: (e) => debugPrint('[RIDER_LOC] ❌ stream error: $e'),
    );
  }

  void _logPosition(String tag, Position pos) {
    debugPrint(
      '[RIDER_LOC][$tag] lat=${pos.latitude.toStringAsFixed(6)}, '
      'lng=${pos.longitude.toStringAsFixed(6)}, '
      'acc=${pos.accuracy.toStringAsFixed(1)}m, '
      'speed=${pos.speed.toStringAsFixed(2)}m/s, '
      'heading=${pos.heading.toStringAsFixed(1)}°, '
      'time=${pos.timestamp}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final initialPosition =
        _initialCenter ?? const LatLng(13.736717, 100.523186);

    return Scaffold(
      appBar: customAppBar(),
      body: Column(
        children: [
          Expanded(
            child: GoogleMap(
              initialCameraPosition:
                  CameraPosition(target: initialPosition, zoom: 14),
              markers: _markers,
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              onMapCreated: (controller) => _controller.complete(controller),
              zoomControlsEnabled: false,
              mapToolbarEnabled: true,
            ),
          ),
          if (_selected != null) _SelectedBar(pin: _selected!),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.extended(
            backgroundColor: _orange,
            onPressed: () async {
              final loc = await _getCurrentLocation(logNow: true);
              if (loc == null) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('ไม่สามารถดึงตำแหน่งได้')),
                  );
                }
                return;
              }
              final c = await _controller.future;
              c.animateCamera(CameraUpdate.newLatLngZoom(loc, 16));
            },
            icon: const Icon(Icons.my_location),
            label: const Text('LOG NOW'),
          ),
          const SizedBox(height: 10),
          if (_initialCenter != null)
            FloatingActionButton(
              backgroundColor: _orange,
              onPressed: () async {
                final controller = await _controller.future;
                controller.animateCamera(
                    CameraUpdate.newLatLngZoom(_initialCenter!, 15));
              },
              child: const Icon(Icons.center_focus_strong),
            ),
          const SizedBox(height: 10),
          FloatingActionButton.extended(
            backgroundColor: _orange,
            onPressed: (_selected == null) ? null : () {},
            icon: const Icon(Icons.save_alt),
            label: const Text('บันทึกที่อยู่ไรเดอร์'),
          ),
        ],
      ),
    );
  }
}

class _AddressPin {
  final String id;
  final String title;
  final String detail;
  final String phone;
  final LatLng position;
  final bool isDefault;

  _AddressPin({
    required this.id,
    required this.title,
    required this.detail,
    required this.phone,
    required this.position,
    required this.isDefault,
  });
}

class _SelectedBar extends StatelessWidget {
  final _AddressPin pin;

  const _SelectedBar({Key? key, required this.pin}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      child: Container(
        width: double.infinity,
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.location_on_outlined, color: Color(0xFFFD8700)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(pin.title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 16)),
                  if (pin.detail.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(pin.detail,
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                  const SizedBox(height: 2),
                  Text(
                      'พิกัด: ${pin.position.latitude.toStringAsFixed(6)}, ${pin.position.longitude.toStringAsFixed(6)}',
                      style: const TextStyle(color: Colors.black54)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
