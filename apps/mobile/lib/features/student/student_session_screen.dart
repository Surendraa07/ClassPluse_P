import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../core/realtime/session_socket.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/answer_option_card.dart';
import '../../widgets/common.dart';
import '../../widgets/image_widgets.dart';
import '../../widgets/inline_banner.dart';
import '../../widgets/live_badge.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/pulse_button.dart';
import '../../widgets/result_bar.dart';
import '../../widgets/skeleton_loader.dart';
import 'student_session_controller.dart';

/// The student's live session: waiting room → question, plus the confusion pulse (always
/// available from the bottom bar). Navigates to the ended screen when the session ends.
class StudentSessionScreen extends ConsumerStatefulWidget {
  const StudentSessionScreen({super.key});

  @override
  ConsumerState<StudentSessionScreen> createState() => _StudentSessionScreenState();
}

class _StudentSessionScreenState extends ConsumerState<StudentSessionScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(studentSessionProvider);
    final c = ref.read(studentSessionProvider.notifier);
    ref.listen(studentSessionProvider.select((v) => v.ended), (_, ended) {
      if (ended) context.go('/student/ended');
    });

    final live = s.live;
    final waiting = live == null || live.status == SessionStatus.waiting;
    final slide = s.slide;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.s16, AppSpace.s8, AppSpace.s16, AppSpace.s8),
              child: Row(
                children: [
                  Expanded(
                    child: Align(alignment: Alignment.centerLeft, child: LiveBadge(title: live?.presentationTitle)),
                  ),
                  const SizedBox(width: AppSpace.s8),
                  if (_tab == 1)
                    const Text('Pulse check', style: AppText.label)
                  else if (slide != null && live != null)
                    Text('Question ${(live.currentIndex ?? 0) + 1} of ${live.totalSlides}', style: AppText.label),
                ],
              ),
            ),
            if (s.isOffline && s.connection != ConnectionStatus.connecting)
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpace.s16, 0, AppSpace.s16, AppSpace.s8),
                child: InlineBanner(
                  key: const ValueKey('offline-banner'),
                  kind: BannerKind.offline,
                  title: "You're offline",
                  message: "Your answer is saved and will send when you reconnect.",
                  actionLabel: 'Retry now',
                  onAction: c.retryNow,
                ),
              ),
            Expanded(
              child: _tab == 1
                  ? _PulseTab(state: s, onSet: c.setPulse)
                  : live == null
                      ? const Padding(
                          padding: EdgeInsets.all(AppSpace.s16),
                          child: SkeletonLoader(rows: 3, label: 'Connecting to the session'),
                        )
                      : waiting || slide == null
                          ? _WaitingRoom(participants: s.participants)
                          : _QuestionView(state: s, controller: c),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.brandTint,
        destinations: [
          const NavigationDestination(
            key: ValueKey('tab-question'),
            icon: Icon(Icons.quiz_outlined),
            selectedIcon: Icon(Icons.quiz_rounded, color: AppColors.brand),
            label: 'Question',
          ),
          NavigationDestination(
            key: const ValueKey('tab-pulse'),
            icon: Icon(_pulseIcon(s.pulse)),
            selectedIcon: Icon(_pulseIcon(s.pulse), color: AppColors.brand),
            label: s.pulse == null ? 'How am I doing?' : (s.pulse == PulseState.following ? 'Following' : 'Lost'),
          ),
        ],
      ),
    );
  }

  static IconData _pulseIcon(PulseState? p) => switch (p) {
        PulseState.following => Icons.check_circle_outline_rounded,
        PulseState.lost => Icons.help_outline_rounded,
        null => Icons.favorite_outline_rounded,
      };
}

class _WaitingRoom extends StatelessWidget {
  const _WaitingRoom({required this.participants});
  final int participants;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpace.s24),
        child: Column(
          children: [
            ExcludeSemantics(
              child: Container(
                width: 160,
                height: 160,
                decoration: const BoxDecoration(color: Color(0xFFF1EFFE), shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Container(
                  width: 112,
                  height: 112,
                  decoration: const BoxDecoration(color: AppColors.brandTint, shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: const BoxDecoration(color: AppColors.brand, shape: BoxShape.circle),
                    child: const Icon(Icons.sensors_rounded, color: Colors.white, size: 32),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpace.s24),
            Semantics(header: true, child: const Text("You're in!", key: ValueKey('youre-in'), style: AppText.titleLarge)),
            const SizedBox(height: AppSpace.s8),
            const Text(
              'Waiting for your teacher to start the lecture…',
              style: AppText.bodySecondary,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpace.s16),
            Semantics(
              liveRegion: true,
              child: StatusPill(label: '$participants ${participants == 1 ? 'student' : 'students'} joined'),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuestionView extends StatelessWidget {
  const _QuestionView({required this.state, required this.controller});
  final StudentState state;
  final StudentSessionController controller;

  @override
  Widget build(BuildContext context) {
    final slide = state.slide!;
    final closed = state.answerStatus == AnswerStatus.closed;
    final sending = state.answerStatus == AnswerStatus.sending;
    final changed = state.selectedOptionId != null && state.selectedOptionId != state.submittedOptionId;
    final hasSubmitted = state.submittedOptionId != null;
    final results = state.visibleResults;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(AppSpace.s16, AppSpace.s4, AppSpace.s16, AppSpace.s16),
            children: [
              AppCard(
                padding: const EdgeInsets.all(AppSpace.s20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (slide.imageUrl != null) ...[SlideImage(slide.imageUrl!), const SizedBox(height: AppSpace.s16)],
                    Semantics(
                      header: true,
                      child: Text(slide.question, key: const ValueKey('student-question'), style: AppText.title.copyWith(fontSize: 24)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpace.s16),
              const SectionLabel('Choose one'),
              const SizedBox(height: AppSpace.s12),
              for (final (i, o) in slide.options.indexed) ...[
                AnswerOptionCard(
                  key: ValueKey('option-$i'),
                  label: o.label,
                  index: i,
                  total: slide.options.length,
                  selected: state.selectedOptionId == o.id,
                  onTap: closed || sending ? null : () => controller.select(o.id),
                ),
                const SizedBox(height: AppSpace.s12),
              ],
              if (state.error != null) ...[
                InlineBanner(title: closed ? 'Question closed' : "Couldn't send your answer", message: state.error),
                const SizedBox(height: AppSpace.s12),
              ],
              if (hasSubmitted && !changed) _AnswerStatusPill(status: state.answerStatus),
              if (results != null) ...[
                const SizedBox(height: AppSpace.s16),
                const SectionLabel('Class so far'),
                const SizedBox(height: AppSpace.s12),
                for (final (i, o) in slide.options.indexed) ...[
                  ResultBar(
                    label: o.label,
                    percent: results.percentFor(o.id),
                    color: AppColors.resultBars[i % AppColors.resultBars.length],
                    isMine: state.submittedOptionId == o.id,
                  ),
                  const SizedBox(height: AppSpace.s12),
                ],
                Text('${results.answered} of ${results.participants} students answered', style: AppText.caption),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.s16, AppSpace.s8, AppSpace.s16, AppSpace.s12),
          child: PrimaryButton(
            key: const ValueKey('submit-answer'),
            label: hasSubmitted ? 'Change answer' : 'Submit answer',
            loading: sending,
            loadingLabel: 'Sending…',
            // Disabled until an option is chosen, and while the choice equals what was sent.
            onPressed: closed || state.selectedOptionId == null || !changed && hasSubmitted ? null : controller.submit,
          ),
        ),
      ],
    );
  }
}

class _AnswerStatusPill extends StatelessWidget {
  const _AnswerStatusPill({required this.status});
  final AnswerStatus status;

  @override
  Widget build(BuildContext context) {
    final queued = status == AnswerStatus.queued;
    final (bg, fg, icon, text) = queued
        ? (const Color(0xFFFFF7ED), const Color(0xFF9A3412), Icons.schedule_rounded, 'Saved on this phone. Will send when you reconnect')
        : (AppColors.successTint, AppColors.success, Icons.check_rounded, 'Answer recorded. You can change it until your teacher moves on');
    return Semantics(
      liveRegion: true,
      child: Container(
        key: ValueKey(queued ? 'answer-queued' : 'answer-recorded'),
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.s16, vertical: AppSpace.s12),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadius.md)),
        child: Row(
          children: [
            Icon(icon, color: fg, size: 20),
            const SizedBox(width: AppSpace.s8),
            Expanded(child: Text(text, style: AppText.label.copyWith(color: fg))),
          ],
        ),
      ),
    );
  }
}

class _PulseTab extends StatelessWidget {
  const _PulseTab({required this.state, required this.onSet});
  final StudentState state;
  final ValueChanged<PulseState> onSet;

  @override
  Widget build(BuildContext context) {
    final p = state.pulse;
    return ListView(
      padding: const EdgeInsets.all(AppSpace.s16),
      children: [
        Semantics(header: true, child: const Text('How are you following along?', style: AppText.titleLarge)),
        const SizedBox(height: AppSpace.s16),
        PulseButton(
          key: const ValueKey('pulse-following'),
          kind: PulseKind.following,
          selected: p == PulseState.following,
          onTap: () => onSet(PulseState.following),
        ),
        const SizedBox(height: AppSpace.s16),
        PulseButton(
          key: const ValueKey('pulse-lost'),
          kind: PulseKind.lost,
          selected: p == PulseState.lost,
          onTap: () => onSet(PulseState.lost),
        ),
        const SizedBox(height: AppSpace.s16),
        if (p != null)
          Semantics(
            liveRegion: true,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.s16, vertical: AppSpace.s12),
              decoration: BoxDecoration(
                color: state.pulsePending ? const Color(0xFFFFF7ED) : AppColors.successTint,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    state.pulsePending ? Icons.schedule_rounded : Icons.check_rounded,
                    size: 20,
                    color: state.pulsePending ? const Color(0xFF9A3412) : AppColors.success,
                  ),
                  const SizedBox(width: AppSpace.s8),
                  Text(
                    state.pulsePending ? 'Will send when you reconnect' : 'Recorded just now',
                    style: AppText.label.copyWith(color: state.pulsePending ? const Color(0xFF9A3412) : AppColors.success),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: AppSpace.s12),
        const Text(
          'Anonymous: your teacher only sees class totals. Tap the other option anytime to change it.',
          style: AppText.caption,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
