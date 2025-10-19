// lib/data/shipment_detail_api.dart
import 'package:cloud_firestore/cloud_firestore.dart';

/// ---- Models ----

class GeoCoord {
  final double lat;
  final double lng;
  const GeoCoord(this.lat, this.lng);

  factory GeoCoord.fromGeoPoint(GeoPoint gp) =>
      GeoCoord(gp.latitude, gp.longitude);
}

class AddressInfo {
  final String? id;
  final String text; // address_text หรือ detail ที่ resolve แล้ว
  final GeoCoord? geo; // lat/lng ที่ resolve แล้ว

  const AddressInfo({this.id, required this.text, this.geo});

  AddressInfo copyWith({String? id, String? text, GeoCoord? geo}) {
    return AddressInfo(
      id: id ?? this.id,
      text: text ?? this.text,
      geo: geo ?? this.geo,
    );
  }
}

class PersonInfo {
  final String name;
  final String phone;
  final String avatarUrl;
  final AddressInfo address;

  const PersonInfo({
    required this.name,
    required this.phone,
    required this.avatarUrl,
    required this.address,
  });
}

class ShipmentDetail {
  final String id;
  final int status;
  final String itemName;
  final String itemDesc;
  final String photoUrl;

  final PersonInfo sender;
  final PersonInfo receiver;

  const ShipmentDetail({
    required this.id,
    required this.status,
    required this.itemName,
    required this.itemDesc,
    required this.photoUrl,
    required this.sender,
    required this.receiver,
  });
}

/// ---- API ----

class ShipmentDetailApi {
  ShipmentDetailApi({FirebaseFirestore? firestore})
      : _fs = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _fs;

  Map<String, dynamic> _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return v.map((k, v) => MapEntry(k.toString(), v));
    return <String, dynamic>{};
  }

  String _pickFrom(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = (m[k] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  /// รองรับทั้ง GeoPoint และ Map {latitude/_latitude/lat, longitude/_longitude/lng}
  GeoPoint? _toGeoPoint(dynamic v) {
    if (v == null) return null;
    if (v is GeoPoint) return v;
    final m = _asMap(v);
    if (m.isEmpty) return null;
    final lat = (m['latitude'] ?? m['_latitude'] ?? m['lat']);
    final lng = (m['longitude'] ?? m['_longitude'] ?? m['lng']);
    if (lat is num && lng is num)
      return GeoPoint(lat.toDouble(), lng.toDouble());
    return null;
  }

  /// ดึง GeoPoint จาก key มาตรฐานที่มักใช้กับ address snapshot
  GeoPoint? _extractGeoPointDeep(dynamic raw) {
    // ตรงๆ
    final direct = _toGeoPoint(raw);
    if (direct != null) return direct;
    final m = _asMap(raw);
    if (m.isEmpty) return null;
    for (final k in const ['location', 'geopoint', 'geo']) {
      final gp = _toGeoPoint(m[k]);
      if (gp != null) return gp;
    }
    // fallback lat/lng ชั้นเดียว
    return _toGeoPoint(m);
  }

  Future<Map<String, dynamic>?> _getAddressDoc(String id) async {
    if (id.isEmpty) return null;
    final snap = await _fs.collection('addressuser').doc(id).get();
    return snap.data();
  }

  String _resolveAddressText(Map<String, dynamic> addrLike) {
    return (addrLike['detail'] ?? addrLike['address_text'] ?? '').toString();
  }

  Future<ShipmentDetail?> getShipmentDetailOnce(String shipmentId) async {
    final snap = await _fs.collection('shipments').doc(shipmentId).get();
    if (!snap.exists) return null;
    return await _buildDetailFromDoc(snap.id, snap.data() ?? {});
  }

  Stream<ShipmentDetail?> watchShipmentDetail(String shipmentId) {
    return _fs.collection('shipments').doc(shipmentId).snapshots().asyncMap(
      (doc) async {
        if (!doc.exists) return null;
        return await _buildDetailFromDoc(doc.id, doc.data() ?? {});
      },
    );
  }

  Future<String> _findLiveUserAvatar({String? uid, String? phone}) async {
    try {
      // 1) ลองด้วย uid ตรง ๆ
      final u = (uid ?? '').trim();
      if (u.isNotEmpty) {
        final doc = await _fs.collection('users').doc(u).get();
        final m = doc.data() ?? {};
        final v = (m['photoUrl'] ?? m['photo_url'] ?? '').toString().trim();
        if (v.startsWith('http')) return v;
      }

      // 2) ลองด้วย phone แบบ exact match
      final p = (phone ?? '').trim();
      if (p.isNotEmpty) {
        final q = await _fs
            .collection('users')
            .where('phone', isEqualTo: p)
            .limit(1)
            .get();
        if (q.docs.isNotEmpty) {
          final m = q.docs.first.data();
          final v = (m['photoUrl'] ?? '').toString().trim();
          if (v.startsWith('http')) return v;
        }
      }
    } catch (_) {}
    return '';
  }

  Future<ShipmentDetail> _buildDetailFromDoc(
    String id,
    Map<String, dynamic> data,
  ) async {
    final statusRaw = data['status'];
    final status =
        (statusRaw is int) ? statusRaw : int.tryParse('$statusRaw') ?? 0;

    final itemName = (data['item_name'] ?? data['itemName'] ?? '-').toString();
    final itemDesc =
        (data['item_description'] ?? data['itemDescription'] ?? '').toString();
    final photoUrl =
        (data['last_photo_url'] ?? data['photo_url'] ?? '').toString();

    // sender / receiver snapshots
    final sender = _asMap(data['sender_snapshot'] ?? data['sender']);
    final receiver = _asMap(data['receiver_snapshot'] ?? data['receiver']);

    // 1) Sender resolve
    final pickupAddrSnap = _asMap(sender['pickup_address']);
    String pickupText = _resolveAddressText(pickupAddrSnap);
    GeoPoint? pickupGeo = _extractGeoPointDeep(pickupAddrSnap);

    final pickupId =
        (sender['pickup_address_id'] ?? data['pickup_address_id'] ?? '')
            .toString();
    if ((pickupText.isEmpty || pickupGeo == null) && pickupId.isNotEmpty) {
      final ad = await _getAddressDoc(pickupId) ?? {};
      if (pickupText.isEmpty) pickupText = _resolveAddressText(ad);
      pickupGeo ??= _extractGeoPointDeep(ad);
    }

    final sName = sender['name'].toString();
    final sPhone = (sender['phone'] ?? sender['phone_number'] ?? '').toString();
    String sAvatar = await _findLiveUserAvatar(phone: sPhone);

    final senderInfo = PersonInfo(
      name: sName,
      phone: sPhone,
      avatarUrl: sAvatar,
      address: AddressInfo(
        id: pickupId.isEmpty ? null : pickupId,
        text: pickupText,
        geo: pickupGeo != null ? GeoCoord.fromGeoPoint(pickupGeo) : null,
      ),
    );

    // 2) Receiver resolve (delivery_address_snapshot OR receiver.address)
    final deliverySnap = _asMap(data['delivery_address_snapshot'] ?? {});
    final recvAddrSnap =
        deliverySnap.isNotEmpty ? deliverySnap : _asMap(receiver['address']);

    String recvText = _resolveAddressText(recvAddrSnap);
    GeoPoint? recvGeo = _extractGeoPointDeep(recvAddrSnap);

    final deliveryId =
        (receiver['address_id'] ?? data['delivery_address_id'] ?? '')
            .toString();
    if ((recvText.isEmpty || recvGeo == null) && deliveryId.isNotEmpty) {
      final ad = await _getAddressDoc(deliveryId) ?? {};
      if (recvText.isEmpty) recvText = _resolveAddressText(ad);
      recvGeo ??= _extractGeoPointDeep(ad);
    }

    final rName = _pickFrom(
        receiver, const ['display_name', 'name', 'fullname', 'full_name']);
    final rPhone =
        _pickFrom(receiver, const ['phone', 'phoneNumber', 'mobile', 'tel']);
    String rAvatar = await _findLiveUserAvatar(phone: rPhone);

    final receiverInfo = PersonInfo(
      name: rName,
      phone: rPhone,
      avatarUrl: rAvatar,
      address: AddressInfo(
        id: deliveryId.isEmpty ? null : deliveryId,
        text: recvText,
        geo: recvGeo != null ? GeoCoord.fromGeoPoint(recvGeo) : null,
      ),
    );

    return ShipmentDetail(
      id: id,
      status: status,
      itemName: itemName,
      itemDesc: itemDesc,
      photoUrl: photoUrl,
      sender: senderInfo,
      receiver: receiverInfo,
    );
  }
}
