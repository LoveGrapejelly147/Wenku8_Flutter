/// Gain processing is omitted. Ordinary TTS playback does not use it.
class ListeningEnhancementPreference {
  const ListeningEnhancementPreference({this.enabled = false});

  final bool enabled;

  factory ListeningEnhancementPreference.fromJson(Map<dynamic, dynamic> json) =>
      ListeningEnhancementPreference(enabled: json['enabled'] == true);

  Map<String, Object?> toJson() => {'enabled': enabled};
}

class ListeningEnhancement {
  ListeningEnhancementPreference preference =
      const ListeningEnhancementPreference();

  Future<void> configure(
    ListeningEnhancementPreference value, {
    int? audioSessionId,
  }) async {
    preference = value;
  }

  Future<void> setPreference(ListeningEnhancementPreference value) async {
    preference = value;
  }

  Future<void> dispose() async {}
}
