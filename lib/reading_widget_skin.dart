enum ReadingWidgetSkin {
  original,
  seasons,
  archive,
  editorial,
  constellation,
  signal,
  score,
  ink,
  festival;

  static ReadingWidgetSkin fromId(String? id) {
    for (final skin in values) {
      if (skin.name == id) return skin;
    }
    return seasons;
  }
}

int readingDailyGoal(int? minutes) {
  final value = minutes ?? 0;
  if (value < 0) return 0;
  if (value > 24 * 60) return 24 * 60;
  return value;
}
