// class UserProfile {
//   final String id; // ใช้ phone เป็น docId
//   final String phone;
//   final String name;
//   final String? photoUrl;
//   final String passwordHash; // เก็บเฉพาะแฮช
//   const UserProfile({
//     required this.id,
//     required this.phone,
//     required this.name,
//     required this.passwordHash,
//     this.photoUrl,
//   });

//   factory UserProfile.fromJson(String id, Map<String, dynamic> m) =>
//       UserProfile(
//         id: id,
//         phone: m['phone'] ?? '',
//         name: m['name'] ?? '',
//         photoUrl: m['photoUrl'],
//         passwordHash: m['password_hash'] ?? '',
//       );

//   Map<String, dynamic> toJson() => {
//         'phone': phone,
//         'name': name,
//         'photoUrl': photoUrl,
//         'password_hash': passwordHash,
//       }..removeWhere((k, v) => v == null);
// }
