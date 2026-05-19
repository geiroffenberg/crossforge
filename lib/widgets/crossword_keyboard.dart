import 'package:flutter/material.dart';

/// QWERTY keyboard for crossword input.
///
/// Provides letter keys, ⌫ backspace, and ← → word-navigation arrows.
/// Call [onLetter], [onBackspace], and [onNavigate] to hook it up to the grid.
class CrosswordKeyboard extends StatelessWidget {
  final void Function(String letter) onLetter;
  final void Function() onBackspace;
  /// [direction] is -1 (back) or +1 (forward) within the current word.
  final void Function(int direction) onNavigate;

  static const _row1 = ['Q','W','E','R','T','Y','U','I','O','P'];
  static const _row2 = ['A','S','D','F','G','H','J','K','L'];
  static const _row3 = ['Z','X','C','V','B','N','M'];

  const CrosswordKeyboard({
    Key? key,
    required this.onLetter,
    required this.onBackspace,
    required this.onNavigate,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFCBD5E1), // slate-300
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _letterRow(_row1),
          const SizedBox(height: 5),
          _letterRow(_row2),
          const SizedBox(height: 5),
          // Bottom row: ← | Z–M letters | ⌫ | →
          Row(
            children: [
              _iconKey(Icons.arrow_back_rounded, () => onNavigate(-1),
                  color: Colors.deepPurple.shade600),
              const SizedBox(width: 4),
              ..._row3.expand((l) => [
                    Expanded(child: _letterKey(l)),
                    const SizedBox(width: 4),
                  ]),
              _iconKey(Icons.backspace_outlined, onBackspace,
                  color: const Color(0xFF64748B)),
              const SizedBox(width: 4),
              _iconKey(Icons.arrow_forward_rounded, () => onNavigate(1),
                  color: Colors.deepPurple.shade600),
            ],
          ),
        ],
      ),
    );
  }

  Widget _letterRow(List<String> letters) {
    return Row(
      children: letters.expand((l) sync* {
        if (l != letters.first) yield const SizedBox(width: 4);
        yield Expanded(child: _letterKey(l));
      }).toList(),
    );
  }

  Widget _letterKey(String letter) {
    return GestureDetector(
      onTap: () => onLetter(letter),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(5),
          boxShadow: const [
            BoxShadow(color: Color(0x40000000), blurRadius: 0, offset: Offset(0, 2)),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          letter,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
      ),
    );
  }

  Widget _iconKey(IconData icon, VoidCallback onTap, {required Color color}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 44,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(5),
          boxShadow: const [
            BoxShadow(color: Color(0x40000000), blurRadius: 0, offset: Offset(0, 2)),
          ],
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}
