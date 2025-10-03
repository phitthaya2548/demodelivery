// lib/models/user_address.dart
class UserAddress {
  final String id;
  final String userId;
  final String nameLabel; // บ้าน/หอ/ที่ทำงาน
  final String addressText;
  final double? lat;
  final double? lng;
  final bool isDefault;

  UserAddress({
    required this.id,
    required this.userId,
    required this.nameLabel,
    required this.addressText,
    this.lat,
    this.lng,
    this.isDefault = false,
  });

  factory UserAddress.fromJson(String id, Map<String, dynamic> m,
          {required String userId}) =>
      UserAddress(
        id: id,
        userId: userId,
        nameLabel: (m['name'] ?? m['name_address'] ?? 'บ้าน') as String,
        addressText: (m['address_text'] ?? '') as String,
        lat: (m['gps']?['lat'] ?? m['gps_lat'])?.toDouble(),
        lng: (m['gps']?['lng'] ?? m['gps_lng'])?.toDouble(),
        isDefault: (m['is_default'] ?? false) as bool,
      );

  Map<String, dynamic> toJson() => {
        'name': nameLabel,
        'address_text': addressText,
        'gps': (lat != null && lng != null) ? {'lat': lat, 'lng': lng} : null,
        'is_default': isDefault,
      }..removeWhere((k, v) => v == null);
}
