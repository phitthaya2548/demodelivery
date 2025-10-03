class Rider {
  final int? riderId;           // rider_id (PK)
  final String phoneNumber;     // phone_number
  final String password;        // password (ควรเป็น hash)
  final String name;            // name
  final String? profileImage;   // profile_image
  final String? vehicleImage;   // vehicle_image
  final String? licensePlate;   // license_plate

  const Rider({
    this.riderId,
    required this.phoneNumber,
    required this.password,
    required this.name,
    this.profileImage,
    this.vehicleImage,
    this.licensePlate,
  });

  factory Rider.fromMap(Map<String, dynamic> m) => Rider(
    riderId: m['rider_id'] as int?,
    phoneNumber: m['phone_number'] as String,
    password: m['password'] as String,
    name: m['name'] as String,
    profileImage: m['profile_image'] as String?,
    vehicleImage: m['vehicle_image'] as String?,
    licensePlate: m['license_plate'] as String?,
  );

  Map<String, dynamic> toMap() => {
    if (riderId != null) 'rider_id': riderId,
    'phone_number': phoneNumber,
    'password': password,
    'name': name,
    'profile_image': profileImage,
    'vehicle_image': vehicleImage,
    'license_plate': licensePlate,
  }..removeWhere((k, v) => v == null);
}
