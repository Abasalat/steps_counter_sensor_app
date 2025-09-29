import 'package:flutter/material.dart';

class StatusTile extends StatelessWidget {
  final String title;
  final String value;
  const StatusTile({super.key, required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      trailing: Text(value),
    );
  }
}
