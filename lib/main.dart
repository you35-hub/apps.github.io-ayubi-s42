import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'orb_3d.dart';
import 'ayubi_mode.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(MobileAds.instance.initialize());
  RewardGate.loadAd();
  runApp(const AyubiApp());
}

class AyubiApp extends StatelessWidget {
  const AyubiApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ayubi_S42',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0E27),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E5FF),
          secondary: Color(0xFF7C4DFF),
        ),
      ),
      home: const ChatScreen(),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  // ============================================
  // 👇 PASTE YOUR REAL API KEY HERE 👇
  // ============================================
  static const String apiKey =
      String.fromEnvironment('OPENROUTER_KEY', defaultValue: '');
  // ============================================

  static const List<Map<String, String>> aiBrains = [
    {
      'name': 'Ayubi',
      'model': 'nvidia/nemotron-3-super-120b-a12b:free',
      'emoji': '🧠',
      'prompt':
          'You are Ayubi_S42, a helpful AI assistant. Answer concisely and clearly. Use Markdown formatting for code, lists, and emphasis.',
    },
    {
      'name': 'Reason',
      'model': 'nvidia/nemotron-3-ultra-550b-a55b:free',
      'emoji': '🔮',
      'prompt':
          'You are a deep reasoning AI. Think step by step. Format with Markdown headings, bold, numbered lists.',
    },
    {
      'name': 'Fast',
      'model': 'nex-agi/nex-n2.5-pro:free',
      'emoji': '⚡',
      'prompt':
          'You are a fast, direct assistant. Use short Markdown with bullets and bold.',
    },
    {
      'name': 'Code',
      'model': 'cohere/north-mini-code:free',
      'emoji': '💻',
      'prompt':
          'You are a coding assistant. Wrap code in triple backticks with language. Use Markdown headings.',
    },
  ];

  int _currentBrain = 0;
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<Map<String, String>> _messages = [];
  bool _loading = false;

  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();
  bool _voiceMode = true;
  bool _listening = false;
  bool _speaking = false;
  bool _autoSpeak = true;
  bool _speechReady = false;
  String _selectedVoice = 'default';
  List<Map<String, String>> _voices = [];
  String _liveTranscript = '';
  double _speechRate = 0.5;
  double _speechPitch = 1.0;

  final List<Map<String, String>> _modeMessages = [];
  final List<Map<String, String>> _liveMessages = [];
  bool _liveModeOpen = false;
  List<Map<String, dynamic>> _chats = [];
  int _activeChatIndex = -1;
  bool _historyOpen = false;
  bool _ayubiModeOpen = false;

  @override
  void initState() {
    super.initState();
    _initVoice();
    _loadHistory();
  }

  Future<void> _initVoice() async {
    await _tryInitSpeech();
    try {
      final voices = await _tts.getVoices;
      if (voices is List) {
        final parsed = voices
            .map((v) => {
                  'name': (v['name'] ?? '').toString(),
                  'locale': (v['locale'] ?? '').toString(),
                })
            .where((v) {
              final n = (v['name'] ?? '').toString().toLowerCase();
              return n.isNotEmpty &&
                  !n.contains('compact') &&
                  !n.contains('espeak');
            })
            .toList();
        if (mounted) {
          setState(() => _voices = parsed);
          if (parsed.isNotEmpty) {
            final englishVoice = parsed.firstWhere(
              (v) => (v['locale'] ?? '').toLowerCase().startsWith('en'),
              orElse: () => parsed.first,
            );
            _selectedVoice = englishVoice['name']!;
          }
        }
      }
    } catch (e) {
      debugPrint('TTS voices error: $e');
    }

    await _tts.setSpeechRate(_speechRate);
    await _tts.setPitch(_speechPitch);
    _tts.setCompletionHandler(() {
      if (mounted) setState(() => _speaking = false);
    });
    _tts.setErrorHandler((_) {
      if (mounted) setState(() => _speaking = false);
    });
  }

  Future<void> _tryInitSpeech() async {
    try {
      final ok = await _speech.initialize(
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            if (mounted) setState(() => _listening = false);
          }
        },
        onError: (_) {
          if (mounted) setState(() => _listening = false);
        },
      );
      if (mounted) setState(() => _speechReady = ok && _speech.isAvailable);
    } catch (e) {
      debugPrint('Speech init error: $e');
      if (mounted) setState(() => _speechReady = false);
    }
  }

  Future<void> _applyVoice() async {
    if (_selectedVoice == 'default') return;
    try {
      final v = _voices.firstWhere((x) => x['name'] == _selectedVoice);
      await _tts.setVoice({'name': v['name']!, 'locale': v['locale']!});
    } catch (_) {}
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('chats');
    if (raw != null) {
      final list = jsonDecode(raw) as List;
      if (mounted) {
        setState(() {
          _chats =
              list.map((e) => Map<String, dynamic>.from(e)).toList();
        });
      }
    }
    if (_chats.isEmpty) {
      _newChat(save: false);
    } else {
      _activeChatIndex = 0;
      _messages.clear();
      _messages.addAll((_chats[0]['messages'] as List)
          .map((e) => Map<String, String>.from(e)));
      if (mounted) setState(() {});
    }
  }

  Future<void> _saveHistory() async {
    if (_activeChatIndex < 0 || _activeChatIndex >= _chats.length) return;
    _chats[_activeChatIndex] = {
      'title': _chats[_activeChatIndex]['title'] ?? 'New chat',
      'messages': _messages,
    };
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('chats', jsonEncode(_chats));
  }

  void _newChat({bool save = true}) {
    setState(() {
      _chats.insert(0, {
        'title': 'New chat',
        'messages': <Map<String, String>>[],
      });
      _activeChatIndex = 0;
      _messages.clear();
    });
    if (save) _saveHistory();
  }

  void _switchChat(int index) {
    setState(() {
      _activeChatIndex = index;
      _messages.clear();
      _messages.addAll((_chats[index]['messages'] as List)
          .map((e) => Map<String, String>.from(e)));
      _historyOpen = false;
    });
  }

  void _deleteChat(int index) {
    setState(() {
      _chats.removeAt(index);
      if (_chats.isEmpty) {
        _newChat();
      } else {
        _activeChatIndex = 0;
        _messages.clear();
        _messages.addAll((_chats[0]['messages'] as List)
            .map((e) => Map<String, String>.from(e)));
      }
    });
    _saveHistory();
  }

  Future<bool> _ensureMicPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<void> _startListening() async {
    if (!_speechReady) {
      final granted = await _ensureMicPermission();
      if (!granted) {
        _snack('Please allow microphone permission');
        return;
      }
      await _tryInitSpeech();
      await Future.delayed(const Duration(milliseconds: 400));
    }

    if (!_speechReady) {
      _snack('Mic not available — restart the app once');
      return;
    }

    setState(() {
      _listening = true;
      _liveTranscript = '';
    });

    Timer? silenceTimer;
    void resetSilenceTimer() {
      silenceTimer?.cancel();
      silenceTimer = Timer(const Duration(milliseconds: 1500), () {
        if (mounted && _listening) {
          _finishListeningAndSend();
        }
      });
    }

    await _speech.listen(
      onResult: (result) {
        if (!mounted) return;
        setState(() {
          _liveTranscript = result.recognizedWords;
          if (!_ayubiModeOpen && !_liveModeOpen) {
            _controller.text = _liveTranscript;
          }
        });
        resetSilenceTimer();
        if (result.finalResult && _liveTranscript.trim().isNotEmpty) {
          silenceTimer?.cancel();
          _finishListeningAndSend();
        }
      },
      listenFor: const Duration(minutes: 5),
      pauseFor: const Duration(seconds: 5),
      partialResults: true,
      cancelOnError: false,
      listenMode: stt.ListenMode.dictation,
    );
  }

  Future<void> _finishListeningAndSend() async {
    if (!mounted) return;
    await _speech.stop();
    setState(() => _listening = false);

    final text = _liveTranscript.trim();
    if (text.isEmpty) return;

    _controller.text = text;
    await _send();

    if ((_ayubiModeOpen || _liveModeOpen) && _voiceMode) {
      _autoRestartMicAfterReply();
    }
  }

  void _autoRestartMicAfterReply() {
    Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final inVoiceMode = _ayubiModeOpen || _liveModeOpen;
      if (!_loading && !_speaking && inVoiceMode) {
        timer.cancel();
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted && inVoiceMode && !_listening && !_speaking) {
            _startListening();
          }
        });
      }
    });
  }

  Future<void> _stopListening() async {
    await _speech.stop();
    if (mounted) setState(() => _listening = false);
    if (_controller.text.trim().isNotEmpty &&
        !_ayubiModeOpen &&
        !_liveModeOpen) {
      _send();
    }
  }

  Future<void> _speak(String text) async {
    if (text.trim().isEmpty) return;
    setState(() => _speaking = true);
    await _applyVoice();
    try {
      await _tts.speak(text);
    } catch (e) {
      if (mounted) setState(() => _speaking = false);
    }
  }

  Future<void> _stopSpeaking() async {
    await _tts.stop();
    if (mounted) setState(() => _speaking = false);
  }

  OrbState get _orbState {
    if (_listening) return OrbState.listening;
    if (_loading) return OrbState.thinking;
    if (_speaking) return OrbState.speaking;
    return OrbState.idle;
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _openUrl(String url) async {
    String finalUrl = url.trim();
    if (!finalUrl.startsWith('http://') &&
        !finalUrl.startsWith('https://')) {
      finalUrl = 'https://$finalUrl';
    }
    try {
      await launchUrl(Uri.parse(finalUrl),
          mode: LaunchMode.externalApplication);
    } catch (e) {
      _snack('Could not open link');
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _loading) return;

    if (apiKey.isEmpty) {
      _snack('API key missing. Build with --dart-define=OPENROUTER_KEY=...');
      return;
    }

    final target = _liveModeOpen
        ? _liveMessages
        : (_ayubiModeOpen ? _modeMessages : _messages);

    setState(() {
      target.add({'role': 'user', 'content': text});
      target.add({'role': 'assistant', 'content': ''});
      _loading = true;
      if (!_ayubiModeOpen && !_liveModeOpen && _messages.length <= 2) {
        final t =
            text.length > 30 ? '${text.substring(0, 30)}...' : text;
        _chats[_activeChatIndex]['title'] = t;
      }
    });
    _controller.clear();
    _liveTranscript = '';
    if (!_ayubiModeOpen && !_liveModeOpen) _scrollDown();
    if (!_ayubiModeOpen && !_liveModeOpen) _saveHistory();

    final brain = aiBrains[_currentBrain];
    final history = target
        .where((m) => (m['content'] ?? '').isNotEmpty)
        .map((m) => {'role': m['role'], 'content': m['content']})
        .toList();

    try {
      final request = http.Request(
        'POST',
        Uri.parse('https://openrouter.ai/api/v1/chat/completions'),
      );
      request.headers.addAll({
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      });
      request.body = jsonEncode({
        'model': brain['model'],
        'stream': true,
        'messages': [
          {'role': 'system', 'content': brain['prompt']},
          ...history,
        ],
      });

      final response = await request.send();
      if (response.statusCode != 200) {
        final body = await response.stream.bytesToString();
        if (mounted) {
          setState(() {
            target.last['content'] =
                'Error ${response.statusCode}: $body';
          });
        }
        return;
      }

      final stream = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      await for (final line in stream) {
        if (line.startsWith('data: ')) {
          final data = line.substring(6).trim();
          if (data == '[DONE]') break;
          if (data.isEmpty) continue;
          try {
            final json = jsonDecode(data);
            final delta = json['choices']?[0]?['delta']?['content'];
            if (delta != null && delta is String) {
              if (mounted) {
                setState(() {
                  target.last['content'] =
                      (target.last['content'] ?? '') + delta;
                });
                if (!_ayubiModeOpen && !_liveModeOpen) _scrollDown();
              }
            }
          } catch (_) {}
        }
      }

      if (!_ayubiModeOpen && !_liveModeOpen) _saveHistory();
      if (_voiceMode && _autoSpeak) {
        await _speak(target.last['content'] ?? '');
      }
    } catch (e) {
      if (mounted) {
        setState(() => target.last['content'] = 'Connection error: $e');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
      if (!_ayubiModeOpen && !_liveModeOpen) _scrollDown();
    }
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    _tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_liveModeOpen) return _buildLiveMode();
    if (_ayubiModeOpen) return _buildAyubiMode();
    return _buildChatView();
  }

  Widget _buildAyubiMode() {
    final brain = aiBrains[_currentBrain];
    return Scaffold(
      backgroundColor: const Color(0xFF05071A),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text(brain['emoji']!,
                          style: const TextStyle(fontSize: 24)),
                      const SizedBox(width: 10),
                      Text(
                        'Ayubi_S42  •  ${brain['name']}',
                        style: const TextStyle(
                          color: Color(0xFF00E5FF),
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close,
                        color: Color(0xFF00E5FF)),
                    onPressed: () async {
                      await _stopSpeaking();
                      await _stopListening();
                      if (mounted) {
                        setState(() => _ayubiModeOpen = false);
                      }
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: SizedBox(
                  width: 320,
                  height: 320,
                  child: AyubiMode(
                    state: _orbState,
                    brainName: brain['name']!,
                    brainEmoji: brain['emoji']!,
                  ),
                ),
              ),
            ),
            if (_modeMessages.isNotEmpty &&
                (_modeMessages.last['content'] ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 120),
                  child: SingleChildScrollView(
                    child: Text(
                      _modeMessages.last['content'] ?? '',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 24, vertical: 12),
              child: Text(
                _listening
                    ? (_liveTranscript.isEmpty
                        ? 'Listening...'
                        : _liveTranscript)
                    : _loading
                        ? 'Thinking...'
                        : _speaking
                            ? 'Speaking...'
                            : 'Tap the mic and speak',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _listening
                      ? const Color(0xFF7C4DFF)
                      : _loading
                          ? const Color(0xFFFF4081)
                          : _speaking
                              ? const Color(0xFF00E676)
                              : Colors.white54,
                  fontSize: 15,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 24, top: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _circleBtn(
                    icon: _listening ? Icons.stop : Icons.mic,
                    active: _listening,
                    activeColor: const Color(0xFF7C4DFF),
                    onTap: () async {
                      if (_listening) {
                        await _stopListening();
                      } else {
                        await _stopSpeaking();
                        await _startListening();
                      }
                    },
                  ),
                  const SizedBox(width: 20),
                  _circleBtn(
                    icon: _voiceMode
                        ? Icons.volume_up
                        : Icons.volume_off,
                    active: _voiceMode,
                    activeColor: const Color(0xFF00E5FF),
                    onTap: () =>
                        setState(() => _voiceMode = !_voiceMode),
                  ),
                  const SizedBox(width: 20),
                  _circleBtn(
                    icon: _speaking
                        ? Icons.stop
                        : Icons.record_voice_over,
                    active: _speaking,
                    activeColor: const Color(0xFF00E676),
                    onTap: () async {
                      if (_speaking) {
                        await _stopSpeaking();
                      } else {
                        final last = _modeMessages.lastWhere(
                          (m) => m['role'] == 'assistant',
                          orElse: () => {'content': ''},
                        );
                        if ((last['content'] ?? '').isNotEmpty) {
                          await _speak(last['content']!);
                        }
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveMode() {
    final brain = aiBrains[_currentBrain];
    return Scaffold(
      backgroundColor: const Color(0xFF05071A),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text(brain['emoji']!,
                          style: const TextStyle(fontSize: 24)),
                      const SizedBox(width: 10),
                      Text(
                        'Live Voice  •  ${brain['name']}',
                        style: const TextStyle(
                          color: Color(0xFF00E5FF),
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close,
                        color: Color(0xFF00E5FF)),
                    onPressed: () async {
                      await _stopSpeaking();
                      await _stopListening();
                      if (mounted) {
                        setState(() => _liveModeOpen = false);
                        _saveLiveToHistory();
                      }
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: GestureDetector(
                  onTap: () async {
                    if (_speaking) {
                      await _stopSpeaking();
                      await _startListening();
                    } else if (_listening) {
                      await _stopListening();
                    } else {
                      await _startListening();
                    }
                  },
                  child: SizedBox(
                    width: 320,
                    height: 320,
                    child: AyubiMode(
                      state: _orbState,
                      brainName: brain['name']!,
                      brainEmoji: brain['emoji']!,
                    ),
                  ),
                ),
              ),
            ),
            if (_liveMessages.isNotEmpty &&
                (_liveMessages.last['content'] ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 140),
                  child: SingleChildScrollView(
                    child: Text(
                      _liveMessages.last['content'] ?? '',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 24, vertical: 12),
              child: Text(
                _listening
                    ? (_liveTranscript.isEmpty
                        ? '🎤 Listening...'
                        : _liveTranscript)
                    : _loading
                        ? '💭 Thinking...'
                        : _speaking
                            ? '🔊 Speaking... (tap orb to interrupt)'
                            : 'Tap the orb to speak',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _listening
                      ? const Color(0xFF7C4DFF)
                      : _loading
                          ? const Color(0xFFFF4081)
                          : _speaking
                              ? const Color(0xFF00E676)
                              : Colors.white54,
                  fontSize: 15,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 24, top: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _circleBtn(
                    icon: _listening ? Icons.stop : Icons.mic,
                    active: _listening,
                    activeColor: const Color(0xFF7C4DFF),
                    onTap: () async {
                      if (_listening) {
                        await _stopListening();
                      } else {
                        await _stopSpeaking();
                        await _startListening();
                      }
                    },
                  ),
                  const SizedBox(width: 20),
                  _circleBtn(
                    icon: _speaking
                        ? Icons.stop
                        : Icons.record_voice_over,
                    active: _speaking,
                    activeColor: const Color(0xFF00E676),
                    onTap: () async {
                      if (_speaking) {
                        await _stopSpeaking();
                      } else {
                        final last = _liveMessages.lastWhere(
                          (m) => m['role'] == 'assistant',
                          orElse: () => {'content': ''},
                        );
                        if ((last['content'] ?? '').isNotEmpty) {
                          await _speak(last['content']!);
                        }
                      }
                    },
                  ),
                  const SizedBox(width: 20),
                  _circleBtn(
                    icon: Icons.delete_sweep,
                    active: false,
                    activeColor: const Color(0xFFFF4081),
                    onTap: () {
                      setState(() => _liveMessages.clear());
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveLiveToHistory() async {
    if (_liveMessages.isEmpty) return;
    final firstUser = _liveMessages.firstWhere(
      (m) => m['role'] == 'user',
      orElse: () => {'content': 'Live voice chat'},
    );
    final title = (firstUser['content'] ?? 'Live chat').length > 30
        ? '🎤 ${(firstUser['content'] ?? '').substring(0, 30)}...'
        : '🎤 ${firstUser['content'] ?? 'Live chat'}';

    setState(() {
      _chats.insert(0, {
        'title': title,
        'messages': List<Map<String, String>>.from(_liveMessages),
      });
      _activeChatIndex = 0;
      _messages.clear();
      _messages.addAll(List<Map<String, String>>.from(_liveMessages));
    });
    await _saveHistory();
  }

  Widget _buildChatView() {
    final showThinking = _loading &&
        (_messages.isEmpty ||
            (_messages.last['role'] == 'assistant' &&
                (_messages.last['content'] ?? '').isEmpty));

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0E27),
        elevation: 0,
        title: Row(
          children: [
            SizedBox(
              width: 50,
              height: 50,
              child: Orb3D(state: _orbState, size: 50),
            ),
            const SizedBox(width: 8),
            const Text(
              'Ayubi_S42',
              style: TextStyle(
                color: Color(0xFF00E5FF),
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.graphic_eq, color: Color(0xFF00E676)),
            onPressed: () async {
              final unlocked = await RewardGate.showAd();
              if (unlocked && mounted) {
                setState(() {
                  _liveModeOpen = true;
                  _liveMessages.clear();
                  _voiceMode = true;
                  _autoSpeak = true;
                });
                await Future.delayed(const Duration(milliseconds: 600));
                if (mounted && _liveModeOpen) _startListening();
              }
            },
            tooltip: 'Live Voice Chat (Watch Ad)',
          ),
          IconButton(
            icon: const Icon(Icons.blur_on, color: Color(0xFF00E5FF)),
            onPressed: () async {
              final unlocked = await RewardGate.showAd();
              if (unlocked && mounted) {
                setState(() {
                  _ayubiModeOpen = true;
                  _modeMessages.clear();
                });
              }
            },
            tooltip: 'Ayubi_S42 Mode (Watch Ad)',
          ),
          IconButton(
            icon: const Icon(Icons.add_comment_outlined,
                color: Color(0xFF00E5FF)),
            onPressed: () => _newChat(),
            tooltip: 'New chat',
          ),
          IconButton(
            icon: const Icon(Icons.menu, color: Color(0xFF00E5FF)),
            onPressed: () =>
                setState(() => _historyOpen = !_historyOpen),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: List.generate(aiBrains.length, (i) {
                      final brain = aiBrains[i];
                      final selected = i == _currentBrain;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () => setState(() => _currentBrain = i),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              gradient: selected
                                  ? const LinearGradient(colors: [
                                      Color(0xFF00E5FF),
                                      Color(0xFF7C4DFF),
                                    ])
                                  : null,
                              color: selected
                                  ? null
                                  : const Color(0xFF1A1F3A),
                              borderRadius: BorderRadius.circular(20),
                              border: selected
                                  ? null
                                  : Border.all(
                                      color: const Color(0xFF00E5FF)
                                          .withOpacity(0.3),
                                    ),
                            ),
                            child: Row(
                              children: [
                                Text(brain['emoji']!,
                                    style: const TextStyle(fontSize: 14)),
                                const SizedBox(width: 6),
                                Text(
                                  brain['name']!,
                                  style: TextStyle(
                                    color: selected
                                        ? Colors.black
                                        : const Color(0xFF00E5FF),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ),
              Expanded(
                child: _messages.isEmpty
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 280,
                            height: 280,
                            child:
                                Orb3D(state: _orbState, size: 280),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'Ask me anything...',
                            style: TextStyle(
                                color: Colors.white38, fontSize: 16),
                          ),
                        ],
                      )
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.all(16),
                        itemCount:
                            _messages.length + (showThinking ? 1 : 0),
                        itemBuilder: (_, i) {
                          if (showThinking && i == _messages.length) {
                            return const ThinkingIndicator();
                          }
                          final m = _messages[i];
                          final isUser = m['role'] == 'user';
                          return Align(
                            alignment: isUser
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: GestureDetector(
                              onLongPress: () {
                                Clipboard.setData(ClipboardData(
                                    text: m['content'] ?? ''));
                                _snack('Copied');
                              },
                              child: Container(
                                margin: const EdgeInsets.symmetric(
                                    vertical: 6),
                                padding: const EdgeInsets.all(14),
                                constraints: BoxConstraints(
                                  maxWidth: MediaQuery.of(context)
                                          .size
                                          .width *
                                      0.78,
                                ),
                                decoration: BoxDecoration(
                                  gradient: isUser
                                      ? const LinearGradient(colors: [
                                          Color(0xFF00E5FF),
                                          Color(0xFF7C4DFF),
                                        ])
                                      : null,
                                  color: isUser
                                      ? null
                                      : const Color(0xFF1A1F3A),
                                  borderRadius:
                                      BorderRadius.circular(16),
                                ),
                                child: isUser
                                    ? SelectableText(
                                        m['content'] ?? '',
                                        style: const TextStyle(
                                          color: Colors.black,
                                          fontSize: 15,
                                        ),
                                      )
                                    : MarkdownBody(
                                        data: m['content'] ?? '',
                                        onTapLink: (text, href, title) {
                                          if (href != null) _openUrl(href);
                                        },
                                        selectable: true,
                                        styleSheet:
                                            MarkdownStyleSheet(
                                          p: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 15,
                                              height: 1.5),
                                          h1: const TextStyle(
                                              color: Color(0xFF00E5FF),
                                              fontSize: 22,
                                              fontWeight:
                                                  FontWeight.bold),
                                          h2: const TextStyle(
                                              color: Color(0xFF00E5FF),
                                              fontSize: 19,
                                              fontWeight:
                                                  FontWeight.bold),
                                          h3: const TextStyle(
                                              color: Color(0xFF7C4DFF),
                                              fontSize: 17,
                                              fontWeight:
                                                  FontWeight.bold),
                                          strong: const TextStyle(
                                              color: Color(0xFF00E5FF),
                                              fontWeight:
                                                  FontWeight.bold),
                                          em: const TextStyle(
                                              color: Colors.white70,
                                              fontStyle:
                                                  FontStyle.italic),
                                          code: const TextStyle(
                                              color: Color(0xFF00E676),
                                              backgroundColor:
                                                  Color(0xFF0A0E27),
                                              fontFamily: 'monospace'),
                                          codeblockDecoration:
                                              BoxDecoration(
                                            color: const Color(0xFF0A0E27),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          listBullet: const TextStyle(
                                              color: Color(0xFF00E5FF)),
                                        ),
                                      ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
              if (_listening)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    _liveTranscript.isEmpty
                        ? 'Listening...'
                        : _liveTranscript,
                    style: const TextStyle(
                        color: Color(0xFF7C4DFF), fontSize: 13),
                  ),
                ),
              SafeArea(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  color: const Color(0xFF0A0E27),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () =>
                            setState(() => _voiceMode = !_voiceMode),
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _voiceMode
                                ? const Color(0xFF00E5FF)
                                : const Color(0xFF1A1F3A),
                          ),
                          child: Icon(
                            _voiceMode
                                ? Icons.volume_up
                                : Icons.volume_off,
                            color: _voiceMode
                                ? Colors.black
                                : const Color(0xFF00E5FF),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          style: const TextStyle(color: Colors.white),
                          onSubmitted: (_) => _send(),
                          decoration: InputDecoration(
                            hintText: _voiceMode
                                ? 'Voice on — tap mic'
                                : 'Type a message...',
                            hintStyle: const TextStyle(
                                color: Colors.white38),
                            filled: true,
                            fillColor: const Color(0xFF1A1F3A),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 18, vertical: 14),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _listening
                            ? _stopListening
                            : _startListening,
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _listening
                                ? const Color(0xFF7C4DFF)
                                : const Color(0xFF1A1F3A),
                          ),
                          child: Icon(
                            _listening ? Icons.stop : Icons.mic,
                            color: _listening
                                ? Colors.white
                                : const Color(0xFF00E5FF),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _send,
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [
                                Color(0xFF00E5FF),
                                Color(0xFF7C4DFF),
                              ],
                            ),
                          ),
                          child: const Icon(Icons.send,
                              color: Colors.black),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (_historyOpen) _buildSidebar(),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    return Positioned(
      top: 0,
      bottom: 0,
      left: 0,
      width: 300,
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0F1430),
          boxShadow: [
            BoxShadow(color: Colors.black54, blurRadius: 20),
          ],
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Settings',
                      style: TextStyle(
                        color: Color(0xFF00E5FF),
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close,
                          color: Colors.white70),
                      onPressed: () =>
                          setState(() => _historyOpen = false),
                    ),
                  ],
                ),
              ),
              if (_voices.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('AI Voice / Language',
                          style: TextStyle(
                              color: Colors.white54, fontSize: 12)),
                      const SizedBox(height: 6),
                      Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1F3A),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: DropdownButton<String>(
                          value: _selectedVoice,
                          dropdownColor: const Color(0xFF0F1430),
                          isExpanded: true,
                          underline: const SizedBox(),
                          style: const TextStyle(
                              color: Color(0xFF00E5FF), fontSize: 13),
                          items: [
                            const DropdownMenuItem(
                              value: 'default',
                              child: Text('🌐 System default',
                                  style: TextStyle(
                                      color: Color(0xFF00E5FF))),
                            ),
                            ..._voices.take(40).map(
                                  (v) => DropdownMenuItem(
                                    value: v['name'],
                                    child: Text(
                                      _friendlyVoiceName(
                                          v['name']!, v['locale'] ?? ''),
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          color: Color(0xFF00E5FF),
                                          fontSize: 12),
                                    ),
                                  ),
                                ),
                          ],
                          onChanged: (v) async {
                            setState(() => _selectedVoice = v!);
                            await _applyVoice();
                            await _tts
                                .speak(_voicePreviewFor(v!));
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Voice speed  ${_speechRate.toStringAsFixed(1)}x',
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 12),
                    ),
                    Slider(
                      value: _speechRate,
                      min: 0.2,
                      max: 1.5,
                      divisions: 13,
                      activeColor: const Color(0xFF00E5FF),
                      onChanged: (v) async {
                        setState(() => _speechRate = v);
                        await _tts.setSpeechRate(v);
                      },
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Voice pitch  ${_speechPitch.toStringAsFixed(1)}',
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 12),
                    ),
                    Slider(
                      value: _speechPitch,
                      min: 0.5,
                      max: 2.0,
                      divisions: 15,
                      activeColor: const Color(0xFF7C4DFF),
                      onChanged: (v) async {
                        setState(() => _speechPitch = v);
                        await _tts.setPitch(v);
                      },
                    ),
                  ],
                ),
              ),
              SwitchListTile(
                title: const Text('Auto-speak replies',
                    style: TextStyle(
                        color: Colors.white70, fontSize: 13)),
                value: _autoSpeak,
                activeColor: const Color(0xFF00E5FF),
                onChanged: (v) => setState(() => _autoSpeak = v),
              ),
              const Divider(color: Colors.white12),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text('Chat History',
                    style: TextStyle(
                        color: Colors.white54, fontSize: 12)),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: _chats.length,
                  itemBuilder: (_, i) {
                    final chat = _chats[i];
                    final active = i == _activeChatIndex;
                    return ListTile(
                      selected: active,
                      selectedTileColor:
                          const Color(0xFF00E5FF).withOpacity(0.1),
                      title: Text(
                        chat['title'] ?? 'New chat',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: active
                              ? const Color(0xFF00E5FF)
                              : Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline,
                            size: 18, color: Colors.white38),
                        onPressed: () => _deleteChat(i),
                      ),
                      onTap: () => _switchChat(i),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _friendlyVoiceName(String name, String locale) {
    final parts = locale.split('-');
    final langCode = parts.isNotEmpty ? parts[0].toLowerCase() : '';
    final countryCode =
        parts.length > 1 ? parts[1].toUpperCase() : '';
    final lang = _languageName(langCode);
    final country = _countryName(countryCode);

    final lowerName = name.toLowerCase();
    String gender = '';
    if (lowerName.contains('female') ||
        lowerName.contains('#f') ||
        lowerName.contains('_f')) {
      gender = ' — Female';
    } else if (lowerName.contains('male') ||
        lowerName.contains('#m') ||
        lowerName.contains('_m')) {
      gender = ' — Male';
    }

    if (country.isNotEmpty) {
      return '🌐 $lang ($country)$gender';
    }
    return '🌐 $lang$gender';
  }

  String _languageName(String code) {
    switch (code) {
      case 'en': return 'English';
      case 'ur': return 'Urdu';
      case 'hi': return 'Hindi';
      case 'ar': return 'Arabic';
      case 'fa': return 'Persian';
      case 'tr': return 'Turkish';
      case 'fr': return 'French';
      case 'de': return 'German';
      case 'es': return 'Spanish';
      case 'it': return 'Italian';
      case 'pt': return 'Portuguese';
      case 'ru': return 'Russian';
      case 'zh': return 'Chinese';
      case 'ja': return 'Japanese';
      case 'ko': return 'Korean';
      case 'bn': return 'Bengali';
      case 'pa': return 'Punjabi';
      case 'ta': return 'Tamil';
      case 'te': return 'Telugu';
      case 'ml': return 'Malayalam';
      case 'gu': return 'Gujarati';
      case 'mr': return 'Marathi';
      case 'ne': return 'Nepali';
      case 'si': return 'Sinhala';
      case 'id': return 'Indonesian';
      case 'ms': return 'Malay';
      case 'th': return 'Thai';
      case 'vi': return 'Vietnamese';
      case 'nl': return 'Dutch';
      case 'pl': return 'Polish';
      case 'sv': return 'Swedish';
      case 'da': return 'Danish';
      case 'no': return 'Norwegian';
      case 'fi': return 'Finnish';
      case 'el': return 'Greek';
      case 'he': return 'Hebrew';
      case 'sw': return 'Swahili';
      default: return code.toUpperCase();
    }
  }

  String _countryName(String code) {
    switch (code) {
      case 'US': return 'United States';
      case 'GB':
      case 'UK': return 'United Kingdom';
      case 'PK': return 'Pakistan';
      case 'IN': return 'India';
      case 'SA': return 'Saudi Arabia';
      case 'AE': return 'UAE';
      case 'EG': return 'Egypt';
      case 'IR': return 'Iran';
      case 'TR': return 'Turkey';
      case 'FR': return 'France';
      case 'DE': return 'Germany';
      case 'ES': return 'Spain';
      case 'IT': return 'Italy';
      case 'BR': return 'Brazil';
      case 'PT': return 'Portugal';
      case 'RU': return 'Russia';
      case 'CN': return 'China';
      case 'TW': return 'Taiwan';
      case 'JP': return 'Japan';
      case 'KR': return 'South Korea';
      case 'BD': return 'Bangladesh';
      case 'LK': return 'Sri Lanka';
      case 'NP': return 'Nepal';
      case 'ID': return 'Indonesia';
      case 'MY': return 'Malaysia';
      case 'TH': return 'Thailand';
      case 'VN': return 'Vietnam';
      case 'NL': return 'Netherlands';
      case 'PL': return 'Poland';
      case 'SE': return 'Sweden';
      case 'DK': return 'Denmark';
      case 'NO': return 'Norway';
      case 'FI': return 'Finland';
      case 'GR': return 'Greece';
      case 'IL': return 'Israel';
      case 'ZA': return 'South Africa';
      case 'AU': return 'Australia';
      case 'CA': return 'Canada';
      case 'NZ': return 'New Zealand';
      default: return code;
    }
  }

  String _voicePreviewFor(String voiceName) {
    try {
      final v = _voices.firstWhere((x) => x['name'] == voiceName);
      final locale = v['locale'] ?? '';
      final lang = locale.split('-').first.toLowerCase();
      switch (lang) {
        case 'ur': return 'السلام علیکم، میں ایوبی ہوں۔';
        case 'ar': return 'مرحبا، أنا أيوبي.';
        case 'fa': return 'سلام، من ایوبی هستم.';
        case 'hi': return 'नमस्ते, मैं अयूबी हूँ।';
        case 'bn': return 'হ্যালো, আমি আইয়ুবি।';
        case 'pa': return 'ਸਤ ਸ੍ਰੀ ਅਕਾਲ, ਮੈਂ ਅਯੂਬੀ ਹਾਂ।';
        case 'tr': return 'Merhaba, ben Ayubi.';
        case 'fr': return 'Bonjour, je suis Ayubi.';
        case 'de': return 'Hallo, ich bin Ayubi.';
        case 'es': return 'Hola, soy Ayubi.';
        case 'it': return 'Ciao, sono Ayubi.';
        case 'pt': return 'Olá, eu sou Ayubi.';
        case 'ru': return 'Привет, я Аюби.';
        case 'zh': return '你好，我是阿尤比。';
        case 'ja': return 'こんにちは、アユビです。';
        case 'ko': return '안녕하세요, 저는 아유비입니다.';
        case 'id': return 'Halo, saya Ayubi.';
        default: return 'Hello, I am Ayubi S 42.';
      }
    } catch (_) {
      return 'Hello, I am Ayubi S 42.';
    }
  }

  Widget _circleBtn({
    required IconData icon,
    required bool active,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? activeColor : const Color(0xFF1A1F3A),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: activeColor.withOpacity(0.6),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: Icon(
          icon,
          color: active ? Colors.black : const Color(0xFF00E5FF),
          size: 28,
        ),
      ),
    );
  }
}

class RewardGate {
  static RewardedAd? _rewardedAd;
  static bool _isLoading = false;

  // Test Ad Unit ID — REPLACE with your real AdMob rewarded unit ID later
  static const String adUnitId =
      'ca-app-pub-3940256099942544/5224354917';

  static void loadAd() {
    if (_isLoading || _rewardedAd != null) return;
    _isLoading = true;

    RewardedAd.load(
      adUnitId: adUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
          _isLoading = false;
        },
        onAdFailedToLoad: (error) {
          _isLoading = false;
          debugPrint('Ad failed to load: $error');
        },
      ),
    );
  }

  static Future<bool> showAd() async {
    if (_rewardedAd == null) {
      loadAd();
      await Future.delayed(const Duration(seconds: 2));
      if (_rewardedAd == null) return false;
    }

    bool earned = false;
    await _rewardedAd!.show(
      onUserEarnedReward: (ad, reward) {
        earned = true;
      },
    );
    _rewardedAd = null;
    loadAd();
    return earned;
  }
}

class ThinkingIndicator extends StatefulWidget {
  const ThinkingIndicator({super.key});
  @override
  State<ThinkingIndicator> createState() => _ThinkingIndicatorState();
}

class _ThinkingIndicatorState extends State<ThinkingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1F3A),
          borderRadius: BorderRadius.circular(16),
        ),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (_, __) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) {
                final delay = i * 0.2;
                final t = (_controller.value - delay) % 1.0;
                final scale =
                    0.6 + 0.4 * (1 - (t - 0.5).abs() * 2);
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF00E5FF),
                      ),
                    ),
                  ),
                );
              }),
            );
          },
        ),
      ),
    );
  }
}