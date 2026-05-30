import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/admob_config.dart';
import '../crossword_generator.dart';
import '../models/difficulty.dart';
import '../services/score_service.dart';
import '../screens/stats_screen.dart';
import '../widgets/crossword_grid.dart';
import '../widgets/crossword_keyboard.dart';
import '../widgets/clue_panel.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Top-level isolate helpers (must be top-level for compute())
// ─────────────────────────────────────────────────────────────────────────────

/// Word length range accepted for crossword slots — driven by difficulty config at runtime.
/// These top-level constants are no longer used; config is passed via isolate params.

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
  final int minLen = params['minLen'] as int;
  final int maxLen = params['maxLen'] as int;
  final int minWords = params['minWords'] as int;
  final int maxWords = params['maxWords'] as int;
  final int candidateSample = params['candidateSample'] as int;

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
    if (word.length < minLen || word.length > maxLen) continue;
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
      e.key: {
        'definitions': <String>[e.value],
      },
  };

  // ── Step 4: run generator (up to 20 retries with varied seeds) ───────────
  CrosswordGenerator? gen;
  bool success = false;

  for (int attempt = 0; attempt < 20 && !success; attempt++) {
    gen = CrosswordGenerator(
      width: width,
      height: height,
      dictionary: dict,
      minLen: minLen,
      maxLen: maxLen,
      minWords: minWords,
      maxWords: maxWords,
      candidateSample: candidateSample,
      rng: Random(seed + attempt * 7919),
    );
    success = gen.generate();
  }

  if (!success || gen == null) {
    return {'error': 'Generator could not place enough words.'};
  }

  // ── Step 6: serialise result as plain types ───────────────────────────────
  final grid = gen.getGrid();
  final words = gen.getPlacedWords().map((w) {
    // Look up synonyms from the raw dictionary (keys are UPPERCASE).
    final entry = raw[w.word];
    final rawSyns = (entry is Map ? entry['SYNONYMS'] : null) as List?;
    final synonyms = rawSyns == null
        ? <String>[]
        : rawSyns
              .whereType<String>()
              .where((s) => s.isNotEmpty && s.toUpperCase() != w.word)
              .take(6)
              .toList();
    return <String, dynamic>{
      'number': w.number,
      'word': w.word,
      'clue': w.clue,
      'x': w.x,
      'y': w.y,
      'orientation': w.orientation,
      'synonyms': synonyms,
    };
  }).toList();

  return {'grid': grid, 'words': words, 'cellNumbers': gen.cellNumbers};
}

// ─────────────────────────────────────────────────────────────────────────────
// GameScreen
// ─────────────────────────────────────────────────────────────────────────────

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  static const int _gridWidth = 10;
  static const int _gridHeight = 10;
  static const int _kMaxHints = 5;

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
  int _hintsRemaining = _kMaxHints;
  PlacedWord? _activeWord;
  DifficultyLevel _difficulty = DifficultyLevel.expert;

  InterstitialAd? _interstitialAd;

  @override
  void dispose() {
    _interstitialAd?.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadInterstitialAd();
    _firstLoad();
  }

  void _loadInterstitialAd() {
    final adUnitId = AdMobConfig.interstitialAdUnitId;
    if (adUnitId.isEmpty) return;
    InterstitialAd.load(
      adUnitId: adUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => _interstitialAd = ad,
        onAdFailedToLoad: (error) => _interstitialAd = null,
      ),
    );
  }

  /// Shows the interstitial (if ready) then generates a new puzzle.
  /// Only call this from the post-completion "New Puzzle" button.
  Future<void> _showInterstitialThenGenerate() async {
    final ad = _interstitialAd;
    _interstitialAd = null;
    if (ad != null) {
      ad.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (a) {
          a.dispose();
          _loadInterstitialAd();
          _generateNewPuzzle();
        },
        onAdFailedToShowFullScreenContent: (a, error) {
          a.dispose();
          _loadInterstitialAd();
          _generateNewPuzzle();
        },
      );
      await ad.show();
    } else {
      await _generateNewPuzzle();
    }
  }

  /// Load the raw JSON string once, then immediately generate the first puzzle.
  /// The JSON string is held in memory so subsequent puzzles skip the file read.
  Future<void> _firstLoad() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      _rawJsonString = await rootBundle.loadString(
        'assets/dictionaries/simple_english_merged.json',
      );
    } catch (e) {
      setState(() {
        _errorMessage = 'Could not load dictionary asset: $e';
        _isLoading = false;
      });
      return;
    }

    // Try to resume the previous unfinished puzzle first.
    final restored = await _restoreGameState();
    if (!restored) await _generateNewPuzzle();
  }

  /// Offload the entire parse + filter + generate pipeline to a background isolate.
  Future<void> _generateNewPuzzle() async {
    await _clearSavedGame();
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await compute(_buildPuzzleIsolate, {
        'jsonString': _rawJsonString!,
        'width': _gridWidth,
        'height': _gridHeight,
        'seed': DateTime.now().millisecondsSinceEpoch,
        'minLen': DifficultyConfig.forLevel(_difficulty).minLen,
        'maxLen': DifficultyConfig.forLevel(_difficulty).maxLen,
        'minWords': DifficultyConfig.forLevel(_difficulty).minWords,
        'maxWords': DifficultyConfig.forLevel(_difficulty).maxWords,
        'candidateSample': DifficultyConfig.forLevel(_difficulty).candidateSample,
      });

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
          synonyms: List<String>.from(m['synonyms'] as List? ?? []),
        );
      }).toList();

      final cellNumbers = Map<String, int>.from(
        result['cellNumbers'] as Map<Object?, Object?>,
      );

      final userAnswers = List.generate(
        _gridHeight,
        (_) => List.generate(_gridWidth, (_) => ''),
      );

      setState(() {
        _solutionGrid = grid;
        _placedWords = words;
        _userAnswers = userAnswers;
        _cellNumbers = cellNumbers;
        _showSolution = false;
        _hintsRemaining = _kMaxHints;
        _isLoading = false;
      });
      _saveGameState();
    } catch (e) {
      setState(() {
        _errorMessage = 'Error generating puzzle: $e';
        _isLoading = false;
      });
    }
  }

  // ── Game-state persistence ────────────────────────────────────────────────

  static const String _kSaveKey = 'crossword_current_game_v1';

  Future<void> _saveGameState() async {
    if (_solutionGrid.isEmpty || _showSolution) return;
    final prefs = await SharedPreferences.getInstance();
    final data = jsonEncode({
      'solutionGrid': _solutionGrid,
      'userAnswers': _userAnswers,
      'placedWords': _placedWords
          .map((w) => {
                'number': w.number,
                'word': w.word,
                'clue': w.clue,
                'x': w.x,
                'y': w.y,
                'orientation': w.orientation,
                'synonyms': w.synonyms,
              })
          .toList(),
      'cellNumbers': _cellNumbers,
      'hintsRemaining': _hintsRemaining,
      'difficulty': DifficultyConfig.stringFromLevel(_difficulty),
    });
    await prefs.setString(_kSaveKey, data);
  }

  Future<bool> _restoreGameState() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kSaveKey);
    if (saved == null) return false;
    try {
      final data = jsonDecode(saved) as Map<String, dynamic>;
      final solutionGrid = (data['solutionGrid'] as List)
          .map((row) => List<String>.from(row as List))
          .toList();
      final userAnswers = (data['userAnswers'] as List)
          .map((row) => List<String>.from(row as List))
          .toList();
      final placedWords = (data['placedWords'] as List).map((w) {
        final m = w as Map<String, dynamic>;
        return PlacedWord(
          number: m['number'] as int,
          word: m['word'] as String,
          clue: m['clue'] as String,
          x: m['x'] as int,
          y: m['y'] as int,
          orientation: m['orientation'] as String,
          synonyms: List<String>.from(m['synonyms'] as List? ?? []),
        );
      }).toList();
      final cellNumbers = Map<String, int>.from(
        (data['cellNumbers'] as Map).map(
          (k, v) => MapEntry(k as String, v as int),
        ),
      );
      final hintsRemaining = data['hintsRemaining'] as int;
      final difficulty = DifficultyConfig.levelFromString(
        data['difficulty'] as String? ?? 'expert',
      );
      setState(() {
        _solutionGrid = solutionGrid;
        _userAnswers = userAnswers;
        _placedWords = placedWords;
        _cellNumbers = cellNumbers;
        _hintsRemaining = hintsRemaining;
        _difficulty = difficulty;
        _showSolution = false;
        _isLoading = false;
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _clearSavedGame() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kSaveKey);
  }

  void _updateCell(int x, int y, String letter) {
    if (letter.isNotEmpty && !RegExp(r'[a-zA-Z]').hasMatch(letter)) return;
    setState(() {
      _userAnswers[y][x] = letter.toUpperCase();
    });
    _saveGameState();
    _checkCompletion();
  }

  void _checkCompletion() {
    if (_solutionGrid.isEmpty || _showSolution) return;

    // Every non-black cell must have a letter.
    for (int row = 0; row < _solutionGrid.length; row++) {
      for (int col = 0; col < _solutionGrid[row].length; col++) {
        if (_solutionGrid[row][col].isEmpty) continue; // black cell
        if (_userAnswers[row][col].isEmpty) return; // still blank
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
      _clearSavedGame();
      ScoreService.append(
        ScoreRecord(
          date: DateTime.now(),
          score: 100,
          totalWords: _placedWords.length,
          correctWords: _placedWords.length,
          solved: true,
          difficulty: DifficultyConfig.stringFromLevel(_difficulty),
        ),
      );
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
        final y = word.orientation == 'down' ? word.y + i : word.y;
        if (_userAnswers[y][x] != _solutionGrid[y][x]) {
          wordOk = false;
          break;
        }
      }
      if (wordOk) correct++;
    }
    return correct;
  }

  /// Returns the [PlacedWord] the user currently has selected (matching both
  /// cell position and direction), or null if nothing is selected.
  PlacedWord? _selectedWord() {
    final state = _gridKey.currentState;
    if (state == null) return null;
    final sel = state.selection;
    if (sel.x == null || sel.y == null) return null;

    for (final w in _placedWords) {
      if (w.orientation != sel.direction) continue;
      if (w.orientation == 'across') {
        if (w.y == sel.y! && sel.x! >= w.x && sel.x! < w.x + w.word.length) {
          return w;
        }
      } else {
        if (w.x == sel.x! && sel.y! >= w.y && sel.y! < w.y + w.word.length) {
          return w;
        }
      }
    }
    return null;
  }

  void _showHint() {
    if (_hintsRemaining <= 0 || _showSolution) return;

    final word = _selectedWord();
    if (word == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select a word first, then tap the hint button.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final syns = word.synonyms;
    if (syns.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No synonyms available for this word.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() => _hintsRemaining--);
    _saveGameState();

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.lightbulb, color: Colors.amber),
            const SizedBox(width: 8),
            Text(
              '${word.number}. ${word.orientation == 'across' ? 'Across' : 'Down'}',
              style: const TextStyle(fontSize: 16),
            ),
            const Spacer(),
            Text(
              '$_hintsRemaining hint${_hintsRemaining == 1 ? '' : 's'} left',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Clue: ${word.clue}',
              style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 13),
            ),
            const SizedBox(height: 12),
            const Text(
              'Synonyms:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: syns
                  .map(
                    (s) => Chip(
                      label: Text(s, style: const TextStyle(fontSize: 13)),
                      backgroundColor: Colors.deepPurple.shade50,
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _changeDifficulty(DifficultyLevel level) async {
    if (level == _difficulty) return;

    final hasProgress =
        _userAnswers.any((row) => row.any((c) => c.isNotEmpty));

    if (hasProgress && mounted) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Change difficulty?'),
          content: const Text(
            'Your current progress will be lost and a new puzzle will start.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Change'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    setState(() => _difficulty = level);
    await _generateNewPuzzle();
  }

  void _giveUp() {
    final total = _placedWords.length;
    final correct = _countCorrectWords();
    final score = total == 0 ? 0.0 : (correct / total) * 100.0;

    setState(() => _showSolution = true);
    _clearSavedGame();

    ScoreService.append(
      ScoreRecord(
        date: DateTime.now(),
        score: score,
        totalWords: total,
        correctWords: correct,
        solved: false,
        difficulty: DifficultyConfig.stringFromLevel(_difficulty),
      ),
    );

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
        title: Row(
          children: [
            Image.asset(
              'assets/icon.png',
              height: 36,
              width: 36,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: 12),
            DropdownButton<DifficultyLevel>(
              value: _difficulty,
              dropdownColor: Colors.deepPurple.shade800,
              underline: const SizedBox.shrink(),
              icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              items: const [
                DropdownMenuItem(
                  value: DifficultyLevel.easy,
                  child: Text('Easy'),
                ),
                DropdownMenuItem(
                  value: DifficultyLevel.intermediate,
                  child: Text('Medium'),
                ),
                DropdownMenuItem(
                  value: DifficultyLevel.expert,
                  child: Text('Expert'),
                ),
              ],
              onChanged: (level) {
                if (level != null) _changeDifficulty(level);
              },
            ),
          ],
        ),
        backgroundColor: Colors.deepPurple.shade700,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart_rounded),
            tooltip: 'Progress',
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const StatsScreen())),
          ),
          if (!_isLoading && _errorMessage == null)
            ..._showSolution
                ? [
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      tooltip: 'New Puzzle',
                      onPressed: _showInterstitialThenGenerate,
                    ),
                  ]
                : [
                    // Hint button — shows badge with remaining count.
                    Badge(
                      label: Text('$_hintsRemaining'),
                      isLabelVisible: _hintsRemaining < _kMaxHints,
                      backgroundColor: Colors.amber.shade700,
                      child: IconButton(
                        icon: Icon(
                          Icons.lightbulb_outline,
                          color: _hintsRemaining > 0
                              ? Colors.amber.shade300
                              : Colors.white30,
                        ),
                        tooltip:
                            '$_hintsRemaining hint${_hintsRemaining == 1 ? '' : 's'} remaining',
                        onPressed: _hintsRemaining > 0 ? _showHint : null,
                      ),
                    ),
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
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15),
            ),
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
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: CrosswordGrid(
                key: _gridKey,
                solutionGrid: _solutionGrid,
                displayGrid: _getDisplayGrid(),
                showSolution: _showSolution,
                cellNumbers: _cellNumbers,
                onCellChanged: _updateCell,
                onSelectionChanged: (x, y, dir) {
                  setState(() {
                    _activeWord = _placedWords.where((w) {
                      if (w.orientation != dir) return false;
                      if (dir == 'across') {
                        return w.y == y && x >= w.x && x < w.x + w.word.length;
                      }
                      return w.x == x && y >= w.y && y < w.y + w.word.length;
                    }).firstOrNull;
                  });
                },
              ),
            ),
          ),
        ),

        // ── Custom keyboard ──────────────────────────────────────────────
        if (!_showSolution)
          CrosswordKeyboard(
            onLetter: (l) => _gridKey.currentState?.inputLetter(l),
            onBackspace: () => _gridKey.currentState?.deleteLetter(),
          ),

        // ── Clue lists (fill remaining space, each scrolls independently)
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: CluePanel(
              placedWords: _placedWords,
              activeNumber: _activeWord?.number,
              activeOrientation: _activeWord?.orientation,
              onWordTap: _showSolution
                  ? null
                  : (w) {
                      setState(() => _activeWord = w);
                      _gridKey.currentState?.selectWord(
                        w.x,
                        w.y,
                        w.orientation,
                      );
                    },
            ),
          ),
        ),
      ],
    );
  }
}
