// lib/models/gxho/shipment_models.dart
import 'package:cloud_firestore/cloud_firestore.dart';

Map<String, dynamic> _asMapLocal(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return v.map((k, v) => MapEntry(k.toString(), v));
  return <String, dynamic>{};
}

String _str(dynamic v, [String d = '']) => (v ?? d).toString();
int _toInt(dynamic v, [int d = 0]) =>
    (v is int) ? v : int.tryParse('${v ?? ''}') ?? d;

class PersonVM {
  PersonVM({
    required this.name,
    required this.phone,
    required this.immediateAvatar,
    required this.addressImmediate,
    required this.addressIdFallback,
    required this.uid,
  });

  final String name;
  final String phone;
  final String immediateAvatar;
  final String addressImmediate;
  final String addressIdFallback;
  final String uid;
}

class ShipmentVM {
  ShipmentVM({
    required this.id,
    required this.itemName,
    required this.itemDesc,
    required this.photoUrl,
    required this.status,
    required this.sender,
    required this.receiver,
  });

  final String id;
  final String itemName;
  final String itemDesc;
  final String photoUrl; // ใช้รูปสินค้าล่าสุด/รูปสินค้าเท่านั้น
  final int status;
  final PersonVM sender;
  final PersonVM receiver;

  factory ShipmentVM.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? <String, dynamic>{};

    // core
    final id = _str(m['id'], doc.id);
    final itemName = _str(m['item_name'], '-');
    final itemDesc = _str(m['item_description']);
    final photoUrl = _str(m['last_photo_url']); // ✅ รูปสินค้าเท่านั้น
    final status = _toInt(m['status']);

    // sender
    final senderMap = _asMapLocal(m['sender_snapshot']);
    final senderPickup = _asMapLocal(senderMap['pickup_address']);
    final senderAddrObj = _asMapLocal(senderMap['address']);
    final senderAddrImmediate = _str(
      senderPickup['detail'] ??
          senderPickup['address_text'] ??
          senderAddrObj['address_text'] ??
          '',
    );
    final senderAddrFallback = _str(
      senderMap['address_id'] ?? m['pickup_address_id'] ?? '',
    );
    final sender = PersonVM(
      name: _str(senderMap['name']),
      phone: _str(senderMap['phone']),
      immediateAvatar: _str(senderMap['photo_url']),
      addressImmediate: senderAddrImmediate,
      addressIdFallback: senderAddrFallback,
      uid: _str(senderMap['user_id']),
    );

    // receiver
    final receiverMap = _asMapLocal(m['receiver_snapshot']);
    final deliverySnap = _asMapLocal(m['delivery_address_snapshot']);
    final receiverAddrObj = _asMapLocal(receiverMap['address']);
    final receiverAddrImmediate = _str(
      deliverySnap['detail'] ??
          deliverySnap['address_text'] ??
          receiverAddrObj['address_text'] ??
          '',
    );
    final receiverAddrFallback = _str(
      receiverMap['address_id'] ?? m['delivery_address_id'] ?? '',
    );
    final receiver = PersonVM(
      name: _str(receiverMap['name']),
      phone: _str(receiverMap['phone']),
      immediateAvatar: _str(receiverMap['photo_url']),
      addressImmediate: receiverAddrImmediate,
      addressIdFallback: receiverAddrFallback,
      uid: _str(receiverMap['user_id']),
    );

    return ShipmentVM(
      id: id,
      itemName: itemName,
      itemDesc: itemDesc,
      photoUrl: photoUrl,
      status: status,
      sender: sender,
      receiver: receiver,
    );
  }
}
