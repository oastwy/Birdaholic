import 'package:flutter/material.dart';
import '../services/speech_service.dart';

class VoiceNoteField extends StatefulWidget {
  final TextEditingController controller;
  final String hintText;
  final int maxLines;

  const VoiceNoteField({
    super.key,
    required this.controller,
    this.hintText = '添加备注...',
    this.maxLines = 3,
  });

  @override
  State<VoiceNoteField> createState() => _VoiceNoteFieldState();
}

class _VoiceNoteFieldState extends State<VoiceNoteField> {
  bool _listening = false;

  SpeechService get _svc => SpeechService.instance;

  @override
  void initState() {
    super.initState();
    // Wait for the singleton future (cached — no duplicate init).
    _svc.init().then((ok) {
      if (mounted) setState(() {});
    });
  }

  void _onStatus(String s) {
    if (s == 'done' || s == 'notListening') {
      if (mounted) setState(() => _listening = false);
    }
  }

  @override
  void dispose() {
    if (_listening) _svc.speech.stop();
    super.dispose();
  }

  Future<void> _toggleListening() async {
    if (_listening) {
      await _svc.speech.stop();
      setState(() => _listening = false);
      return;
    }
    if (!_svc.available) {
      final ok = await _svc.requestAndInit();
      if (!mounted) return;
      setState(() {});
      if (!ok) return;
    }
    // Attach status listener before calling listen().
    _svc.speech.statusListener = _onStatus;

    // Find the best available Chinese locale, fall back to default.
    String? localeId;
    try {
      final locales = await _svc.speech.locales();
      final zh = locales.firstWhere(
        (l) => l.localeId.startsWith('zh'),
        orElse: () => locales.first,
      );
      localeId = zh.localeId;
    } catch (_) {}

    setState(() => _listening = true);
    try {
      await _svc.speech.listen(
        localeId: localeId,
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 4),
        onResult: (result) {
          if (!mounted) return;
          if (result.recognizedWords.isNotEmpty) {
            widget.controller.text = result.recognizedWords;
            widget.controller.selection = TextSelection.fromPosition(
              TextPosition(offset: widget.controller.text.length),
            );
          }
        },
      );
    } catch (e) {
      if (mounted) setState(() => _listening = false);
      return;
    }
    // If listen() returned but isListening is false, it failed silently.
    if (mounted && !_svc.speech.isListening) {
      setState(() => _listening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final available = _svc.available;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: widget.controller,
          maxLines: widget.maxLines,
          decoration: InputDecoration(
            hintText: widget.hintText,
            border: const OutlineInputBorder(),
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                color: _listening ? Colors.red[50] : Colors.green[50],
                borderRadius: BorderRadius.circular(20),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: _toggleListening,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _listening ? Icons.mic : Icons.mic_none,
                        size: 16,
                        color: _listening
                            ? Colors.red
                            : (available ? Colors.green[700] : Colors.grey),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _listening ? '点击停止' : '语音输入',
                        style: TextStyle(
                          fontSize: 12,
                          color: _listening
                              ? Colors.red
                              : (available
                                  ? Colors.green[700]
                                  : Colors.grey),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_listening) ...[
              const SizedBox(width: 8),
              const _PulsingDot(),
              const SizedBox(width: 4),
              const Text('正在听...',
                  style: TextStyle(fontSize: 12, color: Colors.red)),
            ],
            if (!available && _svc.failReason.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text('（${_svc.failReason}，点击重试）',
                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ),
          ],
        ),
      ],
    );
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot();
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _ctrl,
      child: Container(
        width: 8,
        height: 8,
        decoration:
            const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
      ),
    );
  }
}
