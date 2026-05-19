import 'package:flutter/material.dart';

/// Compact QWERTY keyboard for crossword input.
/// Letters only + ⌫ backspace. No arrow navigation keys.
class CrosswordKeyboard extends StatelessWidget {
  final void Function(String letter) onLetter;
  final void Function() onBackspace;

  static const _row1 = ['Q','W','E','R','T','Y','U','I','O','P'];
  static const _row2 = ['A','S','D','F','G','H','J','K','L'];
  static const _row3 = ['Z','X','C','V','B','N','M'];

  const CrosswordKeyboard({
    Key? key,
    required this.onLetter,
    required this.onBackspace,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFCBD5E1),
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _letterRow(_row1),
          const SizedBox(height: 4),
          _letterRow(_row2),
          const SizedBox(height: 4),
          Row(
            children: [
              ..._row3.expand((l) => [
                    Expanded(child: _letterKey(l)),
                    const SizedBox(width: 3),
                  ]),
              _backspaceKey(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _letterRow(List<String> letters) {
    return Row(
      children: letters.expand((l) sync* {
        if (l != letters.first) yield const SizedBox(width: 3);
        yield Expanded(child: _letterKey(l));
      }).toList(),
    );
  }

  Widget _letterKey(String letter) {
    return GestureDetector(
      onTap: () => onLetter(letter),
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4),
          boxShadow: const [
            BoxShadow(color: Color(0x40000000), blurRadius: 0, offset: Offset(0, 2)),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          letter,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
      ),
    );
  }

  Widget _backspaceKey() {
    return GestureDetector(
      onTap: onBackspace,
      child: Container(
        width: 44,
        height: 36,
        decoration: BoxDecoration(
          color: const Color(0xFF64748B),
          borderRadius: BorderRadius.circular(4),
          boxShadow: const [
            BoxShadow(color: Color(0x40000000), blurRadius: 0, offset: Offset(0, 2)),
          ],
        ),
        alignment: Alignment.center,
        child: const Icon(Icons.backspace_outlined, color: Colors.white, size: 18),
      ),
    );
  }
}
