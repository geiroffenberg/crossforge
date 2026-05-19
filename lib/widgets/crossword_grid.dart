import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Interactive crossword grid widget.
///
/// State is public so an external [CrosswordKeyboard] can call
/// [inputLetter], [deleteLetter], and [navigateWord] via a [GlobalKey].
class CrosswordGrid extends StatefulWidget {
  final List<List<String>> solutionGrid;
  final List<List<String>> displayGrid;
  final bool showSolution;
  final Map<String, int> cellNumbers;
  final void Function(int x, int y, String letter) onCellChanged;

  const CrosswordGrid({
    Key? key,
    required this.solutionGrid,
    required this.displayGrid,
    required this.showSolution,
    required this.cellNumbers,
    required this.onCellChanged,
  }) : super(key: key);

  @override
  CrosswordGridState createState() => CrosswordGridState();
}

class CrosswordGridState extends State<CrosswordGrid> {
  int? _selX;
  int? _selY;
  String _dir = 'across'; // 'across' | 'down'

  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  int get _rows => widget.solutionGrid.length;
  int get _cols => _rows > 0 ? widget.solutionGrid[0].length : 0;
  bool _isBlack(int x, int y) => widget.solutionGrid[y][x].isEmpty;

  // ── Public API (called by CrosswordKeyboard) ─────────────────────────────

  void inputLetter(String letter) {
    if (_selX == null || _selY == null) return;
    widget.onCellChanged(_selX!, _selY!, letter.toUpperCase());
    _advance(1);
  }

  void deleteLetter() {
    if (_selX == null || _selY == null) return;
    if (widget.displayGrid[_selY!][_selX!].isNotEmpty) {
      // Cell has a letter: clear it, stay here.
      widget.onCellChanged(_selX!, _selY!, '');
    } else {
      // Cell empty: step back then clear.
      _advance(-1);
      if (_selX != null && _selY != null) {
        widget.onCellChanged(_selX!, _selY!, '');
      }
    }
  }

  void navigateWord(int direction) => _advance(direction);

  // ── Internal helpers ─────────────────────────────────────────────────────

  /// Move [steps] cells in the current word direction, skipping black cells.
  void _advance(int steps) {
    if (_selX == null || _selY == null) return;
    final dx = _dir == 'across' ? steps : 0;
    final dy = _dir == 'down'   ? steps : 0;
    int nx = _selX! + dx, ny = _selY! + dy;
    while (nx >= 0 && nx < _cols && ny >= 0 && ny < _rows) {
      if (!_isBlack(nx, ny)) {
        setState(() { _selX = nx; _selY = ny; });
        return;
      }
      nx += dx; ny += dy;
    }
  }

  /// Returns all cell keys ('x,y') belonging to the currently selected word.
  Set<String> _wordCells() {
    if (_selX == null || _selY == null) return {};
    final cells = <String>{};
    if (_dir == 'across') {
      int x = _selX!;
      while (x > 0 && !_isBlack(x - 1, _selY!)) x--;
      while (x < _cols && !_isBlack(x, _selY!)) { cells.add('$x,${_selY!}'); x++; }
    } else {
      int y = _selY!;
      while (y > 0 && !_isBlack(_selX!, y - 1)) y--;
      while (y < _rows && !_isBlack(_selX!, y)) { cells.add('${_selX!},$y'); y++; }
    }
    return cells;
  }

  bool _hasWordIn(int x, int y, String dir) {
    if (dir == 'across') {
      return (x > 0 && !_isBlack(x - 1, y)) || (x < _cols - 1 && !_isBlack(x + 1, y));
    } else {
      return (y > 0 && !_isBlack(x, y - 1)) || (y < _rows - 1 && !_isBlack(x, y + 1));
    }
  }

  void _onTap(int x, int y) {
    if (_isBlack(x, y)) return;
    _focus.requestFocus();
    setState(() {
      if (_selX == x && _selY == y) {
        // Same cell: toggle direction if the other direction has a word.
        final other = _dir == 'across' ? 'down' : 'across';
        if (_hasWordIn(x, y, other)) _dir = other;
      } else {
        _selX = x;
        _selY = y;
        // Keep current direction if a word exists; otherwise switch.
        if (!_hasWordIn(x, y, _dir)) {
          _dir = _dir == 'across' ? 'down' : 'across';
        }
      }
    });
  }

  // ── Physical keyboard (desktop / Chromebook) ─────────────────────────────

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (_selX == null || _selY == null) return KeyEventResult.ignored;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft)  { setState(() { _dir = 'across'; }); _advance(-1); return KeyEventResult.handled; }
    if (key == LogicalKeyboardKey.arrowRight) { setState(() { _dir = 'across'; }); _advance( 1); return KeyEventResult.handled; }
    if (key == LogicalKeyboardKey.arrowUp)    { setState(() { _dir = 'down';   }); _advance(-1); return KeyEventResult.handled; }
    if (key == LogicalKeyboardKey.arrowDown)  { setState(() { _dir = 'down';   }); _advance( 1); return KeyEventResult.handled; }
    if (key == LogicalKeyboardKey.backspace)  { deleteLetter(); return KeyEventResult.handled; }

    final ch = event.character;
    if (ch != null && RegExp(r'[a-zA-Z]').hasMatch(ch)) {
      inputLetter(ch);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final inWord = _wordCells();

    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      child: AspectRatio(
        aspectRatio: 1,
        child: GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: _cols,
            mainAxisSpacing: 1,
            crossAxisSpacing: 1,
          ),
          itemCount: _rows * _cols,
          itemBuilder: (_, index) {
            final y = index ~/ _cols;
            final x = index % _cols;
            return _buildCell(x, y, inWord);
          },
        ),
      ),
    );
  }

  Widget _buildCell(int x, int y, Set<String> inWord) {
    if (_isBlack(x, y)) {
      return Container(color: const Color(0xFF1A1A2E));
    }

    final isSelected = _selX == x && _selY == y;
    final isInWord   = inWord.contains('$x,$y');
    final solution   = widget.solutionGrid[y][x];
    final display    = widget.displayGrid[y][x];
    final number     = widget.cellNumbers['$x,$y'];


    final Color bg;
    if (isSelected) {
      bg = const Color(0xFF6D28D9); // purple-700
    } else if (isInWord) {
      bg = const Color(0xFFDDD6FE); // purple-100
    } else if (widget.showSolution && display.isNotEmpty && display != solution) {
      bg = const Color(0xFFFEE2E2); // red-100
    } else {
      bg = Colors.white;
    }

    return GestureDetector(
      onTap: () => _onTap(x, y),
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(
            color: isSelected ? const Color(0xFF6D28D9) : const Color(0xFF9CA3AF),
            width: isSelected ? 2 : 0.8,
          ),
        ),
        child: Stack(
          children: [
            if (number != null)
              Positioned(
                top: 1, left: 2,
                child: Text(
                  '$number',
                  style: const TextStyle(
                    fontSize: 7, height: 1,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ),
            Center(
              child: Text(
                widget.showSolution ? solution : display,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : Colors.black87,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
