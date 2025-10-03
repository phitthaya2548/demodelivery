// lib/models/shipment.dart
class Shipment {
  final String id;
  final String senderId;
  final String receiverId;
  final String pickupAddressId;
  final String deliveryAddressId;
  final String? riderId;
  final String itemDescription;
  final String? itemName;
  final int status; // 1..4

  Shipment({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.pickupAddressId,
    required this.deliveryAddressId,
    this.riderId,
    required this.itemDescription,
    this.itemName,
    required this.status,
  });

  factory Shipment.fromJson(String id, Map<String,dynamic> m) => Shipment(
    id: id,
    senderId: (m['sender_id'] ?? '') as String,
    receiverId: (m['receiver_id'] ?? '') as String,
    pickupAddressId: (m['pickup_address_id'] ?? '') as String,
    deliveryAddressId: (m['delivery_address_id'] ?? '') as String,
    riderId: m['rider_id'] as String?,
    itemDescription: (m['item_description'] ?? '') as String,
    itemName: m['item_name'] as String?,
    status: (m['status'] is int) ? m['status'] : int.parse(m['status'].toString()),
  );

  Map<String, dynamic> toJson() => {
    'sender_id': senderId,
    'receiver_id': receiverId,
    'pickup_address_id': pickupAddressId,
    'delivery_address_id': deliveryAddressId,
    'rider_id': riderId,
    'item_description': itemDescription,
    'item_name': itemName,
    'status': status,
  }..removeWhere((k, v) => v == null);
}
