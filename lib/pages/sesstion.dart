import 'package:get_storage/get_storage.dart';

class AuthSession {
  final String role;        // 'USER' | 'RIDER' | 'ADMIN' ...
  final String userId;      // แนะนำให้เป็น string (ใช้เบอร์โทรเป็น id)
  final String fullname;
  final String phoneId;     // เบอร์โทรแบบ normalize แล้ว

  const AuthSession({
    required this.role,
    required this.userId,
    required this.fullname,
    required this.phoneId,
  });

  Map<String, dynamic> toMap() => {
        'role': role,
        'userId': userId,
        'fullname': fullname,
        'phoneId': phoneId,
      };

  factory AuthSession.fromMap(Map<String, dynamic> m) => AuthSession(
        role: (m['role'] ?? '') as String,
        userId: (m['userId'] ?? '') as String,
        fullname: (m['fullname'] ?? '') as String,
        phoneId: (m['phoneId'] ?? '') as String,
      );
}

class SessionStore {
  static const _boxName = 'app_session';
  static const _keyAuth = 'auth';
  static const _keyProfile = 'profile'; // ใช้กรณีอยากเก็บข้อมูลโปรไฟล์เพิ่มเติม

  static final GetStorage _box = GetStorage(_boxName);

  /// ต้องเรียกใน main(): await SessionStore.init();
  static Future<void> init() async {
    await GetStorage.init(_boxName);
  }

  // ---------- AUTH ----------
  static Future<void> saveAuth(AuthSession s) async {
    await _box.write(_keyAuth, s.toMap());
  }

  static AuthSession? getAuth() {
    final raw = _box.read(_keyAuth);
    if (raw is Map) {
      return AuthSession.fromMap(Map<String, dynamic>.from(raw));
    }
    return null;
  }

  static bool get isLoggedIn => getAuth() != null;

  static String? get role => getAuth()?.role;
  static String? get userId => getAuth()?.userId;
  static String? get fullname => getAuth()?.fullname;
  static String? get phoneId => getAuth()?.phoneId;

  static Future<void> clearAuth() => _box.remove(_keyAuth);

  // ---------- PROFILE (ออปชัน) ----------
  static Future<void> saveProfile(Map<String, dynamic> profile) async {
    await _box.write(_keyProfile, profile);
  }

  static Map<String, dynamic>? getProfile() {
    final raw = _box.read(_keyProfile);
    return raw == null ? null : Map<String, dynamic>.from(raw);
  }

  static Future<void> clearAll() => _box.erase();
}
