import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../firebase_options.dart';
import 'buffer_service.dart';
import 'video_upload_service.dart';
import 'call_recording_service.dart';

const String periodicTaskName = 'caremode_periodic_task';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();

    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    final prefs = await SharedPreferences.getInstance();
    final userCode = prefs.getString('caremode_senior_code');

    // Track B: 버퍼 플러시(SMS/GPS)
    final buffer = const BufferService();
    final sms = await buffer.takeSmsAndClear();
    final gps = await buffer.takeGpsAndClear();

    final firestore = FirebaseFirestore.instance;
    final now = DateTime.now().toIso8601String();
    if (sms.isNotEmpty) {
      await firestore.collection('buffer_sms').add({
        'code': userCode,
        'items': sms,
        'createdAt': FieldValue.serverTimestamp(),
        'localTimestamp': now,
      });
    }
    if (gps.isNotEmpty) {
      await firestore.collection('buffer_gps').add({
        'code': userCode,
        'items': gps,
        'createdAt': FieldValue.serverTimestamp(),
        'localTimestamp': now,
      });
    }

    // Track A: 무거운 파일 업로드(동영상 + 통화녹음)
    if (userCode != null) {
      // SAF 폴더 권한이 없는 경우 내부 로직이 스킵하도록 되어 있음
      await VideoUploadService().start(
        userCode,
        scanInterval: const Duration(hours: 2),
      );
      await VideoUploadService().scanAndUploadTodayVideos();

      await CallRecordingService().start(userCode);
      await CallRecordingService().scanAndUploadNewRecordings();
    }

    return true;
  });
}
