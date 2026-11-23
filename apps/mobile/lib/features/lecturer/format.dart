String greeting([DateTime? now]) {
  final h = (now ?? DateTime.now()).hour;
  if (h < 12) return 'Good morning';
  if (h < 18) return 'Good afternoon';
  return 'Good evening';
}

String plural(int n, String word) => '$n ${n == 1 ? word : '${word}s'}';

String relativeTime(DateTime? t, [DateTime? now]) {
  if (t == null) return 'recently';
  final d = (now ?? DateTime.now()).difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  if (d.inDays == 1) return 'yesterday';
  if (d.inDays < 7) return '${d.inDays} days ago';
  return '${t.day}/${t.month}/${t.year}';
}

/// "482913" → "482 913" (easier to read from the back of the room).
String formatCode(String code) => code.length == 6 ? '${code.substring(0, 3)} ${code.substring(3)}' : code;
