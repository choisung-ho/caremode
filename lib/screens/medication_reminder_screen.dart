// lib/screens/medication_reminder_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MedicationReminderScreen extends StatefulWidget {
  const MedicationReminderScreen({super.key});

  @override
  State<MedicationReminderScreen> createState() =>
      _MedicationReminderScreenState();
}

class _MedicationReminderScreenState extends State<MedicationReminderScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _medicineNameController = TextEditingController();
  final TextEditingController _instructionsController = TextEditingController();
  final List<TimeOfDay> _times = [TimeOfDay(hour: 8, minute: 0)];
  bool _saving = false;

  Future<void> _addTime() async {
    final now = TimeOfDay.now();
    final picked = await showTimePicker(context: context, initialTime: now);
    if (picked != null) {
      setState(() {
        _times.add(picked);
      });
    }
  }

  Future<void> _saveReminder() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final code = prefs.getString('caremode_senior_code');
      if (code == null || code.isEmpty) throw Exception('연결 코드가 없습니다.');
      final timesStr = _times.map((t) => t.format(context)).toList();
      await FirebaseFirestore.instance
          .collection('users')
          .doc(code)
          .collection('medication_reminders')
          .add({
            'medicineName': _medicineNameController.text.trim(),
            'times': timesStr,
            'instructions': _instructionsController.text.trim(),
            'createdAt': FieldValue.serverTimestamp(),
          });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('약 알림이 등록되었습니다!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('저장 실패: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  void dispose() {
    _medicineNameController.dispose();
    _instructionsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('약 알림 등록')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _medicineNameController,
                decoration: const InputDecoration(labelText: '약 이름'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? '약 이름을 입력하세요' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _instructionsController,
                decoration: const InputDecoration(labelText: '복용 방법/메모'),
              ),
              const SizedBox(height: 16),
              const Text(
                '복용 시간',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              ..._times.map(
                (t) => ListTile(
                  title: Text(t.format(context)),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: () {
                      setState(() {
                        _times.remove(t);
                      });
                    },
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _addTime,
                icon: const Icon(Icons.add),
                label: const Text('시간 추가'),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _saving ? null : _saveReminder,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('알림 등록'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
