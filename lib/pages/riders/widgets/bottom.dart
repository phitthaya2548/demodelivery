
import 'package:deliverydomo/pages/riders/home_rider.dart';
import 'package:deliverydomo/pages/riders/list_rider.dart';
import 'package:deliverydomo/pages/riders/map_rider.dart';
import 'package:deliverydomo/pages/riders/profile_rider.dart';
import 'package:flutter/material.dart';

class BottomRider extends StatefulWidget {
  @override
  _BottomRiderState createState() => _BottomRiderState();
}

class _BottomRiderState extends State<BottomRider> {
  int _selectedIndex = 0;
  int _rebuildSeed = 0; // เปลี่ยนค่านี้เพื่อบังคับรีบิลด์หน้าเดิม

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
        return MapRider(key: key);
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
