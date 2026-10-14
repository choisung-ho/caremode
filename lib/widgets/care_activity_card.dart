import 'package:flutter/material.dart';

class CareActivityCard extends StatelessWidget {
  final String time;
  final String title;
  final String desc;
  final IconData icon;
  final bool isAlert; // 주의가 필요한 항목인가?

  const CareActivityCard({
    super.key,
    required this.time,
    required this.title,
    required this.desc,
    required this.icon,
    this.isAlert = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isAlert ? const Color(0xFFFFF4E5) : Colors.white, // 경고면 연한 주황색
        borderRadius: BorderRadius.circular(16),
        border: isAlert ? Border.all(color: Colors.orangeAccent) : null,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 13),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 왼쪽 아이콘
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isAlert
                  ? Colors.orangeAccent
                  : Colors.teal.withValues(alpha: 26),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: isAlert ? Colors.white : Colors.teal,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),

          // 내용
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isAlert ? Colors.deepOrange : Colors.black87,
                      ),
                    ),
                    Text(
                      time,
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  desc,
                  style: TextStyle(
                    color: Colors.grey[700],
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
