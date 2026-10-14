import 'package:flutter/material.dart';

class TimelineCard extends StatelessWidget {
  final String time;
  final String title;
  final String desc;
  final IconData icon;

  const TimelineCard({
    super.key,
    required this.time,
    required this.title,
    required this.desc,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Icon(icon, color: Theme.of(context).colorScheme.primary),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(desc),
        trailing: Text(time, style: const TextStyle(color: Colors.grey)),
      ),
    );
  }
}
