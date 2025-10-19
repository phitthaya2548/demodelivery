// lib/pages/riders/bottom_rider.dart
import 'package:deliverydomo/pages/riders/home_rider.dart';
import 'package:deliverydomo/pages/riders/list_rider.dart';
import 'package:deliverydomo/pages/riders/map_rider.dart';
import 'package:deliverydomo/pages/riders/profile_rider.dart';
// ถ้ามี SessionStore ใช้อยู่แล้ว ให้ import มาด้วย
import 'package:deliverydomo/pages/sesstion.dart';
import 'package:flutter/material.dart';

class BottomRider extends StatefulWidget {
  const BottomRider({
    Key? key,
    this.initialIndex =
        0, // ✅ เลือกแท็บเริ่มต้นจากภายนอกได้ (0:Home, 1:Order, 2:Map, 3:Profile)
  }) : super(key: key);

  final int initialIndex;

  @override
  _BottomRiderState createState() => _BottomRiderState();
}

class _BottomRiderState extends State<BottomRider> {
  late int _selectedIndex;
  int _rebuildSeed = 0; // เปลี่ยนค่านี้เพื่อบังคับรีบิลด์หน้าเดิม

  // ✅ ดึง riderId จาก session (ปรับให้ตรงกับโปรเจกต์คุณได้)
  String get _riderId {
    final uid = (SessionStore.userId ?? '').toString().trim();
    final phone = (SessionStore.phoneId ?? '').toString().trim();
    // เลือก uid ก่อน ถ้าไม่มีค่อย fallback เป็น phone
    return uid.isNotEmpty ? uid : phone;
  }

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex.clamp(0, 3);
  }

  void _onItemTapped(int index) {
    setState(() {
      if (index == _selectedIndex) {
        // กดแท็บเดิมซ้ำ -> รีโหลดหน้าเดิม
        _rebuildSeed++;
      } else {
        // เปลี่ยนแท็บ -> สร้างหน้าของแท็บใหม่นั้นขึ้นมาใหม่
        _selectedIndex = index;
      }
    });
  }

  // สร้างหน้าใหม่ตาม index ทุกครั้ง (ไม่ใช้ IndexedStack)
  Widget _buildPage() {
    final key = ValueKey('tab$_selectedIndex-$_rebuildSeed');

    switch (_selectedIndex) {
      case 0:
        return HomeRider(key: key);

      case 1:
        return ListRider(key: key);

      case 2:
        // ✅ กันพื้นที่ล่างให้ MapRider เพื่อไม่ให้โดน BottomNavigationBar บัง
        // ความสูง BottomNav ในไฟล์นี้ตั้งไว้ 100 จึงส่ง bottomReserved: 100
        return MapRider(
          key: key,
         
        );

      case 3:
        return ProfileRider(key: key);

      default:
        return HomeRider(key: key);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _buildPage(), // เปลี่ยนหน้าแล้ว “รันใหม่” ทุกครั้ง
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.blueAccent,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(40),
            topRight: Radius.circular(40),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              spreadRadius: 2,
              blurRadius: 10,
            ),
          ],
        ),
        height: 100,
        child: ClipRRect(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(40),
            topRight: Radius.circular(40),
          ),
          child: BottomNavigationBar(
            currentIndex: _selectedIndex,
            onTap: _onItemTapped,
            selectedItemColor: Colors.orange,
            unselectedItemColor: Colors.grey,
            showSelectedLabels: true,
            showUnselectedLabels: true,
            type: BottomNavigationBarType.fixed,
            elevation: 15,
            backgroundColor: Colors.white,
            items: const <BottomNavigationBarItem>[
              BottomNavigationBarItem(
                icon: ImageIcon(AssetImage('assets/icons/home.png')),
                label: 'Home',
              ),
              BottomNavigationBarItem(
                icon: ImageIcon(AssetImage('assets/icons/list.png')),
                label: 'Order',
              ),
              BottomNavigationBarItem(
                icon: ImageIcon(AssetImage('assets/icons/map.png')),
                label: 'Map',
              ),
              BottomNavigationBarItem(
                icon: ImageIcon(AssetImage('assets/icons/profile.png')),
                label: 'Profile',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// หน้ากันไว้เมื่อยังไม่มี riderId ใน session (ให้ผู้ใช้ล็อกอินหรือเริ่มงานก่อน)
class _NeedRiderIdScreen extends StatelessWidget {
  const _NeedRiderIdScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'ยังไม่พบรหัสไรเดอร์ในเซสชัน\nกรุณาเข้าสู่ระบบ/เริ่มงานก่อนใช้งานแผนที่',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
