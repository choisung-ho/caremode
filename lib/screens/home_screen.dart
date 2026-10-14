// lib/screens/home_screen.dart
import 'package:flutter/material.dart';
import 'package:call_log/call_log.dart';
import 'package:intl/intl.dart';
import '../widgets/timeline_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Future<Iterable<CallLogEntry>> getCallLogs() async {
    return await CallLog.get();
  }

  String formatTime(int timestamp) {
    var date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return DateFormat('a h:mm', 'ko_KR').format(date);
  }

  String formatDuration(int seconds) {
    if (seconds < 60) return "$seconds초";
    return "${(seconds / 60).floor()}분 ${seconds % 60}초";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "오늘의 하루 매듭",
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        DateFormat(
                          'M월 d일 EEEE',
                          'ko_KR',
                        ).format(DateTime.now()),
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                  const CircleAvatar(child: Text("ME")),
                ],
              ),
              const SizedBox(height: 20),
              Expanded(
                child: FutureBuilder<Iterable<CallLogEntry>>(
                  future: getCallLogs(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return const Center(child: Text("최근 통화 기록이 없어요"));
                    }
                    final entries = snapshot.data!.toList();
                    return ListView.builder(
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        IconData icon = Icons.call_received;
                        String typeText = "수신";
                        if (entry.callType == CallType.missed) {
                          icon = Icons.call_missed;
                          typeText = "부재중";
                        } else if (entry.callType == CallType.outgoing) {
                          icon = Icons.call_made;
                          typeText = "발신";
                        }

                        return TimelineCard(
                          time: formatTime(entry.timestamp ?? 0),
                          title: entry.name ?? entry.number ?? "알 수 없음",
                          desc:
                              "$typeText (${formatDuration(entry.duration ?? 0)})",
                          icon: icon,
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
