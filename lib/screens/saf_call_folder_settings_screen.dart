import 'package:flutter/material.dart';

import '../widgets/saf_call_folder_settings_snippet.dart';

class SafCallFolderSettingsScreen extends StatelessWidget {
  const SafCallFolderSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('통화녹음 폴더 권한')),
      body: const SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: SafCallFolderSettingsSnippet(),
        ),
      ),
    );
  }
}
