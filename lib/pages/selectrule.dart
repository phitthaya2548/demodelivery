import 'package:deliverydomo/pages/register_rider.dart';
import 'package:deliverydomo/pages/register_user.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// หน้าเลือกประเภทสมาชิก
class SelectMemberTypePage extends StatelessWidget {
  const SelectMemberTypePage({super.key});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final h = MediaQuery.of(context).size.height;

    Widget logo() => Column(
          children: [
            const Icon(Icons.delivery_dining, color: Colors.white, size: 92),
            const SizedBox(height: 8),
            const Text(
              'DELIVERY',
              style: TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
          ],
        );

    Widget title() => Text(
          'เลือกประเภทสมาชิก',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.orange[800],
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        );

    Widget orangeButton(String text, VoidCallback onPressed) => SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFD8700),
              elevation: 6,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shadowColor: Colors.black26,
            ),
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        );

    void goUser() {
      Get.to(() => RegisterUser());
    }

    void goRider() {
      Get.to(() => RegisterRider());
    }

/*************  ✨ Windsurf Command ⭐  *************/
    /// ไปยังหน้าสมัครไรเดอร์
/*******  77bcff55-54c5-4eea-b004-a341335269e3  *******/ void goBack() {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    }

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFFD8700), Color(0xFFFFDE98)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: w * 0.1),
            child: Column(
              children: [
                logo(),
                SizedBox(height: h * 0.03),
                Card(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18)),
                  elevation: 6,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
                    child: Column(
                      children: [
                        title(),
                        const SizedBox(height: 16),
                        orangeButton('สมัครผู้ใช้', goUser),
                        const SizedBox(height: 12),
                        orangeButton('สมัครไรเดอร์', goRider),
                        const SizedBox(height: 4),
                        TextButton(
                          onPressed: goBack,
                          child: const Text(
                            'ย้อนกลับ',
                            style: TextStyle(
                              color: Color(0xFFFD8700),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: h * 0.04),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
