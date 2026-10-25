import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const WenquxingApp());
}

const ink = Color(0xFF243447);
const accent = Color(0xFF287D78);

// ============================== 数据模型 ==============================

class WordEntry {
  final String level, word, meaning, example, ipa;

  const WordEntry({
    required this.level,
    required this.word,
    required this.meaning,
    required this.example,
    required this.ipa,
  });

  factory WordEntry.fromJson(Map<String, dynamic> j) => WordEntry(
        level: j['level'] ?? '',
        word: j['word'] ?? '',
        meaning: j['meaning'] ?? '',
        example: j['example'] ?? '',
        ipa: j['ipa'] ?? '',
      );
}

class WordProgress {
  int seen;
  int correct;
  int wrong;
  int streak;
  int intervalDays;
  int dueAt;
  int lastAt;

  WordProgress({
    this.seen = 0,
    this.correct = 0,
    this.wrong = 0,
    this.streak = 0,
    this.intervalDays = 0,
    this.dueAt = 0,
    this.lastAt = 0,
  });

  factory WordProgress.fromJson(Map<String, dynamic> j) => WordProgress(
        seen: j['seen'] ?? 0,
        correct: j['correct'] ?? 0,
        wrong: j['wrong'] ?? 0,
        streak: j['streak'] ?? 0,
        intervalDays: j['intervalDays'] ?? 0,
        dueAt: j['dueAt'] ?? 0,
        lastAt: j['lastAt'] ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'seen': seen,
        'correct': correct,
        'wrong': wrong,
        'streak': streak,
        'intervalDays': intervalDays,
        'dueAt': dueAt,
        'lastAt': lastAt,
      };
}

int dayKeyOf([DateTime? d]) {
  final x = d ?? DateTime.now();
  return x.year * 10000 + x.month * 100 + x.day;
}

// ============================== App ==============================

class WenquxingApp extends StatelessWidget {
  const WenquxingApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: '文曲星背单词',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: accent),
          scaffoldBackgroundColor: const Color(0xFFF7F8FA),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFFF7F8FA),
            foregroundColor: ink,
            centerTitle: false,
          ),
          inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(),
            filled: true,
            fillColor: Colors.white,
          ),
        ),
        home: const HomePage(),
      );
}

// ============================== 首页 ==============================

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<WordEntry> words = [];
  Map<String, WordProgress> progress = {};
  Set<String> learned = {};
  Set<String> wrongs = {};
  int dailyGoal = 20;
  String level = '全部';
  bool loading = true;

  // 今日新学词数（仅统计当天首次学习的词），按日期存储
  int todayNewCount = 0;
  int todayKey = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = await rootBundle.loadString('assets/data/words.json');
      final decoded = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();

      words = decoded.map(WordEntry.fromJson).toList();

      final p = prefs.getString('progress_v1');
      if (p != null) {
        final m = jsonDecode(p) as Map<String, dynamic>;
        progress = m.map(
          (k, v) => MapEntry(
            k,
            WordProgress.fromJson(Map<String, dynamic>.from(v)),
          ),
        );
      }

      learned = (prefs.getStringList('learned_v1') ?? []).toSet();
      wrongs = (prefs.getStringList('wrongs_v1') ?? []).toSet();
      dailyGoal = prefs.getInt('daily_goal') ?? 20;

      // 恢复今日新词计数
      final storedKey = prefs.getInt('today_new_key') ?? 0;
      final storedCount = prefs.getInt('today_new_count') ?? 0;
      final currentKey = dayKeyOf();
      if (storedKey == currentKey) {
        todayNewCount = storedCount;
      } else {
        todayNewCount = 0;
      }
      todayKey = currentKey;
    } catch (e) {
      debugPrint('加载数据失败：$e');
    }

    if (mounted) setState(() => loading = false);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      'progress_v1',
      jsonEncode(progress.map((k, v) => MapEntry(k, v.toJson()))),
    );
    await prefs.setStringList('learned_v1', learned.toList());
    await prefs.setStringList('wrongs_v1', wrongs.toList());
    await prefs.setInt('daily_goal', dailyGoal);
    await prefs.setInt('today_new_key', todayKey);
    await prefs.setInt('today_new_count', todayNewCount);
  }

  /// 由 QuizPage 回调：某个词今日首次学习时更新计数
  void _notifyFirstLearnedToday() {
    final currentKey = dayKeyOf();
    if (todayKey != currentKey) {
      todayKey = currentKey;
      todayNewCount = 0;
    }
    todayNewCount++;
  }

  int get todayCount => todayNewCount;

  List<WordEntry> get availableWords => words
      .where((w) => level == '全部' || w.level == level)
      .toList();

  List<WordEntry> get dueWords => availableWords.where((w) {
        final p = progress[w.word];
        return p != null &&
            p.dueAt > 0 &&
            p.dueAt <= DateTime.now().millisecondsSinceEpoch;
      }).toList()
        ..sort((a, b) => (progress[a.word]?.dueAt ?? 0)
            .compareTo(progress[b.word]?.dueAt ?? 0));

  List<WordEntry> get newWords =>
      availableWords.where((w) => !learned.contains(w.word)).toList();

  void _start({required bool reviewOnly}) {
    final pool = reviewOnly
        ? dueWords
        : <WordEntry>[
            ...dueWords,
            ...newWords.take(max(0, dailyGoal - todayCount)),
          ];

    if (pool.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            reviewOnly
                ? '今天没有到期复习的单词。'
                : '今天的学习任务已完成，或当前词库已学完！',
          ),
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QuizPage(
          words: pool,
          progress: progress,
          learned: learned,
          wrongs: wrongs,
          onChanged: _save,
          onFirstLearnedToday: _notifyFirstLearnedToday,
          onFinished: () {
            if (mounted) setState(() {});
          },
        ),
      ),
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final due = dueWords.length;
    final progressRatio = dailyGoal == 0
        ? 0.0
        : (todayCount / dailyGoal).clamp(0.0, 1.0).toDouble();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '文曲星背单词',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SettingsPage(
                    initialGoal: dailyGoal,
                    onSave: (g) async {
                      setState(() => dailyGoal = g);
                      await _save();
                    },
                  ),
                ),
              );
            },
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF244B54), Color(0xFF287D78)],
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '每天一点，积少成多',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 23,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '今日进度  $todayCount / $dailyGoal 个新词',
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: LinearProgressIndicator(
                    value: progressRatio,
                    minHeight: 8,
                    backgroundColor: Colors.white24,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: ink,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                    onPressed: () => _start(reviewOnly: false),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('开始今日学习'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  label: '待复习',
                  value: '$due',
                  icon: Icons.replay_rounded,
                  color: const Color(0xFFB56B36),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatCard(
                  label: '已学单词',
                  value: '${learned.length}',
                  icon: Icons.menu_book_rounded,
                  color: accent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatCard(
                  label: '错题',
                  value: '${wrongs.length}',
                  icon: Icons.error_outline,
                  color: const Color(0xFFB94B4B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text(
            '选择词库级别',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ['全部', '初中', '高中', '四级', '大学']
                .map(
                  (x) => ChoiceChip(
                    label: Text(x),
                    selected: level == x,
                    onSelected: (_) => setState(() => level = x),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 22),
          _ActionTile(
            icon: Icons.replay_circle_filled_outlined,
            title: '复习到期单词',
            subtitle: '按记忆间隔安排，答错的词会更快回来',
            trailing: '$due 个',
            onTap: () => _start(reviewOnly: true),
          ),
          const SizedBox(height: 10),
          _ActionTile(
            icon: Icons.error_outline,
            title: '错题再练',
            subtitle: '集中练习曾经答错的单词',
            trailing: '${wrongs.length} 个',
            onTap: () {
              final pool = availableWords
                  .where((w) => wrongs.contains(w.word))
                  .toList();

              if (pool.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('错题本还是空的，继续学习后会自动收录。'),
                  ),
                );
                return;
              }

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => QuizPage(
                    words: pool,
                    progress: progress,
                    learned: learned,
                    wrongs: wrongs,
                    onChanged: _save,
                    onFirstLearnedToday: _notifyFirstLearnedToday,
                    onFinished: () {
                      if (mounted) setState(() {});
                    },
                  ),
                ),
              ).then((_) {
                if (mounted) setState(() {});
              });
            },
          ),
          const SizedBox(height: 10),
          _ActionTile(
            icon: Icons.library_books_outlined,
            title: '浏览词库',
            subtitle: '查看当前内置词汇与释义',
            trailing: '${availableWords.length} 词',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => WordListPage(
                  words: availableWords,
                  progress: progress,
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            '当前内置词库为启动测试版，包含初中、高中、四级和大学词汇。后续可继续扩充，并完善词频、词性和发音资源。',
            style: TextStyle(
              color: Colors.black54,
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================== 小组件 ==============================

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 7),
            Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
      );
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title, subtitle, trailing;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Card(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
          leading: CircleAvatar(
            backgroundColor: const Color(0xFFE6F2F0),
            child: Icon(icon, color: accent),
          ),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(subtitle),
          ),
          trailing: Text(
            trailing,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: accent,
            ),
          ),
          onTap: onTap,
        ),
      );
}

// ============================== 答题页 ==============================

class QuizPage extends StatefulWidget {
  final List<WordEntry> words;
  final Map<String, WordProgress> progress;
  final Set<String> learned, wrongs;
  final Future<void> Function() onChanged;
  final VoidCallback onFirstLearnedToday; // 首次学习当天记录
  final VoidCallback onFinished;

  const QuizPage({
    super.key,
    required this.words,
    required this.progress,
    required this.learned,
    required this.wrongs,
    required this.onChanged,
    required this.onFirstLearnedToday,
    required this.onFinished,
  });

  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> {
  late List<WordEntry> queue;
  int index = 0;
  late WordEntry current;
  late List<int> hidden;

  final Map<int, TextEditingController> _controllers = {};
  final Map<int, FocusNode> _focusNodes = {};

  bool checked = false;
  bool correct = false;
  bool showMeaning = false;
  String feedback = '';
  int right = 0;
  int answered = 0;

  bool _handlingInput = false;
  final FlutterTts _tts = FlutterTts();

  Future<void> _initTts() async {
    try {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.42);
      await _tts.setPitch(1.0);
      await _tts.awaitSpeakCompletion(true);
    } catch (e) {
      debugPrint('语音引擎初始化失败：$e');
    }
  }

  @override
  void initState() {
    super.initState();
    queue = [...widget.words]..shuffle();
    _initTts();
    _prepare();
  }

  void _disposeInputs() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final f in _focusNodes.values) {
      f.dispose();
    }
    _controllers.clear();
    _focusNodes.clear();
  }

  void _prepare() {
    if (index >= queue.length) return;

    current = queue[index];
    _disposeInputs();

    checked = false;
    correct = false;
    feedback = '';
    showMeaning = false;

    final n = current.word.length;
    final rng = Random();

    final count = n <= 3
        ? 1
        : (n <= 5
                ? max(2, (n / 3).floor())
                : max(2, (n / 3).round()))
            .clamp(1, n - 1)
            .toInt();

    final positions = List<int>.generate(n, (i) => i)..shuffle(rng);
    hidden = (positions.take(count).toList()..sort());

    for (final pos in hidden) {
      _controllers[pos] = TextEditingController();
      _focusNodes[pos] = FocusNode();
    }

    if (mounted) setState(() {});

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || hidden.isEmpty) return;
      _focusNodes[hidden.first]?.requestFocus();
    });
  }

  void _onLetterChanged(int pos, String value) {
    if (checked || _handlingInput) return;
    _handlingInput = true;

    try {
      final normalized = value.toLowerCase();

      if (normalized.isNotEmpty) {
        final letter = normalized.characters.last;
        _controllers[pos]!.value = TextEditingValue(
          text: letter,
          selection: TextSelection.collapsed(offset: letter.length),
        );

        final hiddenIndex = hidden.indexOf(pos);
        if (hiddenIndex >= 0 && hiddenIndex < hidden.length - 1) {
          _focusNodes[hidden[hiddenIndex + 1]]?.requestFocus();
        } else {
          _focusNodes[pos]?.unfocus();
        }
      } else {
        // 删除后自动回到上一个空格
        final hiddenIndex = hidden.indexOf(pos);
        if (hiddenIndex > 0) {
          _focusNodes[hidden[hiddenIndex - 1]]?.requestFocus();
        }
      }

      setState(() {});
    } finally {
      _handlingInput = false;
    }
  }

  void _submit() {
    if (checked) return;

    final answer = hidden.map((i) {
      return (_controllers[i]?.text ?? '').trim().toLowerCase();
    }).join();

    final expected = hidden.map((i) => current.word[i]).join();
    correct = answer == expected;

    final isFirstLearn = !widget.learned.contains(current.word);
    final p = widget.progress.putIfAbsent(
      current.word,
      () => WordProgress(),
    );

    final now = DateTime.now();

    p.seen++;
    p.lastAt = dayKeyOf(now);
    answered++;

    if (correct) {
      right++;
      p.correct++;
      p.streak++;

      p.intervalDays = p.streak <= 1
          ? 1
          : p.streak == 2
              ? 3
              : p.streak == 3
                  ? 7
                  : (p.intervalDays * 2).clamp(14, 180).toInt();

      p.dueAt = now
          .add(Duration(days: p.intervalDays))
          .millisecondsSinceEpoch;

      widget.learned.add(current.word);
      widget.wrongs.remove(current.word);
      feedback = '答对了！恭喜过关 🎉';

      // 首次学习且今日首次 → 计入今日新词进度
      if (isFirstLearn) {
        widget.onFirstLearnedToday();
      }
    } else {
      p.wrong++;
      p.streak = 0;
      p.intervalDays = 0;
      p.dueAt = now.add(const Duration(hours: 8)).millisecondsSinceEpoch;

      widget.wrongs.add(current.word);
      feedback = '再接再厉，正确答案是 ${current.word}';
    }

    setState(() => checked = true);
    widget.onChanged();
  }

  void _next() {
    if (!checked) return;

    if (index < queue.length - 1) {
      index++;
      _prepare();
    } else {
      widget.onFinished();

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('本轮完成！'),
          content: Text('本轮答题 $answered 个，答对 $right 个。错题已自动收录，之后会安排复习。'),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context);
              },
              child: const Text('完成'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _speak() async {
    try {
      await _tts.stop();
      await _tts.setLanguage('en-US');
      await _tts.speak(current.word);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('无法播放发音，请检查手机是否安装并启用英文语音引擎。'),
        ),
      );
    }
  }

  Future<void> _speakExample() async {
    final text = current.example.trim();
    if (text.isEmpty) return;
    try {
      await _tts.stop();
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.38);
      await _tts.speak(text);
      await _tts.setSpeechRate(0.42);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('例句朗读失败，请检查手机的英文语音数据。'),
        ),
      );
    }
  }

  Widget _buildWord() {
    // 输入框宽度随单词长度自适应，避免长单词挤爆
    final n = current.word.length;
    final fixedWidth = n > 14 ? 22.0 : 30.0;
    final inputWidth = n > 14 ? 26.0 : 34.0;
    final fontSize = n > 14 ? 26.0 : 32.0;

    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 1,
      children: List.generate(n, (i) {
        if (!hidden.contains(i)) {
          return SizedBox(
            width: fixedWidth,
            height: 58,
            child: Center(
              child: Text(
                current.word[i],
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w800,
                  color: ink,
                ),
              ),
            ),
          );
        }

        return SizedBox(
          width: inputWidth,
          height: 58,
          child: TextField(
            controller: _controllers[i],
            focusNode: _focusNodes[i],
            enabled: !checked,
            textAlign: TextAlign.center,
            maxLength: 1,
            keyboardType: TextInputType.text,
            textCapitalization: TextCapitalization.none,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp('[a-zA-Z]')),
              LengthLimitingTextInputFormatter(1),
            ],
            style: TextStyle(
              fontSize: fontSize - 2,
              fontWeight: FontWeight.w800,
              color: accent,
            ),
            decoration: const InputDecoration(
              counterText: '',
              isDense: true,
              contentPadding: EdgeInsets.only(bottom: 3),
              border: UnderlineInputBorder(
                borderSide: BorderSide(color: accent, width: 2),
              ),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: accent, width: 2),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: accent, width: 3),
              ),
              disabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: accent, width: 2),
              ),
            ),
            onChanged: (value) => _onLetterChanged(i, value),
          ),
        );
      }),
    );
  }

  @override
  void dispose() {
    _disposeInputs();
    _tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (index >= queue.length) {
      return const Scaffold(
        body: Center(child: Text('本轮结束')),
      );
    }

    final ipaText = current.ipa.trim();
    final meaningText = current.meaning.trim();
    final exampleText = current.example.trim();

    return Scaffold(
      appBar: AppBar(
        title: Text('单词练习  ${index + 1}/${queue.length}'),
        actions: [
          IconButton(
            onPressed: _speak,
            icon: const Icon(Icons.volume_up_outlined),
            tooltip: '发音',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(22),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Chip(label: Text(current.level)),
              Text(
                '本轮答对 $right 个',
                style: const TextStyle(
                  color: accent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          const Text(
            '补全单词',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 22),
          _buildWord(),
          const SizedBox(height: 28),
          if (meaningText.isNotEmpty)
            Text(
              meaningText,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20),
            ),
          const SizedBox(height: 10),
          if (ipaText.isNotEmpty)
            Text(
              '音标  /$ipaText/',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.black54,
                fontSize: 16,
              ),
            ),
          const SizedBox(height: 26),
          if (!checked)
            FilledButton(
              onPressed: _submit,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
              child: const Text('提交答案'),
            ),
          if (checked)
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: correct
                    ? const Color(0xFFE5F5ED)
                    : const Color(0xFFFFEEEE),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    feedback,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: correct
                          ? const Color(0xFF21734B)
                          : const Color(0xFFB33A3A),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    ipaText.isEmpty
                        ? current.word
                        : '${current.word}  /$ipaText/',
                  ),
                  if (meaningText.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(meaningText),
                  ],
                  if (exampleText.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    const Text(
                      '例句',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(exampleText),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _speakExample,
                        icon: const Icon(Icons.volume_up_outlined, size: 18),
                        label: const Text('朗读例句'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              setState(() => showMeaning = !showMeaning),
                          icon: const Icon(Icons.lightbulb_outline),
                          label: Text(showMeaning ? '收起提示' : '记忆提示'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton(
                          onPressed: _next,
                          child: Text(
                            index == queue.length - 1 ? '查看结果' : '下一个',
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (showMeaning) ...[
                    const SizedBox(height: 10),
                    Text('记忆提示：${current.word}'),
                    const Text('试着回忆单词的拼写、发音和含义之间的联系。'),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 20),
          Text(
            '小提示：直接在单词横线处输入缺失字母，输入后会自动跳到下一个空位；删除字母会自动回到上一个空位。',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================== 词库页 ==============================

class WordListPage extends StatelessWidget {
  final List<WordEntry> words;
  final Map<String, WordProgress> progress;

  const WordListPage({
    super.key,
    required this.words,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('词库（${words.length}）')),
        body: ListView.separated(
          itemCount: words.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (ctx, i) {
            final w = words[i];
            final p = progress[w.word];
            final ipa = w.ipa.trim();
            final parts = [
              if (w.meaning.trim().isNotEmpty) w.meaning,
              if (ipa.isNotEmpty) '/$ipa/',
              if (w.example.trim().isNotEmpty) w.example,
            ];

            return ListTile(
              title: Text(
                w.word,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                parts.join(' · '),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              isThreeLine: true,
              trailing: Text(
                p == null
                    ? '未学'
                    : (p.wrong > 0 ? '错 ${p.wrong} 次' : '已掌握'),
                style: const TextStyle(fontSize: 12, color: accent),
              ),
            );
          },
        ),
      );
}

// ============================== 设置页 ==============================

class SettingsPage extends StatefulWidget {
  final int initialGoal;
  final Future<void> Function(int) onSave;

  const SettingsPage({
    super.key,
    required this.initialGoal,
    required this.onSave,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late int goal;

  @override
  void initState() {
    super.initState();
    goal = widget.initialGoal;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('学习设置')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              '每日新词目标',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 10),
            Text(
              '$goal 个',
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: accent,
              ),
            ),
            Slider(
              value: goal.toDouble(),
              min: 5,
              max: 50,
              divisions: 9,
              label: '$goal',
              onChanged: (v) => setState(() => goal = v.round()),
            ),
            const Text(
              '建议先从每天 20 个开始。到期复习会优先加入今日练习，不计入新增词目标。',
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () async {
                await widget.onSave(goal);
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('保存设置'),
            ),
            const SizedBox(height: 20),
            const Text(
              '记忆算法说明',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 8),
            const Text(
              '答对后复习间隔依次延长：1 天 → 3 天 → 7 天，之后每次翻倍（上限 180 天）。答错则重置熟练度，并在约 8 小时后重新安排。该规则是第一版的简化间隔复习算法，并非严格复刻某一型号文曲星的内部算法。',
            ),
          ],
        ),
      );
}
