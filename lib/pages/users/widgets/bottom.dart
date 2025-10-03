import 'package:deliverydomo/pages/users/home_user.dart';
import 'package:deliverydomo/pages/users/listorder_user.dart';
import 'package:deliverydomo/pages/users/profile_users.dart';
import 'package:flutter/material.dart';

class BottomUser extends StatefulWidget {
  @override
  _BottomUserState createState() => _BottomUserState();
}

class _BottomUserState extends State<BottomUser> {
  int _selectedIndex = 0;

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  Widget _getPage(int index) {
    switch (index) {
      case 0:
        return const HomeUser();
      case 1:
        return const ListorderUser();
      case 2:
        return const ProfileUser();
      default:
        return const HomeUser();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _getPage(_selectedIndex), // ❌ เอา IndexedStack ออก
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
