import 'package:flutter/material.dart';
import '../crossword_generator.dart';

/// Displays Across and Down clues in standard crossword format.
/// Each clue is prefixed with its assigned grid number.
/// Tapping a clue calls [onWordTap] so the grid can highlight the word.
class CluePanel extends StatelessWidget {
  final List<PlacedWord> placedWords;
  final void Function(PlacedWord)? onWordTap;
  /// Number of the currently active word, for highlighting.
  final int? activeNumber;
  /// Orientation of the currently active word ('across' or 'down').
  final String? activeOrientation;

  const CluePanel({
    super.key,
    required this.placedWords,
    this.onWordTap,
    this.activeNumber,
    this.activeOrientation,
  });

  @override
  Widget build(BuildContext context) {
    final across = placedWords
        .where((w) => w.orientation == 'across')
        .toList()
      ..sort((a, b) => a.number.compareTo(b.number));

    final down = placedWords
        .where((w) => w.orientation == 'down')
        .toList()
      ..sort((a, b) => a.number.compareTo(b.number));

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _section('ACROSS', across, const Color(0xFF1D4ED8))),
        const SizedBox(width: 12),
        Expanded(child: _section('DOWN', down, const Color(0xFFB45309))),
      ],
    );
  }

  Widget _section(String title, List<PlacedWord> words, Color accent) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header (fixed)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Independently scrollable clue list
            Expanded(
              child: ListView.builder(
                itemCount: words.length,
                itemBuilder: (_, i) => _clueRow(words[i], accent),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _clueRow(PlacedWord w, Color accent) {
    final isActive =
        w.number == activeNumber && w.orientation == activeOrientation;

    return InkWell(
      onTap: onWordTap == null ? null : () => onWordTap!(w),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        decoration: isActive
            ? BoxDecoration(
                color: accent.withAlpha(25),
                borderRadius: BorderRadius.circular(4),
                border: Border(
                  left: BorderSide(color: accent, width: 3),
                ),
              )
            : null,
        padding: const EdgeInsets.fromLTRB(6, 4, 4, 4),
        margin: const EdgeInsets.only(bottom: 2),
        child: RichText(
          text: TextSpan(
            style: TextStyle(
              color: isActive ? Colors.black : Colors.black87,
              fontSize: 13,
              height: 1.4,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
            ),
            children: [
              TextSpan(
                text: '${w.number}. ',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              TextSpan(text: w.clue.isEmpty ? '(no clue)' : w.clue),
              TextSpan(
                text: '  (${w.word.length})',
                style: const TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

