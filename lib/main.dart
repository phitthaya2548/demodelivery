// Flutter & Firebase
// Pages
import 'package:deliverydomo/pages/login.dart';
import 'package:deliverydomo/pages/riders/widgets/bottom.dart';
import 'package:deliverydomo/pages/sesstion.dart';
import 'package:deliverydomo/pages/users/widgets/bottom.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter_android/google_maps_flutter_android.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await SessionStore.init();

  final GoogleMapsFlutterPlatform mapsImpl = GoogleMapsFlutterPlatform.instance;
  if (mapsImpl is GoogleMapsFlutterAndroid) {
    mapsImpl.useAndroidViewSurface = true;
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Delivery',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFD8700)),
        scaffoldBackgroundColor: const Color(0xFFFFF5E8),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFD8700),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      home: const _Bootstrap(),
      getPages: [
        GetPage(name: '/login', page: () => const LoginPage()),
        GetPage(name: '/user', page: () => BottomUser()),
        GetPage(name: '/rider', page: () => BottomRider()),
      ],
    );
  }
}

/// หน้า Bootstrap เล็ก ๆ ตัดสินใจนำทางด้วย Get.to หลังเฟรมแรก
class _Bootstrap extends StatefulWidget {
  const _Bootstrap({super.key});
  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final role = SessionStore.role; // 'USER' | 'RIDER' | null
      if (role == 'USER') {
        Get.to(() => BottomUser());
      } else if (role == 'RIDER') {
        Get.to(() => BottomRider());
      } else {
        Get.to(() => const LoginPage());
      }

      // ถ้าอยากกัน back ให้ใช้ Get.offAll(...)
      // เช่น: Get.offAll(() => BottomUser());
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
