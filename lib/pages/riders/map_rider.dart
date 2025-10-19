// lib/pages/map_rider.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math' show cos, sqrt, asin;
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:deliverydomo/pages/riders/widgets/appbar.dart';
import 'package:deliverydomo/pages/sesstion.dart'; // ใช้ SessionStore
import 'package:deliverydomo/services/firebase_reueries_rider.dart';
import 'package:deliverydomo/services/rider_location.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

class MapRider extends StatefulWidget {
  const MapRider({Key? key}) : super(key: key);

  @override
  State<MapRider> createState() => _MapRiderState();
}

class _MapRiderState extends State<MapRider> {
  // ---- Theme colors ----
  static const _orange = Color(0xFFFD8700);
  static const _green = Color(0xFF16A34A);
  static const _blue = Color(0xFF3B82F6);
  static const _red = Color(0xFFE11D48);
  static const _grey = Color(0xFF9CA3AF);

  // ---- Controllers / state ----
  final _controller = Completer<GoogleMapController>();
  final Set<Marker> _staticMarkers = {}; // sender / receiver
  final Set<Polyline> _polylines = {};
  Marker? _riderMarker;

  LatLng? _initialCenter;
  LatLng? _riderPos;
  LatLng? _riderPosPrev;

  // user/session
  late final RiderLocationSender _sender;
  late final FirebaseRiderRepository _repo;
  String? _riderId;
  String? _shipmentId;

  // live firestore subs
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _riderDocSub;
  StreamSubscription<String?>? _currentShipIdSub;
  StreamSubscription<List<QueryDocumentSnapshot<Map<String, dynamic>>>>?
      _shipDocsSub;
  StreamSubscription<List<ResolvedShipment>>? _resolvedShipSub;

  // icons
  BitmapDescriptor? _senderIcon, _receiverIcon, _riderIcon;

  // routing states
  _RouteInfo? _routeInfo;
  bool _isPickedUp = false; // false = ไปจุดรับ, true = ไปจุดส่ง
  bool _routingBusy = false;
  Timer? _routeDebounce;
  LatLng? _lastRoutedFrom;
  int _routeVersion = 0; // บังคับ redraw polyline
  final double _rerouteMinMoveM = 60.0;


  double? _etaMin; // นาที
  double? _distKm; // กม.

  // camera throttling
  DateTime _lastCameraMoveAt = DateTime.fromMillisecondsSinceEpoch(0);

  // ===== Lifecycle =====
  @override
  void initState() {
    super.initState();
    _sender = RiderLocationSender();
    _repo = FirebaseRiderRepository();
    _boot();
  }

  @override
  void dispose() {
    _riderDocSub?.cancel();
    _currentShipIdSub?.cancel();
    _shipDocsSub?.cancel();
    _resolvedShipSub?.cancel();
    _sender.stopLive();
    _routeDebounce?.cancel();
    super.dispose();
  }

  // ===== Boot flow =====
  Future<void> _boot() async {
    // 1) resolve riderId
    _riderId = (SessionStore.userId ?? SessionStore.phoneId ?? '').toString();
    if (_riderId == null || _riderId!.isEmpty) {
      debugPrint('[MAP] riderId not found in SessionStore');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ไม่พบรหัสไรเดอร์ (riderId)')),
        );
      }
      return;
    }

    await _loadCustomIcons();

    // 2) get current position & push once
    final pos = await _ensurePermissionAndGetCurrent(logNow: true);
    if (!mounted) return;
    if (pos != null) {
      _initialCenter = pos;
      _updateRiderMarker(pos);
      await _sender.updateOnce(
        riderId: _riderId!,
        lat: pos.latitude,
        lng: pos.longitude,
      );
    }

    // 3) start live location sender
    await _sender.startLive(
      riderId: _riderId!,
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 5,
      throttle: const Duration(seconds: 3),
    );

    // 4) resolve + subscribe current_shipment_id ผ่าน repo ✅
    _shipmentId = await _repo.getCurrentShipmentIdOnce(_riderId!);

    _currentShipIdSub = _repo.watchCurrentShipmentId(_riderId!).listen((id) {
      _shipmentId = id;
      debugPrint('[MAP] current_shipment_id = $_shipmentId');
    });

   
    _resolvedShipSub = _repo
        .watchShipmentsOfRiderResolved(
      riderId: _riderId!,
      statusIn: const [2, 3],
      limit: 50,
    )
        .listen((list) {
      if (_shipmentId == null || _shipmentId!.isEmpty) {
        // ถ้าไม่มี current_shipment_id ให้ลองหยิบตัวล่าสุดใน list
        if (list.isEmpty) return;
        final s = list.first;
        _applyResolvedShipment(s);
      } else {
        final s = list.where((e) => e.id == _shipmentId).toList();
        if (s.isNotEmpty) _applyResolvedShipment(s.first);
      }
    });

    
    _subscribeRiderDoc();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final c = await _controller.future;
      if (_routeInfo != null) {
        _fitBoundsToRoute();
      } else if (_initialCenter != null) {
        c.animateCamera(CameraUpdate.newLatLngZoom(_initialCenter!, 15));
      }
    });

    // 8) first route build
    _debouncedUpdateRoute();
  }

  // เอา ResolvedShipment จาก repo มาวาง marker + เตรียมเส้นทาง
  void _applyResolvedShipment(ResolvedShipment s) {
    final senderGeo = s.senderGeo;
    final receiverGeo = s.receiverGeo;
    if (senderGeo == null || receiverGeo == null) {
      debugPrint('[MAP] ResolvedShipment missing geo');
      return;
    }
    final senderPos = LatLng(senderGeo.lat, senderGeo.lng);
    final receiverPos = LatLng(receiverGeo.lat, receiverGeo.lng);

    _routeInfo = _RouteInfo(
      senderPos: senderPos,
      receiverPos: receiverPos,
      senderName: s.senderName,
      receiverName: s.receiverName,
      senderAddrText: s.senderAddressText.isEmpty ? null : s.senderAddressText,
      receiverAddrText:
          s.receiverAddressText.isEmpty ? null : s.receiverAddressText,
    );

    _staticMarkers
      ..removeWhere(
          (m) => m.markerId.value == 'sender' || m.markerId.value == 'receiver')
      ..add(
        Marker(
          markerId: const MarkerId('sender'),
          position: senderPos,
          icon: _senderIcon ?? BitmapDescriptor.defaultMarker,
          infoWindow: InfoWindow(
            title: '📤 จุดรับสินค้า',
            snippet: _routeInfo!.senderAddrText,
          ),
        ),
      )
      ..add(
        Marker(
          markerId: const MarkerId('receiver'),
          position: receiverPos,
          icon: _receiverIcon ?? BitmapDescriptor.defaultMarker,
          infoWindow: InfoWindow(
            title: '📥 จุดส่งสินค้า',
            snippet: _routeInfo!.receiverAddrText,
          ),
        ),
      );

    setState(() {});
    _debouncedUpdateRoute(force: true);
  }

  _subscribeRiderDoc() {
    _riderDocSub?.cancel();
    _riderDocSub = FirebaseFirestore.instance
        .collection('rider_location')
        .doc(_riderId)
        .snapshots()
        .listen((snap) async {
      final m = snap.data();
      if (m == null) return;
      final pos = _latLngFromDoc(m);
      if (pos == null) return;

      _updateRiderMarker(pos);
      await _maybeMoveCamera(pos);
      _autoFlipWhenArrived();
      _debouncedUpdateRoute();
    });
  }

  LatLng? _latLngFromDoc(Map<String, dynamic> m) {
    final g = m['last_geo'];
    if (g is GeoPoint) return LatLng(g.latitude, g.longitude);
    final loc = m['last_location'];
    if (loc is Map) {
      final lat = (loc['lat'] as num?)?.toDouble();
      final lng = (loc['lng'] as num?)?.toDouble();
      if (lat != null && lng != null) return LatLng(lat, lng);
    }
    return null;
  }

  // ===== Icons =====
  Future<void> _loadCustomIcons() async {
    _senderIcon = await _mkIcon(Icons.upload_rounded, _orange);
    _receiverIcon = await _mkIcon(Icons.download_rounded, _green);
    _riderIcon = await _mkIcon(Icons.delivery_dining, _blue);
  }

  Future<BitmapDescriptor> _mkIcon(IconData icon, Color color) async {
    const size = 120.0;
    final pr = ui.PictureRecorder();
    final c = Canvas(pr);

    // shadow
    c.drawCircle(
      Offset(size / 2, size / 2 + 2),
      size / 2.5,
      Paint()
        ..color = Colors.black.withOpacity(0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    // bg
    c.drawCircle(
      Offset(size / 2, size / 2),
      size / 2.5,
      Paint()..color = color,
    );
    // border
    c.drawCircle(
      Offset(size / 2, size / 2),
      size / 2.5,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );
    // glyph
    final tp = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: size / 2.5,
          fontFamily: icon.fontFamily,
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      )
      ..layout();
    tp.paint(c, Offset((size - tp.width) / 2, (size - tp.height) / 2));

    final img = await pr.endRecording().toImage(size.toInt(), size.toInt());
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(data!.buffer.asUint8List());
  }

  // ===== Rider marker / camera =====
  void _updateRiderMarker(LatLng pos) {
    _riderPos = pos;
    _riderMarker = Marker(
      markerId: const MarkerId('rider'),
      position: pos,
      icon: _riderIcon ?? BitmapDescriptor.defaultMarker,
      infoWindow: const InfoWindow(title: '🏍️ ตำแหน่งไรเดอร์'),
      anchor: const Offset(0.5, 0.5),
      flat: true,
    );
    setState(() {});
  }

  Future<void> _maybeMoveCamera(LatLng pos) async {
    final now = DateTime.now();
    final far =
        (_riderPosPrev == null) ? true : _distM(_riderPosPrev!, pos) > 25.0;
    final elapsed = now.difference(_lastCameraMoveAt).inMilliseconds;
    if (far || elapsed > 1500) {
      final c = await _controller.future;
      _lastCameraMoveAt = now;
      _riderPosPrev = pos;
      await c.animateCamera(CameraUpdate.newLatLng(pos));
    }
  }

  // ===== Toggle / auto flip =====
  bool get _goingToSender => !_isPickedUp;

  LatLng? _currentDest() {
    if (_routeInfo == null) return null;
    return _goingToSender ? _routeInfo!.senderPos : _routeInfo!.receiverPos;
  }

  void _toggleTarget({bool? picked}) {
    setState(() {
      _isPickedUp = picked ?? !_isPickedUp;
      _lastRoutedFrom = null; // reset guard distance
      _polylines.clear();
      _routeVersion++;
    });
    _debouncedUpdateRoute(force: true);

    final to = _goingToSender ? 'ไป “จุดรับสินค้า”' : 'ไป “จุดส่งสินค้า”';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text('สลับเส้นทาง: $to'),
          duration: const Duration(seconds: 2)),
    );
  }

  void _autoFlipWhenArrived() {
    if (_routeInfo == null || _riderPos == null) return;
    if (_goingToSender) {
      final d = _distM(_riderPos!, _routeInfo!.senderPos);
      if (d < 40) _toggleTarget(picked: true); // ถึงจุดรับแล้ว → ไปส่ง
    }
  }

  // ===== Routing (OSRM) =====
  void _debouncedUpdateRoute({bool force = false}) {
    _routeDebounce?.cancel();
    _routeDebounce = Timer(const Duration(milliseconds: 200), () {
      _updateActiveRoute(force: force);
    });
  }

  Future<void> _updateActiveRoute({bool force = false}) async {
    if (_routingBusy || _riderPos == null) return;

    final dest = _currentDest() ??
        (_staticMarkers.isNotEmpty ? _staticMarkers.first.position : null);
    if (dest == null) return;

    if (!force &&
        _lastRoutedFrom != null &&
        _distM(_lastRoutedFrom!, _riderPos!) < _rerouteMinMoveM) {
      return;
    }
    _lastRoutedFrom = _riderPos;
    _routingBusy = true;

    debugPrint('[ROUTE] mode=${_goingToSender ? 'SENDER' : 'RECEIVER'} '
        'from=${_riderPos!.latitude},${_riderPos!.longitude} '
        'to=${dest.latitude},${dest.longitude}');

    try {
      final r = await _getOSRM(_riderPos!, dest);
      if (!mounted) return;
      final pts = (r['points'] as List<LatLng>? ?? const []);
      setState(() {
        final id = PolylineId('route_${_routeVersion++}');
        _polylines
          ..clear()
          ..add(
            Polyline(
              polylineId: id,
              points: pts.isNotEmpty ? pts : [_riderPos!, dest],
              width: 7,
              geodesic: true,
              color: Colors.blue,
              zIndex: 1000,
            ),
          );

        final dur = (r['duration'] as num?)?.toDouble() ?? 0;
        final dis = (r['distance'] as num?)?.toDouble() ?? 0;
        _etaMin = dur > 0 ? dur / 60.0 : null;
        _distKm = dis > 0 ? dis / 1000.0 : null;
      });
    } catch (e) {
      debugPrint('[ROUTE] error: $e');
    } finally {
      _routingBusy = false;
      _autoFlipWhenArrived();
    }
  }

  Future<Map<String, dynamic>> _getOSRM(LatLng a, LatLng b) async {
    final coords = '${a.longitude},${a.latitude};${b.longitude},${b.latitude}';
    final uri = Uri.https(
      'router.project-osrm.org',
      '/route/v1/driving/$coords',
      {
        'overview': 'full',
        'geometries': 'geojson',
        'steps': 'false',
      },
    );
    final res = await http.get(uri).timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) {
      throw Exception('OSRM ${res.statusCode}');
    }
    final data = jsonDecode(res.body);
    final routes = (data['routes'] as List);
    if (routes.isEmpty) {
      return {'points': <LatLng>[], 'duration': 0.0, 'distance': 0.0};
    }
    final route = routes.first as Map;
    final coordsList = ((route['geometry'] as Map)['coordinates'] as List);
    final points = <LatLng>[
      for (final c in coordsList)
        LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
    ];
    return {
      'points': points,
      'duration': (route['duration'] as num?)?.toDouble() ?? 0.0,
      'distance': (route['distance'] as num?)?.toDouble() ?? 0.0,
    };
  }

  double _distM(LatLng a, LatLng b) {
    const p = 0.017453292519943295;
    final c1 = cos((b.latitude - a.latitude) * p);
    final c2 = cos(a.latitude * p);
    final c3 = cos(b.latitude * p);
    final c4 = 1 - cos((b.longitude - a.longitude) * p);
    final A = 0.5 - c1 / 2 + c2 * c3 * c4 / 2;
    return 12742 * asin(sqrt(A)) * 1000.0;
  }

  Future<LatLng?> _ensurePermissionAndGetCurrent({bool logNow = false}) async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        await Geolocator.openLocationSettings();
        return null;
      }
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) {
        p = await Geolocator.requestPermission();
      }
      if (p == LocationPermission.deniedForever) {
        await Geolocator.openAppSettings();
        return null;
      }
      Position pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.best,
          timeLimit: const Duration(seconds: 8),
        );
      } on TimeoutException {
        final last = await Geolocator.getLastKnownPosition();
        if (last == null) return null;
        pos = last;
      }
      if (logNow) {
        debugPrint(
            '[LOC] ${pos.latitude}, ${pos.longitude} acc=${pos.accuracy}m');
      }
      return LatLng(pos.latitude, pos.longitude);
    } catch (e) {
      debugPrint('[LOC] error: $e');
      return null;
    }
  }

  Future<void> _fitBoundsToRoute() async {
    if (_routeInfo == null) return;
    final c = await _controller.future;
    final sw = LatLng(
      (_routeInfo!.senderPos.latitude <= _routeInfo!.receiverPos.latitude)
          ? _routeInfo!.senderPos.latitude
          : _routeInfo!.receiverPos.latitude,
      (_routeInfo!.senderPos.longitude <= _routeInfo!.receiverPos.longitude)
          ? _routeInfo!.senderPos.longitude
          : _routeInfo!.receiverPos.longitude,
    );
    final ne = LatLng(
      (_routeInfo!.senderPos.latitude >= _routeInfo!.receiverPos.latitude)
          ? _routeInfo!.senderPos.latitude
          : _routeInfo!.receiverPos.latitude,
      (_routeInfo!.senderPos.longitude >= _routeInfo!.receiverPos.longitude)
          ? _routeInfo!.senderPos.longitude
          : _routeInfo!.receiverPos.longitude,
    );
    await c.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(southwest: sw, northeast: ne),
        100,
      ),
    );
  }

  // ===== UI =====
  @override
  Widget build(BuildContext context) {
    final init = _initialCenter ?? const LatLng(13.736717, 100.523186);
    final markers = <Marker>{
      ..._staticMarkers,
      if (_riderMarker != null) _riderMarker!,
    };

    return Scaffold(
      appBar: customAppBar(),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(target: init, zoom: 14),
            markers: markers,
            polylines: _polylines,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            onMapCreated: (c) => _controller.complete(c),
          ),
          if (_routeInfo != null)
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: _BubbleRouteCard(
                goingToSender: _goingToSender,
                senderName: _routeInfo!.senderName,
                receiverName: _routeInfo!.receiverName,
                senderAddrText: _routeInfo!.senderAddrText,
                receiverAddrText: _routeInfo!.receiverAddrText,
                etaMin: _etaMin,
                distKm: _distKm,
              ),
            ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Toggle sender/receiver
          FloatingActionButton(
            heroTag: 'toggle',
            backgroundColor: _red,
            onPressed: () => _toggleTarget(),
            child: const Icon(Icons.directions_car_filled_rounded, size: 26),
          ),
          const SizedBox(height: 12),
          // Jump to my location
          FloatingActionButton(
            heroTag: 'my',
            backgroundColor: _blue,
            onPressed: () async {
              final loc = await _ensurePermissionAndGetCurrent(logNow: true);
              if (loc == null) return;
              if (_riderId != null && _riderId!.isNotEmpty) {
                await _sender.updateOnce(
                  riderId: _riderId!,
                  lat: loc.latitude,
                  lng: loc.longitude,
                );
              }
              _updateRiderMarker(loc);
              final c = await _controller.future;
              await c.animateCamera(CameraUpdate.newLatLngZoom(loc, 16));
              _debouncedUpdateRoute(force: true);
            },
            child: const Icon(Icons.my_location),
          ),
          const SizedBox(height: 12),
          if (_routeInfo != null)
            FloatingActionButton(
              heroTag: 'fit',
              backgroundColor: _grey,
              onPressed: () {
                _debouncedUpdateRoute(force: true);
                _fitBoundsToRoute();
              },
              child: const Icon(Icons.fullscreen_rounded, size: 22),
            ),
        ],
      ),
    );
  }
}

// ===== UI bits =====
class _BubbleRouteCard extends StatelessWidget {
  final bool goingToSender;
  final String senderName, receiverName;
  final String? senderAddrText, receiverAddrText;
  final double? etaMin, distKm;

  const _BubbleRouteCard({
    required this.goingToSender,
    required this.senderName,
    required this.receiverName,
    this.senderAddrText,
    this.receiverAddrText,
    this.etaMin,
    this.distKm,
  });

  @override
  Widget build(BuildContext context) {
    final title = goingToSender ? 'เส้นทางไปรับสินค้า' : 'เส้นทางไปส่งสินค้า';
    final name = goingToSender ? senderName : receiverName;
    final addr = goingToSender ? senderAddrText : receiverAddrText;

    return Material(
      color: Colors.transparent,
      elevation: 8,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              name,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            if ((addr ?? '').isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                addr!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                if (etaMin != null)
                  _Pill(
                      icon: Icons.schedule_rounded,
                      text: '${etaMin!.ceil()} นาที'),
                if (etaMin != null && distKm != null) const SizedBox(width: 8),
                if (distKm != null)
                  _Pill(
                    icon: Icons.social_distance_rounded,
                    text: '${distKm!.toStringAsFixed(1)} กม.',
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Pill({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF475569)),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF334155),
            ),
          ),
        ],
      ),
    );
  }
}

// ===== Data class =====
class _RouteInfo {
  final LatLng senderPos, receiverPos;
  final String senderName, receiverName;
  final String? senderAddrText, receiverAddrText;

  _RouteInfo({
    required this.senderPos,
    required this.receiverPos,
    required this.senderName,
    required this.receiverName,
    this.senderAddrText,
    this.receiverAddrText,
  });
}
