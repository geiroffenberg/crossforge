import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// A single completed game result.
class ScoreRecord {
  final DateTime date;

  /// Score percentage 0–100.
  final double score;

  final int totalWords;
  final int correctWords;

  /// True when the player solved the puzzle without giving up.
  final bool solved;

  /// Difficulty level: 'easy', 'intermediate', or 'expert'.
  final String difficulty;

  const ScoreRecord({
    required this.date,
    required this.score,
    required this.totalWords,
    required this.correctWords,
    required this.solved,
    this.difficulty = 'expert',
  });

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String(),
        'score': score,
        'totalWords': totalWords,
        'correctWords': correctWords,
        'solved': solved,
        'difficulty': difficulty,
      };

  factory ScoreRecord.fromJson(Map<String, dynamic> json) => ScoreRecord(
        date: DateTime.parse(json['date'] as String),
        score: (json['score'] as num).toDouble(),
        totalWords: json['totalWords'] as int,
        correctWords: json['correctWords'] as int,
        solved: json['solved'] as bool,
        difficulty: json['difficulty'] as String? ?? 'expert',
      );
}

/// Persists and retrieves score records using shared_preferences.
class ScoreService {
  static const _key = 'crossword_scores_v1';

  static Future<List<ScoreRecord>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => ScoreRecord.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<void> append(ScoreRecord record) async {
    final prefs = await SharedPreferences.getInstance();
    final records = await loadAll();
    records.add(record);
    await prefs.setString(
        _key, jsonEncode(records.map((r) => r.toJson()).toList()));
  }

  /// Clears all stored scores (useful for testing / reset).
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
