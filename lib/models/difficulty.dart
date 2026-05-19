/// Difficulty levels and their generator parameters.
enum DifficultyLevel { easy, intermediate, expert }

class DifficultyConfig {
  final String label;
  final int minWords;
  final int maxWords;
  final int minLen;
  final int maxLen;
  final int candidateSample;

  const DifficultyConfig({
    required this.label,
    required this.minWords,
    required this.maxWords,
    required this.minLen,
    required this.maxLen,
    required this.candidateSample,
  });

  static const easy = DifficultyConfig(
    label: 'Easy',
    minWords: 5,
    maxWords: 10,
    minLen: 3,
    maxLen: 6,
    candidateSample: 500,
  );

  static const intermediate = DifficultyConfig(
    label: 'Medium',
    minWords: 10,
    maxWords: 18,
    minLen: 3,
    maxLen: 8,
    candidateSample: 800,
  );

  static const expert = DifficultyConfig(
    label: 'Expert',
    minWords: 15,
    maxWords: 28,
    minLen: 2,
    maxLen: 10,
    candidateSample: 1000,
  );

  static DifficultyConfig forLevel(DifficultyLevel level) {
    switch (level) {
      case DifficultyLevel.easy:
        return easy;
      case DifficultyLevel.intermediate:
        return intermediate;
      case DifficultyLevel.expert:
        return expert;
    }
  }

  static DifficultyLevel levelFromString(String s) {
    switch (s) {
      case 'easy':
        return DifficultyLevel.easy;
      case 'intermediate':
        return DifficultyLevel.intermediate;
      default:
        return DifficultyLevel.expert;
    }
  }

  static String stringFromLevel(DifficultyLevel level) {
    switch (level) {
      case DifficultyLevel.easy:
        return 'easy';
      case DifficultyLevel.intermediate:
        return 'intermediate';
      case DifficultyLevel.expert:
        return 'expert';
    }
  }
}
