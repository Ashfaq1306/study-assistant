import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/choice_controls.dart';
import '../../core/widgets/dreamy_background.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/page_shell.dart';
import '../study/application/study_providers.dart';

class ChatMessage {
  const ChatMessage({required this.fromStudent, required this.text});

  final bool fromStudent;
  final String text;
}

class TutorState {
  const TutorState({this.messages = const [], this.thinking = false, this.error, this.remainingToday});

  final List<ChatMessage> messages;
  final bool thinking;
  final ApiException? error;
  final int? remainingToday;

  TutorState copyWith({List<ChatMessage>? messages, bool? thinking, ApiException? error, int? remainingToday}) =>
      TutorState(
        messages: messages ?? this.messages,
        thinking: thinking ?? this.thinking,
        error: error,
        remainingToday: remainingToday ?? this.remainingToday,
      );
}

final tutorProvider = NotifierProvider<TutorController, TutorState>(TutorController.new);

/// The conversation with the AI study helper (kept while the app is open).
class TutorController extends Notifier<TutorState> {
  /// The server accepts the latest 20 messages; older ones are dropped from requests.
  static const _maxHistory = 20;

  @override
  TutorState build() => const TutorState();

  Future<void> ask(String question) async {
    final text = question.trim();
    if (text.isEmpty || state.thinking) return;
    final messages = [...state.messages, ChatMessage(fromStudent: true, text: text)];
    state = state.copyWith(messages: messages, thinking: true);

    var history = messages.length > _maxHistory ? messages.sublist(messages.length - _maxHistory) : messages;
    // The conversation sent must start with the student.
    while (history.isNotEmpty && !history.first.fromStudent) {
      history = history.sublist(1);
    }
    try {
      final reply = await ref.read(examApiProvider).askTutor([
        for (final m in history) (role: m.fromStudent ? 'user' : 'assistant', content: m.text),
      ]);
      state = state.copyWith(
        messages: [
          ...state.messages,
          ChatMessage(fromStudent: false, text: reply.reply),
        ],
        thinking: false,
        remainingToday: reply.remainingToday,
      );
    } on ApiException catch (e) {
      // Take the unanswered question back out, so it can be asked again.
      state = state.copyWith(messages: state.messages.sublist(0, state.messages.length - 1), thinking: false, error: e);
    }
  }

  void clear() => state = const TutorState();
}

class TutorScreen extends ConsumerStatefulWidget {
  const TutorScreen({super.key});

  @override
  ConsumerState<TutorScreen> createState() => _TutorScreenState();
}

class _TutorScreenState extends ConsumerState<TutorScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send([String? preset]) async {
    final text = preset ?? _input.text;
    if (text.trim().isEmpty) return;
    final previous = _input.text;
    _input.clear();
    await ref.read(tutorProvider.notifier).ask(text);
    // Put the student's words back if the question could not be answered.
    if (ref.read(tutorProvider).error != null && preset == null && mounted) _input.text = previous;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(tutorProvider);
    final session = ref.watch(activeSessionProvider).value;
    final topic = session?.topics;

    return Scaffold(
      body: DreamyBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Row(
                  children: [
                    const RoundBackButton(),
                    const SizedBox(width: 12),
                    const IconBadge(Icons.smart_toy_rounded, size: 44, color: AppColors.sky),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('AI study helper', style: Theme.of(context).textTheme.titleLarge),
                          Text(
                            session != null ? 'Helping with ${session.subject}' : 'Ask about anything you are learning',
                            style: Theme.of(context).textTheme.bodyMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    if (state.messages.isNotEmpty)
                      IconButton(
                        tooltip: 'New chat',
                        icon: const Icon(Icons.refresh_rounded, color: AppColors.inkSoft),
                        onPressed: ref.read(tutorProvider.notifier).clear,
                      ),
                  ],
                ),
              ),
              Expanded(
                child: state.messages.isEmpty
                    ? _Welcome(topic: topic, onPick: _send)
                    : ListView(
                        controller: _scroll,
                        reverse: true,
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        children: [
                          if (state.thinking) const _Bubble(fromStudent: false, text: '…', typing: true),
                          for (final m in state.messages.reversed) _Bubble(fromStudent: m.fromStudent, text: m.text),
                        ],
                      ),
              ),
              if (state.error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: MessageBanner.error(state.error!.message),
                ),
              if (state.remainingToday != null && state.remainingToday! <= 5)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '${state.remainingToday} questions left today',
                    style: const TextStyle(color: AppColors.inkSoft, fontWeight: FontWeight.w700),
                  ),
                ),
              _InputBar(controller: _input, enabled: !state.thinking, onSend: _send),
            ],
          ),
        ),
      ),
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome({required this.topic, required this.onPick});

  final String? topic;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final about = topic ?? 'what I am studying';
    final prompts = [
      'Explain $about simply',
      'Give me 3 practice questions on $about',
      'Make a short summary of $about I can revise',
      'What are common mistakes with $about?',
    ];
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Center(child: IconBadge(Icons.psychology_rounded, size: 88, color: AppColors.sky)),
        const SizedBox(height: 16),
        Text('Stuck? Ask me!', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 6),
        const Text(
          'I explain things step by step and give hints. I take a break while your exam is open.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 22),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment: WrapAlignment.center,
          children: [
            for (final p in prompts)
              ChoicePill(
                label: p,
                icon: Icons.auto_awesome_rounded,
                color: AppColors.sky,
                selected: false,
                onTap: () => onPick(p),
              ),
          ],
        ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.fromStudent, required this.text, this.typing = false});

  final bool fromStudent;
  final String text;
  final bool typing;

  @override
  Widget build(BuildContext context) {
    final bubble = Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      margin: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        color: fromStudent ? AppColors.violet : AppColors.card,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(20),
          topRight: const Radius.circular(20),
          bottomLeft: Radius.circular(fromStudent ? 20 : 6),
          bottomRight: Radius.circular(fromStudent ? 6 : 20),
        ),
        boxShadow: [
          BoxShadow(color: AppColors.violet.withValues(alpha: 0.12), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: typing
          ? const SizedBox(width: 36, height: 18, child: Center(child: LinearProgressIndicator(minHeight: 4)))
          : SelectableText(
              text,
              style: TextStyle(
                color: fromStudent ? Colors.white : AppColors.ink,
                fontWeight: FontWeight.w600,
                fontSize: 15.5,
                height: 1.4,
              ),
            ),
    );
    return Align(alignment: fromStudent ? Alignment.centerRight : Alignment.centerLeft, child: bubble);
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({required this.controller, required this.enabled, required this.onSend});

  final TextEditingController controller;
  final bool enabled;
  final ValueChanged<String?> onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              minLines: 1,
              maxLines: 4,
              maxLength: 2000,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(null),
              decoration: const InputDecoration(hintText: 'Ask a question…', counterText: ''),
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: enabled ? AppColors.violet : AppColors.line,
            shape: const CircleBorder(),
            child: IconButton(
              tooltip: 'Send',
              icon: const Icon(Icons.send_rounded, color: Colors.white),
              onPressed: enabled ? () => onSend(null) : null,
            ),
          ),
        ],
      ),
    );
  }
}
