import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/models.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/uploads/image_uploader.dart';
import '../../widgets/common.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/image_widgets.dart';
import '../../widgets/inline_banner.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/skeleton_loader.dart';
import '../auth/auth_controller.dart';
import 'dialogs.dart';
import 'format.dart';
import 'presentations_controller.dart';

/// Lecturer home: greeting, Quick Start, and the presentation list (loading / empty / error).
class LecturerHomeScreen extends ConsumerWidget {
  const LecturerHomeScreen({super.key});

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final title = await showTextInputDialog(
      context,
      title: 'New presentation',
      label: 'Title',
      hint: 'e.g. POP Lecture 4: Loops',
      confirmLabel: 'Create',
    );
    if (title == null || !context.mounted) return;
    try {
      final p = await ref.read(presentationsProvider.notifier).create(title);
      if (context.mounted) context.push('/lecturer/presentations/${p.id}');
    } on ApiException catch (e) {
      if (context.mounted) showError(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lecturer = ref.watch(authControllerProvider).lecturer;
    final presentations = ref.watch(presentationsProvider);

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.read(presentationsProvider.notifier).refresh(),
          child: ListView(
            padding: const EdgeInsets.all(AppSpace.s16),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          header: true,
                          child: Text('${greeting()}, ${lecturer?.firstName ?? ''}', style: AppText.titleLarge),
                        ),
                        const SizedBox(height: AppSpace.s4),
                        const Text('Ready to engage your class?', style: AppText.bodySecondary),
                      ],
                    ),
                  ),
                  const _AccountMenu(),
                ],
              ),
              const SizedBox(height: AppSpace.s20),
              _QuickStart(onTap: () => _create(context, ref)),
              const SizedBox(height: AppSpace.s24),
              ...switch (presentations) {
                AsyncData(:final value) => _list(context, ref, value),
                AsyncError(:final error) => [
                    InlineBanner(
                      kind: error is ApiException && error.isNetwork ? BannerKind.offline : BannerKind.error,
                      title: "Couldn't load your presentations",
                      message: error is ApiException ? error.message : 'Check your connection and try again.',
                      actionLabel: 'Retry',
                      onAction: () => ref.invalidate(presentationsProvider),
                    ),
                    const SizedBox(height: AppSpace.s16),
                    PrimaryButton(label: 'Try again', onPressed: () => ref.invalidate(presentationsProvider)),
                  ],
                _ => [
                    const SectionLabel('Your presentations'),
                    const SizedBox(height: AppSpace.s12),
                    const SkeletonLoader(rows: 3, label: 'Loading presentations'),
                  ],
              },
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _list(BuildContext context, WidgetRef ref, List<PresentationSummary> items) {
    if (items.isEmpty) {
      return [
        EmptyState(
          icon: Icons.slideshow_outlined,
          title: 'No presentations yet',
          message: 'Create your first interactive lesson and bring your classroom to life.',
          actionLabel: 'Create presentation',
          onAction: () => _create(context, ref),
        ),
      ];
    }
    return [
      SectionLabel('Your presentations (${items.length})'),
      const SizedBox(height: AppSpace.s12),
      for (final p in items) ...[
        ListRowCard(
          key: ValueKey('presentation-${p.id}'),
          icon: Icons.slideshow_outlined,
          title: p.title,
          subtitle: '${plural(p.slideCount, 'slide')} · Edited ${relativeTime(p.updatedAt)}',
          onTap: () => context.push('/lecturer/presentations/${p.id}'),
        ),
        const SizedBox(height: AppSpace.s12),
      ],
    ];
  }
}

class _QuickStart extends StatelessWidget {
  const _QuickStart({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Quick start: create a new presentation',
      excludeSemantics: true,
      child: Material(
        color: AppColors.brand,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: InkWell(
          key: const ValueKey('quick-start'),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.s20),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: const Icon(Icons.bolt_rounded, color: Colors.white),
                ),
                const SizedBox(width: AppSpace.s16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Quick Start', style: AppText.titleSmall.copyWith(color: Colors.white)),
                      Text('Create a new presentation', style: AppText.body.copyWith(color: Colors.white)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: Colors.white),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Avatar button with the account menu: change/remove photo, log out.
class _AccountMenu extends ConsumerStatefulWidget {
  const _AccountMenu();

  @override
  ConsumerState<_AccountMenu> createState() => _AccountMenuState();
}

class _AccountMenuState extends ConsumerState<_AccountMenu> {
  bool _busy = false;

  Future<void> _changePhoto() async {
    final hasPhoto = ref.read(authControllerProvider).lecturer?.avatarUrl != null;
    final action = await showImageSourceSheet(context, canRemove: hasPhoto, removeLabel: 'Remove photo');
    if (action == null || !mounted) return;
    final auth = ref.read(authControllerProvider.notifier);
    try {
      if (action == ImageAction.remove) {
        setState(() => _busy = true);
        await auth.updateAvatar(null);
        return;
      }
      final file = await pickImage(sourceFor(action), maxSide: 512);
      if (file == null || !mounted) return;
      setState(() => _busy = true);
      final url = await ref.read(imageUploaderProvider).upload(
            UploadKind.avatar,
            bytes: await file.readAsBytes(),
            filename: file.name,
          );
      await auth.updateAvatar(url);
    } on ApiException catch (e) {
      if (mounted) showError(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lecturer = ref.watch(authControllerProvider).lecturer;
    return PopupMenuButton<String>(
      key: const ValueKey('account-menu'),
      tooltip: 'Account',
      enabled: !_busy,
      padding: EdgeInsets.zero,
      onSelected: (v) async {
        if (v == 'photo') {
          await _changePhoto();
        } else if (v == 'logout') {
          await ref.read(authControllerProvider.notifier).logout();
          if (context.mounted) context.go('/');
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(enabled: false, child: Text(lecturer?.email ?? '', style: AppText.caption)),
        PopupMenuItem(value: 'photo', child: Text(lecturer?.avatarUrl == null ? 'Add profile photo' : 'Change profile photo')),
        const PopupMenuItem(value: 'logout', child: Text('Log out')),
      ],
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: LecturerAvatar(name: lecturer?.name ?? '', url: lecturer?.avatarUrl, size: 40, busy: _busy),
      ),
    );
  }
}
