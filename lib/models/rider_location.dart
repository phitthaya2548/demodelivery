DateTime? _dtOrNull(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  return DateTime.tryParse(v.toString());
}

class RiderLocation {
  final int riderId;
  final double lat;
  final double lng;
  final DateTime? updatedAt;

  const RiderLocation({
    required this.riderId,
    required this.lat,
    required this.lng,
    this.updatedAt,
  });

  factory RiderLocation.fromMap(Map<String, dynamic> m) => RiderLocation(
    riderId: m['rider_id'] as int,
    lat: (m['lat'] as num).toDouble(),
    lng: (m['lng'] as num).toDouble(),
    updatedAt: _dtOrNull(m['updated_at']),
  );

  Map<String, dynamic> toMap() => {
    'rider_id': riderId,
    'lat': lat,
    'lng': lng,
    'updated_at': updatedAt?.toIso8601String(),
  }..removeWhere((k, v) => v == null);
}
