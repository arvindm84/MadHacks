import 'package:flutter/material.dart';
import '../models/poi.dart';

class POIListItem extends StatelessWidget {
  final POI poi;

  const POIListItem({super.key, required this.poi});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF667eea).withOpacity(0.2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        title: Text(
          poi.displayName,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        trailing: poi.distance != null
            ? Text(
                '${poi.distance!.round()}m',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                ),
              )
            : null,
      ),
    );
  }
}
