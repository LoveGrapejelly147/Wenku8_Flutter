import 'package:flutter/material.dart';

import '../listening/controller.dart';
import 'custom_tts.dart';

class CustomSpeechPage extends StatelessWidget {
  const CustomSpeechPage({
    super.key,
    required this.settings,
    required this.controller,
  });

  final CustomSpeechSettings settings;
  final ListeningController controller;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('自定义语音')),
    body: const Padding(
      padding: EdgeInsets.all(24),
      child: Text(
        '自定义语音接口在此版本不可用。在线音色和系统 TTS 仍然可以使用。',
        style: TextStyle(height: 1.6),
      ),
    ),
  );
}
