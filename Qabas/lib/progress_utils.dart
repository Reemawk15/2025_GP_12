int estimateTotalSecondsFromText(String text, {int wordsPerMinute = 150}) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return 1;
  final words = trimmed.split(RegExp(r'\s+')).length;
  final minutes = words / wordsPerMinute;
  final seconds = (minutes * 60).round();
  return seconds <= 0 ? 1 : seconds;
}

double calcProgress({required int listenedSeconds, required int totalSeconds}) {
  if (totalSeconds <= 0) return 0.0;
  final p = listenedSeconds / totalSeconds;
  if (p < 0) return 0.0;
  if (p > 1) return 1.0;
  return p;
}
