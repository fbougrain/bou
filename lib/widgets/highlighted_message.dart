import 'package:flutter/material.dart';

class HighlightedMessage extends StatelessWidget {
  const HighlightedMessage({
    super.key,
    required this.text,
    required this.highlights,
    required this.accent,
  });
  final String text;
  final List<String> highlights;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final spans = <TextSpan>[];
    final lower = text.toLowerCase();
    final ordered = [...highlights]
      ..sort((a, b) => b.length.compareTo(a.length));
    final matches = <Map<String, int>>[];
    for (final h in ordered) {
      final idx = lower.indexOf(h.toLowerCase());
      if (idx != -1) {
        matches.add({'start': idx, 'end': idx + h.length});
      }
    }
    if (matches.isEmpty) {
      spans.add(TextSpan(text: text));
    } else {
      matches.sort((a, b) => a['start']!.compareTo(b['start']!));
      int cursor = 0;
      for (final m in matches) {
        final start = m['start']!;
        final end = m['end']!;
        if (start > cursor) {
          spans.add(TextSpan(text: text.substring(cursor, start)));
        }
        spans.add(
          TextSpan(
            text: text.substring(start, end),
            style: TextStyle(color: accent, fontWeight: FontWeight.w600),
          ),
        );
        cursor = end;
      }
      if (cursor < text.length) {
        spans.add(TextSpan(text: text.substring(cursor)));
      }
    }
    return RichText(
      text: TextSpan(
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13.5,
          height: 1.34,
        ),
        children: spans,
      ),
    );
  }
}

class AiActionChip extends StatelessWidget {
  const AiActionChip({
    super.key,
    required this.label,
    required this.accent,
    required this.onTap,
  });
  final String label;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accent.withValues(alpha: 0.4), width: 1),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: accent,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
          ),
        ),
      ),
    );
  }
}
