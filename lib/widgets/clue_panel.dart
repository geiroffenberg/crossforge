import 'package:flutter/material.dart';
import '../crossword_generator.dart';

/// Displays Across and Down clues in standard crossword format.
/// Each clue is prefixed with its assigned grid number.
class CluePanel extends StatelessWidget {
  final List<PlacedWord> placedWords;

  const CluePanel({Key? key, required this.placedWords}) : super(key: key);

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
                itemBuilder: (_, i) => _clueRow(words[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _clueRow(PlacedWord w) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(color: Colors.black87, fontSize: 13, height: 1.4),
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
    );
  }
}
