import 'package:flutter/material.dart';

AppBar customAppBar() {
  return AppBar(
    toolbarHeight: 70,
    automaticallyImplyLeading: false,
    title: Row(
      children: [
        Image.asset(
          'assets/icons/logo.png',
          width: 60,
          height: 60,
        ), // Delivery icon
        SizedBox(width: 10), // Space between icon and title
        Text(
          'Delivery WarpSong',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ), // App name
      ],
    ),
    backgroundColor: Colors.transparent, // Transparent background for gradient
    elevation: 0, // Remove shadow
    flexibleSpace: Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFFD8700), Color(0xFFFFDE98)], // Gradient colors
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
    ),
  );
}
