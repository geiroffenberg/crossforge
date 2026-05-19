import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../crossword_generator.dart';
import '../services/score_service.dart';
import '../screens/stats_screen.dart';
import '../widgets/crossword_grid.dart';
import '../widgets/crossword_keyboard.dart';
import '../widgets/clue_panel.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Top-level isolate helpers (must be top-level for compute())
// ─────────────────────────────────────────────────────────────────────────────

/// Word length range accepted for crossword slots.
const int _kMinWordLen = 3;
const int _kMaxWordLen = 9;

/// Everything the isolate needs is encoded in a plain Map so it is safely
/// sendable across the isolate boundary without copying custom class state.
///
/// params keys: 'jsonString', 'width', 'height', 'seed'
/// returns Map with 'grid', 'words' (list of plain maps), or 'error'.
Map<String, dynamic> _buildPuzzleIsolate(Map<String, dynamic> params) {
  final String jsonString = params['jsonString'] as String;
  final int width = params['width'] as int;
  final int height = params['height'] as int;
  final int seed = params['seed'] as int;

  // ── Step 1: parse JSON ───────────────────────────────────────────────────
  final Map<String, dynamic> raw;
  try {
    raw = jsonDecode(jsonString) as Map<String, dynamic>;
  } catch (e) {
    return {'error': 'JSON parse failed: $e'};
  }

  // ── Step 2: filter to usable words ───────────────────────────────────────
  // merged.json structure: keys are uppercase words, values have:
  //   "MEANINGS": [ [partOfSpeech, definitionText, categories, antonyms], ... ]
  //   "ANTONYMS": [...], "SYNONYMS": [...]
  final allFiltered = <String, String>{}; // word → definition
  final alphaOnly = RegExp(r'^[a-zA-Z]+$');

  for (final entry in raw.entries) {
    final word = entry.key.toLowerCase();
    if (word.length < _kMinWordLen || word.length > _kMaxWordLen) continue;
    if (!alphaOnly.hasMatch(word)) continue;
    final value = entry.value;
    if (value is! Map) continue;

    // Each meaning is a list: [partOfSpeech, definitionText, categories, ...]
    final meanings = value['MEANINGS'];
    if (meanings is! List || meanings.isEmpty) continue;
    final first = meanings[0];
    if (first is! List || first.length < 2) continue;
    final def = first[1];
    if (def is String && def.isNotEmpty) {
      allFiltered[word] = def;
    }
  }

  if (allFiltered.isEmpty) {
    return {'error': 'No usable words found in dictionary.'};
  }

  // ── Step 3: build dictionary Map in the format CrosswordGenerator expects ─
  // Use ALL qualifying words — a small sample causes fill failures when
  // intersection constraints (2–3 fixed letters) exhaust the candidate list.
  final dict = <String, dynamic>{
    for (final e in allFiltered.entries)
      e.key: {'definitions': <String>[e.value]},
  };

  // ── Step 4: run generator (up to 20 retries with varied seeds) ───────────
  CrosswordGenerator? gen;
  bool success = false;

  for (int attempt = 0; attempt < 20 && !success; attempt++) {
    gen = CrosswordGenerator(
      width: width, height: height, dictionary: dict,
      rng: Random(seed + attempt * 7919),
    );
    success = gen.generate();
  }

  if (!success || gen == null) {
    return {'error': 'Generator could not place enough words.'};
  }

  // ── Step 6: serialise result as plain types ───────────────────────────────
  final grid = gen.getGrid();
  final words = gen.getPlacedWords().map((w) => <String, dynamic>{
        'number': w.number,
        'word': w.word,
        'clue': w.clue,
        'x': w.x,
        'y': w.y,
        'orientation': w.orientation,
      }).toList();

  return {'grid': grid, 'words': words, 'cellNumbers': gen.cellNumbers};
}

// ─────────────────────────────────────────────────────────────────────────────
// GameScreen
// ─────────────────────────────────────────────────────────────────────────────

class GameScreen extends StatefulWidget {
  const GameScreen({Key? key}) : super(key: key);

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  static const int _gridWidth = 10;
  static const int _gridHeight = 10;

  final _gridKey = GlobalKey<CrosswordGridState>();

  // Loaded once; re-used for every puzzle generation.
  String? _rawJsonString;

  // Current puzzle state
  List<List<String>> _solutionGrid = [];
  List<List<String>> _userAnswers = [];
  List<PlacedWord> _placedWords = [];
  Map<String, int> _cellNumbers = {};

  bool _showSolution = false;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _firstLoad();
  }

  /// Load the raw JSON string once, then immediately generate the first puzzle.
  /// The JSON string is held in memory so subsequent puzzles skip the file read.
  Future<void> _firstLoad() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      _rawJsonString = await rootBundle
          .loadString('assets/dictionaries/simple_english_merged.json');
    } catch (e) {
      setState(() {
        _errorMessage = 'Could not load dictionary asset: $e';
        _isLoading = false;
      });
      return;
    }

    await _generateNewPuzzle();
  }

  /// Offload the entire parse + filter + generate pipeline to a background isolate.
  Future<void> _generateNewPuzzle() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await compute(
        _buildPuzzleIsolate,
        {
          'jsonString': _rawJsonString!,
          'width': _gridWidth,
          'height': _gridHeight,
          // Random seed so each call produces a different puzzle.
          'seed': DateTime.now().millisecondsSinceEpoch,
        },
      );

      if (result.containsKey('error')) {
        throw Exception(result['error']);
      }

      final grid = (result['grid'] as List)
          .map((row) => List<String>.from(row as List))
          .toList();

      final words = (result['words'] as List).map((w) {
        final m = w as Map<String, dynamic>;
        return PlacedWord(
          number: m['number'] as int,
          word: m['word'] as String,
          clue: m['clue'] as String,
          x: m['x'] as int,
          y: m['y'] as int,
          orientation: m['orientation'] as String,
        );
      }).toList();

      final cellNumbers = Map<String, int>.from(
          result['cellNumbers'] as Map<Object?, Object?>);

      final userAnswers = List.generate(
          _gridHeight, (_) => List.generate(_gridWidth, (_) => ''));

      setState(() {
        _solutionGrid = grid;
        _placedWords = words;
        _userAnswers = userAnswers;
        _cellNumbers = cellNumbers;
        _showSolution = false;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error generating puzzle: $e';
        _isLoading = false;
      });
    }
  }

  void _updateCell(int x, int y, String letter) {
    if (letter.isNotEmpty && !RegExp(r'[a-zA-Z]').hasMatch(letter)) return;
    setState(() {
      _userAnswers[y][x] = letter.toUpperCase();
    });
    _checkCompletion();
  }

  void _checkCompletion() {
    if (_solutionGrid.isEmpty || _showSolution) return;

    // Every non-black cell must have a letter.
    for (int row = 0; row < _solutionGrid.length; row++) {
      for (int col = 0; col < _solutionGrid[row].length; col++) {
        if (_solutionGrid[row][col].isEmpty) continue; // black cell
        if (_userAnswers[row][col].isEmpty) return;    // still blank
      }
    }

    // All cells filled — check correctness.
    bool allCorrect = true;
    outer:
    for (int row = 0; row < _solutionGrid.length; row++) {
      for (int col = 0; col < _solutionGrid[row].length; col++) {
        if (_solutionGrid[row][col].isEmpty) continue;
        if (_userAnswers[row][col] != _solutionGrid[row][col]) {
          allCorrect = false;
          break outer;
        }
      }
    }

    if (allCorrect) {
      setState(() => _showSolution = true);
      ScoreService.append(ScoreRecord(
        date: DateTime.now(),
        score: 100,
        totalWords: _placedWords.length,
        correctWords: _placedWords.length,
        solved: true,
      ));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('\u{1F389} Congratulations \u2014 puzzle solved!'),
          duration: Duration(seconds: 4),
          backgroundColor: Color(0xFF15803D),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Not quite \u2014 keep trying!'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  /// Returns the number of [_placedWords] whose every cell matches the solution.
  int _countCorrectWords() {
    int correct = 0;
    for (final word in _placedWords) {
      bool wordOk = true;
      for (int i = 0; i < word.word.length; i++) {
        final x = word.orientation == 'across' ? word.x + i : word.x;
        final y = word.orientation == 'down'   ? word.y + i : word.y;
        if (_userAnswers[y][x] != _solutionGrid[y][x]) {
          wordOk = false;
          break;
        }
      }
      if (wordOk) correct++;
    }
    return correct;
  }

  void _giveUp() {
    final total   = _placedWords.length;
    final correct = _countCorrectWords();
    final score   = total == 0 ? 0.0 : (correct / total) * 100.0;

    setState(() => _showSolution = true);

    ScoreService.append(ScoreRecord(
      date: DateTime.now(),
      score: score,
      totalWords: total,
      correctWords: correct,
      solved: false,
    ));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Solution revealed — $correct/$total words correct '
          '(${score.toStringAsFixed(0)}%).',
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  List<List<String>> _getDisplayGrid() =>
      _showSolution ? _solutionGrid : _userAnswers;

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        // Icon replaces text title — sized to match one grid tile.
        title: Image.asset(
          'assets/icon.png',
          height: 36,
          width: 36,
          fit: BoxFit.contain,
        ),
        backgroundColor: Colors.deepPurple.shade700,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart_rounded),
            tooltip: 'Progress',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const StatsScreen()),
            ),
          ),
          if (!_isLoading && _errorMessage == null) ...
            _showSolution
                ? [
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      tooltip: 'New Puzzle',
                      onPressed: _generateNewPuzzle,
                    ),
                  ]
                : [
                    IconButton(
                      icon: const Icon(Icons.flag_outlined),
                      tooltip: 'Give Up & Show Solution',
                      onPressed: _giveUp,
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      tooltip: 'New Puzzle',
                      onPressed: _generateNewPuzzle,
                    ),
                  ],
        ],
      ),
      body: _isLoading
          ? _buildLoading()
          : _errorMessage != null
              ? _buildError()
              : _buildGame(),
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 20),
          Text('Building puzzle…', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(_errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15)),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _firstLoad,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGame() {
    return Column(
      children: [
        // ── Crossword grid (fixed, never scrolls) ──────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: CrosswordGrid(
                key: _gridKey,
                solutionGrid: _solutionGrid,
                displayGrid: _getDisplayGrid(),
                showSolution: _showSolution,
                cellNumbers: _cellNumbers,
                onCellChanged: _updateCell,
              ),
            ),
          ),
        ),

        // ── On-screen keyboard (hidden when solution is revealed) ─────────
        if (!_showSolution)
          CrosswordKeyboard(
            onLetter:    (l) => _gridKey.currentState?.inputLetter(l),
            onBackspace: ()  => _gridKey.currentState?.deleteLetter(),
            onNavigate:  (d) => _gridKey.currentState?.navigateWord(d),
          ),

        // ── Clue lists (fill remaining space, each scrolls independently)
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: CluePanel(placedWords: _placedWords),
          ),
        ),
      ],
    );
  }
}
