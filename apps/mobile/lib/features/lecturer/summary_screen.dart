import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/models.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/common.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/inline_banner.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/result_bar.dart';
import '../../widgets/secondary_button.dart';
import '../../widgets/skeleton_loader.dart';
import 'format.dart';
import 'lecturer_repository.dart';

final summaryProvider = FutureProvider.autoDispose.family<SessionSummary, String>(
  (ref, sessionId) => ref.read(lecturerRepositoryProvider).summary(sessionId),
);

/// After a session: participants, responses, pulse, and per-question results.
class SummaryScreen extends ConsumerWidget {
  const SummaryScreen({super.key, required this.sessionId});
  final String sessionId;

  void _back(BuildContext context) => context.canPop() ? context.pop() : context.go('/lecturer');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(summaryProvider(sessionId));
    final s = async.value;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(
              title: s?.presentationTitle ?? 'Session results',
              subtitle: switch (async) {
                AsyncData(:final value) =>
                  '${value.status == SessionStatus.ended ? 'Ended ${relativeTime(value.endedAt)}' : 'In progress'} · ${value.participants} joined',
                AsyncError() => null,
                _ => 'Loading results…',
              },
              onLeading: () => _back(context),
            ),
            Expanded(
              child: switch (async) {
                AsyncData(:final value) => _content(context, value),
                AsyncError(:final error) => ListView(
                    padding: const EdgeInsets.all(AppSpace.s16),
                    children: [
                      InlineBanner(
                        kind: error is ApiException && error.isNetwork ? BannerKind.offline : BannerKind.error,
                        title: "Couldn't load the results",
                        message: error is ApiException ? error.message : null,
                        actionLabel: 'Retry',
                        onAction: () => ref.invalidate(summaryProvider(sessionId)),
                      ),
                    ],
                  ),
                _ => const Padding(
                    padding: EdgeInsets.all(AppSpace.s16),
                    child: SkeletonLoader(rows: 3, header: true, label: 'Loading results'),
                  ),
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(BuildContext context, SessionSummary s) {
    if (s.totalResponses == 0 && s.pulse.total == 0) {
      return ListView(
        padding: const EdgeInsets.all(AppSpace.s16),
        children: [
          EmptyState(
            icon: Icons.insert_chart_outlined_rounded,
            title: 'No responses yet',
            message: 'Nobody answered during this session. Run it again and share the QR code early.',
            actionLabel: 'Back to presentations',
            onAction: () => context.go('/lecturer'),
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.all(AppSpace.s16),
      children: [
        Row(
          children: [
            Expanded(
              child: StatCard(
                icon: Icons.person_outline_rounded,
                value: '${s.participants}',
                label: 'Participants',
                iconColor: const Color(0xFFC2410C),
                iconBg: const Color(0xFFFFEDD5),
              ),
            ),
            const SizedBox(width: AppSpace.s12),
            Expanded(
              child: StatCard(
                icon: Icons.sensors_rounded,
                value: '${s.totalResponses}',
                label: 'Responses',
                iconColor: AppColors.success,
                iconBg: AppColors.successTint,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.s12),
        AppCard(
          child: Row(
            children: [
              const Icon(Icons.favorite_outline_rounded, color: AppColors.brand),
              const SizedBox(width: AppSpace.s12),
              Expanded(
                child: Text(
                  s.pulse.total == 0
                      ? 'No confusion pulse was sent'
                      : 'Final pulse: ${s.pulse.followingPct.round()}% following, ${s.pulse.lostPct.round()}% lost '
                          '(${s.pulse.total} students)',
                  style: AppText.body,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.s20),
        const SectionLabel('Questions'),
        const SizedBox(height: AppSpace.s12),
        for (final (i, q) in s.slides.indexed) ...[
          ListRowCard(
            key: ValueKey('summary-q-$i'),
            icon: q.type == SlideType.quiz ? Icons.emoji_events_outlined : Icons.bar_chart_rounded,
            title: q.question,
            subtitle: _meta(q),
            onTap: () => context.push('/lecturer/sessions/$sessionId/summary/$i'),
          ),
          const SizedBox(height: AppSpace.s12),
        ],
      ],
    );
  }

  static String _meta(SummarySlide q) {
    final base = plural(q.responses, 'response');
    if (q.responses == 0) return base;
    if (q.type == SlideType.quiz) return '$base · ${q.percentCorrect?.round() ?? 0}% correct';
    final top = q.topOption!;
    return '$base · ${top.percent.round()}% said ${top.label}';
  }
}

/// Full results for one question with Previous / Next.
class QuestionDetailScreen extends ConsumerWidget {
  const QuestionDetailScreen({super.key, required this.sessionId, required this.index});
  final String sessionId;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(summaryProvider(sessionId));
    return Scaffold(
      body: SafeArea(
        child: switch (async) {
          AsyncData(:final value) => _detail(context, value),
          AsyncError() => Padding(
              padding: const EdgeInsets.all(AppSpace.s16),
              child: InlineBanner(
                title: "Couldn't load the results",
                actionLabel: 'Retry',
                onAction: () => ref.invalidate(summaryProvider(sessionId)),
              ),
            ),
          _ => const Padding(padding: EdgeInsets.all(AppSpace.s16), child: SkeletonLoader(rows: 3)),
        },
      ),
    );
  }

  Widget _detail(BuildContext context, SessionSummary s) {
    if (index < 0 || index >= s.slides.length) {
      return const Center(child: Text('Question not found', style: AppText.body));
    }
    final q = s.slides[index];
    void go(int i) => context.pushReplacement('/lecturer/sessions/$sessionId/summary/$i');
    return Column(
      children: [
        ScreenHeader(
          title: 'Question ${index + 1} of ${s.slides.length}',
          subtitle: '${q.type.label} · ${plural(q.responses, 'response')}',
          onLeading: () => context.pop(),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(AppSpace.s16),
            children: [
              AppCard(
                padding: const EdgeInsets.all(AppSpace.s20),
                child: Semantics(header: true, child: Text(q.question, style: AppText.titleLarge.copyWith(fontSize: 24))),
              ),
              const SizedBox(height: AppSpace.s20),
              for (final (i, o) in q.options.indexed) ...[
                ResultBar(
                  label: o.label,
                  count: o.count,
                  percent: o.percent,
                  color: AppColors.resultBars[i % AppColors.resultBars.length],
                  isCorrect: q.type == SlideType.quiz && o.isCorrect,
                ),
                const SizedBox(height: AppSpace.s16),
              ],
              AppCard(
                child: Row(
                  children: [
                    const Expanded(child: Text('Participation', style: AppText.body)),
                    Text('${q.responses} of ${s.participants} students',
                        style: AppText.bodyStrong.copyWith(color: AppColors.brand)),
                  ],
                ),
              ),
              if (q.percentCorrect != null) ...[
                const SizedBox(height: AppSpace.s12),
                AppCard(
                  child: Row(
                    children: [
                      const Expanded(child: Text('Answered correctly', style: AppText.body)),
                      Text('${q.percentCorrect!.round()}%', style: AppText.bodyStrong.copyWith(color: AppColors.success)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.s16, AppSpace.s8, AppSpace.s16, AppSpace.s16),
          child: Row(
            children: [
              Expanded(child: SecondaryButton(label: 'Previous', onPressed: index > 0 ? () => go(index - 1) : null)),
              const SizedBox(width: AppSpace.s12),
              Expanded(
                child: PrimaryButton(
                  label: 'Next question',
                  onPressed: index < s.slides.length - 1 ? () => go(index + 1) : null,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
