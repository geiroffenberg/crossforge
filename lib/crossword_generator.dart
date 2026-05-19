import 'dart:math';

// ─────────────────────────────────────────────────────────────────────────────
// Public data classes
// ─────────────────────────────────────────────────────────────────────────────

/// A word that has been placed in the final grid.
class PlacedWord {
  /// Standard crossword clue number (reading order).
  int number;
  final String word; // UPPERCASE
  final String clue;
  /// Column of the first letter (0-indexed).
  final int x;
  /// Row of the first letter (0-indexed).
  final int y;
  final String orientation; // 'across' | 'down'

  PlacedWord({
    required this.number,
    required this.word,
    required this.clue,
    required this.x,
    required this.y,
    required this.orientation,
  });

  @override
  String toString() =>
      'PlacedWord(#$number "$word" [$orientation] @ ($x,$y))';
}

// ─────────────────────────────────────────────────────────────────────────────
// CrosswordGenerator
// ─────────────────────────────────────────────────────────────────────────────

/// Generates a crossword by placing words at intersections (word-placement
/// style). Starts with a seed word and attaches crossing words at shared
/// letters, building outward until the target word count is met.
///
/// Grid cells are UPPERCASE letters; empty string means "black square".
class CrosswordGenerator {
  final int width;
  final int height;

  /// word → {'definitions': [String]} — same shape built by the isolate helper.
  final Map<String, dynamic> dictionary;

  static const int _kMinLen          = 3;
  static const int _kMaxLen          = 9;
  static const int _kMaxWords        = 22;
  static const int _kMinWords        = 6;
  // Maximum candidates examined per (length, letter) query.
  static const int _kCandidateSample = 300;

  late List<List<String>> _grid;
  final List<PlacedWord>  _placedWords = [];
  Map<String, int>        _cellNumbers = {};

  final Random _rng;

  CrosswordGenerator({
    required this.width,
    required this.height,
    required this.dictionary,
    Random? rng,
  }) : _rng = rng ?? Random();

  // ── Public interface ──────────────────────────────────────────────────────

  List<List<String>> getGrid()        => _grid;
  List<PlacedWord>   getPlacedWords() => List.unmodifiable(_placedWords);
  Map<String, int>   get cellNumbers  => _cellNumbers;

  /// Attempts to generate a valid crossword.
  /// Returns true when at least [_kMinWords] words are placed.
  bool generate() {
    _grid        = List.generate(height, (_) => List.filled(width, ''));
    _placedWords.clear();
    _cellNumbers = {};

    // ── Step 1: build word index ──────────────────────────────────────────
    // Words are stored UPPERCASE so the solution grid matches user input.
    final wordDefs = <String, String>{};
    for (final e in dictionary.entries) {
      final word = (e.key as String).toUpperCase();
      if (word.length < _kMinLen || word.length > _kMaxLen) continue;
      final defs = (e.value as Map<String, dynamic>)['definitions'];
      if (defs is List && defs.isNotEmpty && defs[0] is String) {
        wordDefs[word] = defs[0] as String;
      }
    }
    if (wordDefs.isEmpty) return false;

    // Group by length; pre-shuffle for variety.
    final byLength = <int, List<String>>{};
    for (final w in wordDefs.keys) {
      byLength.putIfAbsent(w.length, () => []).add(w);
    }
    for (final list in byLength.values) list.shuffle(_rng);

    // ── Step 2: place seed word horizontally near centre ──────────────────
    String? seed;
    for (final len in [7, 6, 8, 5, 9, 4]) {
      final candidates = byLength[len];
      if (candidates != null && candidates.isNotEmpty) {
        seed = candidates.first;
        break;
      }
    }
    if (seed == null) return false;

    final seedX = (width - seed.length) ~/ 2;
    final seedY = height ~/ 2;
    _placeWord(seed, seedX, seedY, 'across', wordDefs[seed]!);

    final used  = <String>{seed};
    final queue = <PlacedWord>[..._placedWords];
    int qi = 0;

    // ── Step 3: BFS expansion ─────────────────────────────────────────────
    while (qi < queue.length && _placedWords.length < _kMaxWords) {
      final current  = queue[qi++];
      final crossDir = current.orientation == 'across' ? 'down' : 'across';

      final positions =
          List.generate(current.word.length, (i) => i)..shuffle(_rng);

      for (final pos in positions) {
        if (_placedWords.length >= _kMaxWords) break;

        final cx = current.orientation == 'across'
            ? current.x + pos
            : current.x;
        final cy = current.orientation == 'across'
            ? current.y
            : current.y + pos;

        // Skip if this cell already has a crossing word.
        if (_hasCrossingWord(cx, cy, current.orientation)) continue;

        final placed =
            _tryCrossing(byLength, wordDefs, used, current.word[pos], cx, cy, crossDir);
        if (placed != null) {
          used.add(placed.word);
          queue.add(placed);
        }
      }
    }

    if (_placedWords.length < _kMinWords) return false;

    _assignNumbers();
    return true;
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  void _placeWord(String word, int x, int y, String dir, String clue) {
    for (int i = 0; i < word.length; i++) {
      final cx = dir == 'across' ? x + i : x;
      final cy = dir == 'down'   ? y + i : y;
      _grid[cy][cx] = word[i]; // already UPPERCASE
    }
    _placedWords.add(PlacedWord(
        number: 0, word: word, clue: clue, x: x, y: y, orientation: dir));
  }

  /// Find and place a word in [crossDir] through cell ([cx],[cy]),
  /// where [letter] is already in the grid at that position.
  PlacedWord? _tryCrossing(
    Map<int, List<String>> byLength,
    Map<String, String> wordDefs,
    Set<String> used,
    String letter,
    int cx,
    int cy,
    String crossDir,
  ) {
    final lengths =
        List.generate(_kMaxLen - _kMinLen + 1, (i) => i + _kMinLen)
          ..shuffle(_rng);

    for (final len in lengths) {
      final words = byLength[len];
      if (words == null) continue;

      int checked = 0;
      for (final word in words) {
        if (checked >= _kCandidateSample) break;
        if (used.contains(word)) continue;
        checked++;

        for (int crossPos = 0; crossPos < len; crossPos++) {
          if (word[crossPos] != letter) continue;

          final wx = crossDir == 'across' ? cx - crossPos : cx;
          final wy = crossDir == 'down'   ? cy - crossPos : cy;

          if (_canPlace(word, wx, wy, crossDir)) {
            _placeWord(word, wx, wy, crossDir, wordDefs[word]!);
            return _placedWords.last;
          }
        }
      }
    }
    return null;
  }

  /// True when there is already a word perpendicular to [wordDir]
  /// passing through cell ([cx],[cy]).
  bool _hasCrossingWord(int cx, int cy, String wordDir) {
    final crossDir = wordDir == 'across' ? 'down' : 'across';
    for (final pw in _placedWords) {
      if (pw.orientation != crossDir) continue;
      if (crossDir == 'down') {
        if (pw.x == cx && cy >= pw.y && cy < pw.y + pw.word.length) return true;
      } else {
        if (pw.y == cy && cx >= pw.x && cx < pw.x + pw.word.length) return true;
      }
    }
    return false;
  }

  /// True if [word] can legally be placed at ([x],[y]) in [dir]:
  ///   • within grid bounds
  ///   • cells before/after the word are empty or out-of-bounds
  ///   • each cell is empty or holds the correct matching letter
  ///   • new (empty) cells are not adjacent to a parallel word
  ///   • (after the seed) must intersect at least one existing word
  bool _canPlace(String word, int x, int y, String dir) {
    final len = word.length;
    if (x < 0 || y < 0) return false;
    if (dir == 'across' && x + len > width)  return false;
    if (dir == 'down'   && y + len > height) return false;

    // Cells immediately before and after must be empty or out-of-bounds.
    if (dir == 'across') {
      if (x > 0           && _grid[y][x - 1].isNotEmpty)    return false;
      if (x + len < width && _grid[y][x + len].isNotEmpty)  return false;
    } else {
      if (y > 0            && _grid[y - 1][x].isNotEmpty)   return false;
      if (y + len < height && _grid[y + len][x].isNotEmpty) return false;
    }

    bool hasIntersection = false;
    for (int i = 0; i < len; i++) {
      final cx = dir == 'across' ? x + i : x;
      final cy = dir == 'down'   ? y + i : y;

      if (_grid[cy][cx].isNotEmpty) {
        // Occupied cell: letter must match (valid intersection).
        if (_grid[cy][cx] != word[i]) return false;
        hasIntersection = true;
      } else {
        // Empty cell: must not be adjacent to a parallel word
        // (would merge two words into one long word).
        if (dir == 'across') {
          if (cy > 0          && _grid[cy - 1][cx].isNotEmpty) return false;
          if (cy < height - 1 && _grid[cy + 1][cx].isNotEmpty) return false;
        } else {
          if (cx > 0         && _grid[cy][cx - 1].isNotEmpty) return false;
          if (cx < width - 1 && _grid[cy][cx + 1].isNotEmpty) return false;
        }
      }
    }

    // Every word except the very first must cross an existing word.
    return _placedWords.isEmpty || hasIntersection;
  }

  /// Assign reading-order clue numbers (top→bottom, left→right).
  /// Two words starting at the same cell share the same number.
  void _assignNumbers() {
    final starts = <String>{};
    for (final pw in _placedWords) starts.add('${pw.x},${pw.y}');

    final sorted = starts.toList()
      ..sort((a, b) {
        final pa = a.split(','), pb = b.split(',');
        final ya = int.parse(pa[1]), yb = int.parse(pb[1]);
        return ya != yb
            ? ya.compareTo(yb)
            : int.parse(pa[0]).compareTo(int.parse(pb[0]));
      });

    int num = 1;
    for (final k in sorted) _cellNumbers[k] = num++;

    for (final pw in _placedWords) {
      pw.number = _cellNumbers['${pw.x},${pw.y}'] ?? 0;
    }
  }
}
