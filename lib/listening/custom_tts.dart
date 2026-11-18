import 'dart:typed_data';

import 'models.dart';

class CustomSpeechConfig {
  const CustomSpeechConfig({
    required this.namespace,
    required this.voiceId,
    required this.locale,
    required this.voice,
  });

  final String namespace;
  final String voiceId;
  final String locale;
  final SpeechVoice voice;
}

class CustomSpeechSettings {
  CustomSpeechConfig? get config => null;
  Future<void> load() async {}
}

class CustomSpeechClient {
  Future<Uint8List> synthesize(
    String text,
    CustomSpeechConfig config,
    SpeechCancellation cancellation,
  ) async {
    throw const SpeechFailure('自定义语音接口在此版本不可用');
  }
}
