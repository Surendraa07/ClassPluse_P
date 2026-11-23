import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/config.dart';
import '../../core/models.dart';
import '../../core/realtime/session_socket.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/common.dart';
import '../../widgets/image_widgets.dart';
import '../../widgets/inline_banner.dart';
import '../../widgets/live_badge.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/result_bar.dart';
import '../../widgets/secondary_button.dart';
import '../../widgets/skeleton_loader.dart';
import 'dialogs.dart';
import 'format.dart';
import 'live_session_controller.dart';

/// Waiting room (QR + code + joined count) → live dashboard → summary, driven by `session:state`.
class LiveSessionScreen extends ConsumerWidget {
  const LiveSessionScreen({super.key, required this.sessionId});
  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = lecturerLiveProvider(sessionId);
    final s = ref.watch(provider);

    // Session ended (by us or elsewhere) → summary.
    ref.listen(provider.select((v) => v.live?.status), (prev, next) {
      if (next == SessionStatus.ended) context.pushReplacement('/lecturer/sessions/$sessionId/summary');
    });

    final live = s.live;
    final Widget body;
    if (s.connection == ConnectionStatus.rejected) {
      body = _Rejected(code: s.rejectedCode, onBack: () => context.pop());
    } else if (live == null) {
      body = Column(
        children: [
          ScreenHeader(title: 'Connecting…', leadingIcon: Icons.close_rounded, leadingLabel: 'Close', onLeading: () => context.pop()),
          if (s.connection == ConnectionStatus.offline)
            Padding(
              padding: const EdgeInsets.all(AppSpace.s16),
              child: InlineBanner(
                kind: BannerKind.offline,
                title: "Can't reach the server",
                message: 'Check your connection. We keep trying automatically.',
                actionLabel: 'Retry now',
                onAction: () => ref.read(provider.notifier).reconnect(),
              ),
            ),
          const Padding(padding: EdgeInsets.all(AppSpace.s16), child: SkeletonLoader(rows: 3, header: true)),
        ],
      );
    } else if (live.status == SessionStatus.waiting) {
      body = _WaitingRoom(sessionId: sessionId, state: s);
    } else {
      body = _Dashboard(sessionId: sessionId, state: s);
    }

    return PopScope(
      canPop: true,
      child: Scaffold(body: SafeArea(child: body)),
    );
  }
}

class _OfflineBanner extends ConsumerWidget {
  const _OfflineBanner({required this.sessionId});
  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.s16, 0, AppSpace.s16, AppSpace.s12),
      child: InlineBanner(
        kind: BannerKind.offline,
        title: "You're offline",
        message: 'Reconnecting… Student answers are safe and will appear when you are back.',
        actionLabel: 'Retry',
        onAction: () => ref.read(lecturerLiveProvider(sessionId).notifier).reconnect(),
      ),
    );
  }
}

class _ErrorBanner extends ConsumerWidget {
  const _ErrorBanner({required this.sessionId, required this.message});
  final String sessionId;
  final String message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.s16, 0, AppSpace.s16, AppSpace.s12),
      child: InlineBanner(
        title: "That didn't work",
        message: message,
        actionLabel: 'Dismiss',
        onAction: () => ref.read(lecturerLiveProvider(sessionId).notifier).clearError(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Waiting room

class _WaitingRoom extends ConsumerWidget {
  const _WaitingRoom({required this.sessionId, required this.state});
  final String sessionId;
  final LecturerLiveState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = state.live!;
    final code = live.code ?? '';
    final joined = state.participants;
    final offline = state.connection != ConnectionStatus.connected;

    return Column(
      children: [
        ScreenHeader(
          title: live.presentationTitle ?? 'Live session',
          subtitle: 'Students can join now',
          leadingIcon: Icons.close_rounded,
          leadingLabel: 'Close waiting room',
          onLeading: () => context.pop(),
        ),
        if (offline) _OfflineBanner(sessionId: sessionId),
        if (state.error != null) _ErrorBanner(sessionId: sessionId, message: state.error!),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(AppSpace.s16),
            children: [
              AppCard(
                padding: const EdgeInsets.all(AppSpace.s24),
                child: Column(
                  children: [
                    const Text('SCAN TO JOIN', style: AppText.overline),
                    const SizedBox(height: AppSpace.s12),
                    Semantics(
                      label: 'QR code to join session ${code.split('').join(' ')}',
                      image: true,
                      excludeSemantics: true,
                      child: QrImageView(
                        key: const ValueKey('session-qr'),
                        data: '${AppConfig.deepLinkScheme}://join/$code',
                        size: 220,
                        backgroundColor: Colors.white,
                        eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: AppColors.textPrimary),
                        dataModuleStyle:
                            const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: AppColors.textPrimary),
                      ),
                    ),
                    const SizedBox(height: AppSpace.s16),
                    const Text('OR ENTER CODE', style: AppText.overline),
                    const SizedBox(height: AppSpace.s4),
                    Semantics(
                      label: 'Session code ${code.split('').join(' ')}',
                      excludeSemantics: true,
                      child: FittedBox(
                        child: Text(formatCode(code), key: const ValueKey('session-code'), style: AppText.code),
                      ),
                    ),
                    const SizedBox(height: AppSpace.s12),
                    Semantics(
                      liveRegion: true,
                      child: StatusPill(
                        key: const ValueKey('joined-count'),
                        label: '${plural(joined, 'student')} joined',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpace.s16),
              const Text(
                'Students open ClassPluse, tap "Join a session" and scan the QR code or type the code.',
                style: AppText.bodySecondary,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.s16, AppSpace.s8, AppSpace.s16, AppSpace.s16),
          child: PrimaryButton(
            key: const ValueKey('start-lecture'),
            label: 'Start lecture',
            loading: state.busy,
            loadingLabel: 'Starting…',
            onPressed: offline ? null : () => ref.read(lecturerLiveProvider(sessionId).notifier).start(),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Live dashboard

class _Dashboard extends ConsumerWidget {
  const _Dashboard({required this.sessionId, required this.state});
  final String sessionId;
  final LecturerLiveState state;

  Future<void> _end(BuildContext context, WidgetRef ref) async {
    final ok = await confirmDialog(
      context,
      title: 'End session?',
      message: 'Students will be disconnected and the code will stop working. You can review the results afterwards.',
      confirmLabel: 'End session',
      destructive: true,
    );
    if (ok) await ref.read(lecturerLiveProvider(sessionId).notifier).end();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = state.live!;
    final slide = live.currentSlide;
    final index = live.currentIndex ?? 0;
    final results = state.currentResults;
    final offline = state.connection != ConnectionStatus.connected;
    final controller = ref.read(lecturerLiveProvider(sessionId).notifier);

    return Column(
      children: [
        ScreenHeader(
          title: live.presentationTitle ?? 'Live session',
          subtitle: slide == null ? null : 'Slide ${index + 1} of ${live.totalSlides} · ${slide.type.label}',
          leadingIcon: Icons.close_rounded,
          leadingLabel: 'End session',
          onLeading: () => _end(context, ref),
          trailing: const LiveBadge(compact: true),
        ),
        if (offline) _OfflineBanner(sessionId: sessionId),
        if (state.error != null) _ErrorBanner(sessionId: sessionId, message: state.error!),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(AppSpace.s16, 0, AppSpace.s16, AppSpace.s16),
            children: [
              Semantics(
                liveRegion: true,
                child: Wrap(
                  spacing: AppSpace.s8,
                  runSpacing: AppSpace.s8,
                  children: [
                    StatusPill(label: '${state.participants} joined', tone: StatusPillTone.brand, showDot: false),
                    StatusPill(
                      key: const ValueKey('answered-count'),
                      label: '${results?.answered ?? 0} answered',
                      showDot: false,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpace.s12),
              if (slide != null) ...[
                AppCard(
                  padding: const EdgeInsets.all(AppSpace.s20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (slide.imageUrl != null) ...[SlideImage(slide.imageUrl!), const SizedBox(height: AppSpace.s16)],
                      Semantics(
                        header: true,
                        child: Text(slide.question, style: AppText.titleLarge.copyWith(fontSize: 26)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpace.s20),
                for (final (i, o) in slide.options.indexed) ...[
                  ResultBar(
                    key: ValueKey('result-${o.id}'),
                    label: o.label,
                    count: results?.countFor(o.id) ?? 0,
                    percent: results?.percentFor(o.id) ?? 0,
                    color: AppColors.resultBars[i % AppColors.resultBars.length],
                    isCorrect: slide.type == SlideType.quiz && o.isCorrect,
                    large: true,
                  ),
                  const SizedBox(height: AppSpace.s16),
                ],
              ],
              const SizedBox(height: AppSpace.s4),
              _PulsePanel(pulse: state.pulse, participants: state.participants),
              const SizedBox(height: AppSpace.s12),
              AppCard(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.s16, vertical: AppSpace.s4),
                child: SwitchListTile(
                  key: const ValueKey('toggle-results'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Show live results to students', style: AppText.body),
                  subtitle: Text(
                    live.showResultsToStudents ? 'Students see the class totals' : 'Only you see the results',
                    style: AppText.caption,
                  ),
                  value: live.showResultsToStudents,
                  onChanged: offline || state.busy ? null : controller.setShowResults,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.s16, AppSpace.s8, AppSpace.s16, AppSpace.s16),
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: SecondaryButton(
                  key: const ValueKey('end-session'),
                  label: 'End',
                  tone: SecondaryButtonTone.danger,
                  onPressed: offline ? null : () => _end(context, ref),
                ),
              ),
              const SizedBox(width: AppSpace.s12),
              Expanded(
                flex: 3,
                child: live.isLastSlide
                    ? PrimaryButton(
                        key: const ValueKey('finish-session'),
                        label: 'Finish',
                        icon: Icons.flag_rounded,
                        onPressed: offline ? null : () => _end(context, ref),
                      )
                    : PrimaryButton(
                        key: const ValueKey('next-slide'),
                        label: 'Next slide',
                        loading: state.busy,
                        onPressed: offline ? null : controller.next,
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Confusion pulse: % following vs % lost, with icons and numbers (never colour alone).
class _PulsePanel extends StatelessWidget {
  const _PulsePanel({required this.pulse, required this.participants});
  final PulseTotals pulse;
  final int participants;

  @override
  Widget build(BuildContext context) {
    final lostHigh = pulse.total > 0 && pulse.lostPct >= 30;
    return AppCard(
      key: const ValueKey('pulse-panel'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(
            'Confusion pulse',
            trailing: Text('${pulse.total} of $participants responded', style: AppText.caption),
          ),
          const SizedBox(height: AppSpace.s12),
          if (pulse.total == 0)
            const Text('No pulse yet. Students can tap "I\'m following" or "I\'m lost" at any time.', style: AppText.bodySecondary)
          else ...[
            Row(
              children: [
                Expanded(
                  child: _PulseStat(
                    icon: Icons.check_circle_rounded,
                    color: AppColors.success,
                    label: 'Following',
                    pct: pulse.followingPct,
                    count: pulse.following,
                  ),
                ),
                const SizedBox(width: AppSpace.s12),
                Expanded(
                  child: _PulseStat(
                    icon: Icons.cancel_rounded,
                    color: AppColors.danger,
                    label: 'Lost',
                    pct: pulse.lostPct,
                    count: pulse.lost,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.s12),
            ExcludeSemantics(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.full),
                child: SizedBox(
                  height: 14,
                  child: Row(
                    children: [
                      if (pulse.following > 0) Expanded(flex: pulse.following, child: Container(color: AppColors.successFill)),
                      if (pulse.lost > 0) Expanded(flex: pulse.lost, child: Container(color: AppColors.danger)),
                    ],
                  ),
                ),
              ),
            ),
            if (lostHigh) ...[
              const SizedBox(height: AppSpace.s12),
              Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: AppColors.danger, size: 20),
                  const SizedBox(width: AppSpace.s8),
                  Expanded(
                    child: Text('Many students are lost. Consider slowing down or recapping.',
                        style: AppText.label.copyWith(color: AppColors.danger)),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _PulseStat extends StatelessWidget {
  const _PulseStat({required this.icon, required this.color, required this.label, required this.pct, required this.count});
  final IconData icon;
  final Color color;
  final String label;
  final double pct;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label: ${pct.round()} percent, $count ${count == 1 ? 'student' : 'students'}',
      excludeSemantics: true,
      child: Row(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: AppSpace.s8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${pct.round()}%', style: AppText.title.copyWith(color: color)),
              Text('$label · $count', style: AppText.label),
            ],
          ),
        ],
      ),
    );
  }
}

class _Rejected extends StatelessWidget {
  const _Rejected({required this.code, required this.onBack});
  final String? code;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpace.s16),
      child: Column(
        children: [
          ScreenHeader(title: 'Session unavailable', onLeading: onBack),
          InlineBanner(
            title: code == 'NOT_FOUND' ? 'Session not found' : "Can't open this session",
            message: code == 'UNAUTHORIZED' ? 'Your login expired. Please log in again.' : 'It may have ended or been deleted.',
            actionLabel: 'Go back',
            onAction: onBack,
          ),
        ],
      ),
    );
  }
}
