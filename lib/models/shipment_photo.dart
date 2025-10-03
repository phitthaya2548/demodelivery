// lib/models/shipment_photo.dart
class ShipmentPhoto {
  final String id;
  final String shipmentId;
  final String? riderId;
  final int status;        // 1/3/4 ตามโจทย์
  final String photoUrl;

  ShipmentPhoto({
    required this.id,
    required this.shipmentId,
    this.riderId,
    required this.status,
    required this.photoUrl,
  });

  factory ShipmentPhoto.fromJson(String id, String shipmentId, Map<String, dynamic> m) =>
      ShipmentPhoto(
        id: id,
        shipmentId: shipmentId,
        riderId: m['rider_id'] as String?,
        status: (m['status'] is int) ? m['status'] : int.parse(m['status'].toString()),
        photoUrl: m['photo_url'] as String,
      );

  Map<String, dynamic> toJson() => {
    'rider_id': riderId,
    'status': status,
    'photo_url': photoUrl,
  }..removeWhere((k, v) => v == null);
}
