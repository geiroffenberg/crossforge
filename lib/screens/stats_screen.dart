import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../models/difficulty.dart';
import '../services/score_service.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({Key? key}) : super(key: key);

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  List<ScoreRecord> _records = [];
  bool _loading = true;
  DifficultyLevel? _filter; // null = All

  List<ScoreRecord> get _filtered => _filter == null
      ? _records
      : _records
          .where((r) =>
              r.difficulty == DifficultyConfig.stringFromLevel(_filter!))
          .toList();

  @override
  void initState() {
    super.initState();
    ScoreService.loadAll().then((r) {
      setState(() {
        _records = r;
        _loading = false;
      });
    });
  }

  // ── Summary helpers ──────────────────────────────────────────────────────

  int get _played => _filtered.length;
  int get _solved => _filtered.where((r) => r.solved).length;
  double get _avgScore => _played == 0
      ? 0
      : _filtered.map((r) => r.score).reduce((a, b) => a + b) / _played;
  double get _bestScore => _played == 0
      ? 0
      : _filtered.map((r) => r.score).reduce((a, b) => a > b ? a : b);

  // ── Chart data ───────────────────────────────────────────────────────────

  /// Last 50 games as FlSpots (x = game index, y = score).
  List<FlSpot> get _spots {
    final recent =
        _filtered.length > 50 ? _filtered.sublist(_filtered.length - 50) : _filtered;
    return [
      for (int i = 0; i < recent.length; i++) FlSpot(i.toDouble(), recent[i].score),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('Progress'),
        backgroundColor: Colors.deepPurple.shade700,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _played == 0
              ? _emptyState()
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _filterBar(),
                    const SizedBox(height: 12),
                    _summaryRow(),
                    const SizedBox(height: 20),
                    _chartCard(),
                    const SizedBox(height: 16),
                    _historyList(),
                  ],
                ),
    );
  }

  Widget _filterBar() {
    return SegmentedButton<DifficultyLevel?>(
      segments: const [
        ButtonSegment(value: null, label: Text('All')),
        ButtonSegment(value: DifficultyLevel.easy, label: Text('Easy')),
        ButtonSegment(
            value: DifficultyLevel.intermediate, label: Text('Medium')),
        ButtonSegment(value: DifficultyLevel.expert, label: Text('Expert')),
      ],
      selected: {_filter},
      onSelectionChanged: (s) => setState(() => _filter = s.first),
      style: ButtonStyle(visualDensity: VisualDensity.compact),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bar_chart, size: 72, color: Colors.deepPurple.shade200),
          const SizedBox(height: 16),
          Text(
            'No games yet',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.deepPurple.shade400),
          ),
          const SizedBox(height: 8),
          const Text('Complete or give up a puzzle to see your stats here.',
              textAlign: TextAlign.center),
        ],
      ),
    );
  }

  // ── Summary cards ─────────────────────────────────────────────────────────

  Widget _summaryRow() {
    return Row(
      children: [
        _statCard('Played', '$_played', Colors.deepPurple.shade600),
        const SizedBox(width: 12),
        _statCard('Solved', '$_solved', const Color(0xFF15803D)),
        const SizedBox(width: 12),
        _statCard('Average', '${_avgScore.toStringAsFixed(1)}%', Colors.orange.shade700),
        const SizedBox(width: 12),
        _statCard('Best', '${_bestScore.toStringAsFixed(0)}%', Colors.blue.shade700),
      ],
    );
  }

  Widget _statCard(String label, String value, Color color) {
    return Expanded(
      child: Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            children: [
              Text(value,
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: color)),
              const SizedBox(height: 4),
              Text(label,
                  style: const TextStyle(fontSize: 11, color: Colors.black54)),
            ],
          ),
        ),
      ),
    );
  }

  // ── Line chart ────────────────────────────────────────────────────────────

  Widget _chartCard() {
    final spots = _spots;
    if (spots.length < 2) {
      return Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
              child: Text('Play more puzzles to see your score trend.',
                  style: TextStyle(color: Colors.grey.shade600))),
        ),
      );
    }

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 20, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 12, bottom: 12),
              child: Text('Score trend (last 50 games)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            ),
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  minY: 0,
                  maxY: 100,
                  gridData: FlGridData(
                    show: true,
                    horizontalInterval: 25,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) =>
                        FlLine(color: Colors.grey.shade200, strokeWidth: 1),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 36,
                        interval: 25,
                        getTitlesWidget: (v, _) => Text(
                          '${v.toInt()}%',
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      curveSmoothness: 0.3,
                      color: Colors.deepPurple.shade500,
                      barWidth: 2.5,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, _, __, ___) =>
                            FlDotCirclePainter(
                          radius: 3,
                          color: spot.y >= 100
                              ? const Color(0xFF15803D)
                              : Colors.deepPurple.shade400,
                          strokeWidth: 0,
                        ),
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        color: Colors.deepPurple.shade100.withAlpha(100),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── History list ──────────────────────────────────────────────────────────

  Widget _historyList() {
    final reversed = _filtered.reversed.toList();
    return Card(
      elevation: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Text('History',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          const Divider(height: 1),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: reversed.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) => _historyTile(reversed[i], i + 1),
          ),
        ],
      ),
    );
  }

  Widget _historyTile(ScoreRecord r, int index) {
    final color = r.score >= 100
        ? const Color(0xFF15803D)
        : r.score >= 50
            ? Colors.orange.shade700
            : Colors.red.shade600;

    final dateStr = '${r.date.year}-'
        '${r.date.month.toString().padLeft(2, '0')}-'
        '${r.date.day.toString().padLeft(2, '0')}  '
        '${r.date.hour.toString().padLeft(2, '0')}:'
        '${r.date.minute.toString().padLeft(2, '0')}';

    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: color.withAlpha(30),
        child: Text(
          '${r.score.toStringAsFixed(0)}%',
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.bold, color: color),
        ),
      ),
      title: Text(dateStr,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      subtitle: Text(
        '${DifficultyConfig.forLevel(DifficultyConfig.levelFromString(r.difficulty)).label}  •  '
        '${r.solved ? 'Solved — all ${r.totalWords} words correct' : '${r.correctWords} / ${r.totalWords} words correct'}',
        style: const TextStyle(fontSize: 12),
      ),
      trailing: r.solved
          ? const Icon(Icons.star, color: Color(0xFF15803D), size: 18)
          : null,
    );
  }
}
