import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
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
import '../../widgets/skeleton_loader.dart';
import 'dialogs.dart';
import 'format.dart';
import 'lecturer_repository.dart';
import 'presentations_controller.dart';

/// Ordered slide list for one presentation: add, edit, reorder (drag handle), delete, present.
class BuilderScreen extends ConsumerStatefulWidget {
  const BuilderScreen({super.key, required this.presentationId});
  final String presentationId;

  @override
  ConsumerState<BuilderScreen> createState() => _BuilderScreenState();
}

class _BuilderScreenState extends ConsumerState<BuilderScreen> {
  bool _starting = false;
  String? _actionError;

  String get _id => widget.presentationId;

  Future<void> _addSlide() async {
    final type = await showModalBottomSheet<SlideType>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      builder: (_) => const _AddSlideSheet(),
    );
    if (type == null || !mounted) return;
    final saved = await context.push<bool>('/lecturer/presentations/$_id/slides/new?type=${type.api}');
    if (saved == true) ref.read(presentationProvider(_id).notifier).onSlideSaved();
  }

  Future<void> _editSlide(Slide s) async {
    final saved = await context.push<bool>('/lecturer/presentations/$_id/slides/${s.id}');
    if (saved == true) ref.read(presentationProvider(_id).notifier).onSlideSaved();
  }

  Future<void> _deleteSlide(Slide s) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete slide?',
      message: '"${s.question}" will be removed from this presentation.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok) return;
    await _guard(() => ref.read(presentationProvider(_id).notifier).deleteSlide(s.id));
  }

  Future<void> _rename(Presentation p) async {
    final title = await showTextInputDialog(context, title: 'Rename presentation', label: 'Title', initial: p.title);
    if (title == null) return;
    await _guard(() => ref.read(presentationProvider(_id).notifier).rename(title));
  }

  Future<void> _deletePresentation(Presentation p) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete presentation?',
      message: '"${p.title}", its slides and past session results will be deleted. This cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok) return;
    final done = await _guard(() => ref.read(presentationsProvider.notifier).delete(_id));
    if (done && mounted) context.pop();
  }

  Future<void> _present() async {
    setState(() {
      _starting = true;
      _actionError = null;
    });
    try {
      final s = await ref.read(lecturerRepositoryProvider).startSession(_id);
      if (mounted) context.push('/lecturer/sessions/${s.sessionId}');
    } on ApiException catch (e) {
      if (mounted) setState(() => _actionError = e.message);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<bool> _guard(Future<void> Function() action) async {
    setState(() => _actionError = null);
    try {
      await action();
      return true;
    } on ApiException catch (e) {
      if (mounted) setState(() => _actionError = e.message);
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(presentationProvider(_id));
    final p = async.value;

    return Scaffold(
      floatingActionButton: p == null
          ? null
          : FloatingActionButton(
              key: const ValueKey('add-slide'),
              tooltip: 'Add slide',
              onPressed: _addSlide,
              backgroundColor: AppColors.brand,
              foregroundColor: Colors.white,
              child: const Icon(Icons.add_rounded),
            ),
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(
              title: p?.title ?? 'Presentation',
              subtitle: p == null ? null : '${plural(p.slides.length, 'slide')} · Draft',
              onLeading: () => context.pop(),
              trailing: p == null
                  ? null
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        PrimaryButton(
                          key: const ValueKey('present'),
                          label: 'Present',
                          expand: false,
                          loading: _starting,
                          loadingLabel: 'Starting…',
                          onPressed: p.slides.isEmpty ? null : _present,
                        ),
                        PopupMenuButton<String>(
                          tooltip: 'More options',
                          onSelected: (v) => v == 'rename' ? _rename(p) : _deletePresentation(p),
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'rename', child: Text('Rename')),
                            PopupMenuItem(value: 'delete', child: Text('Delete presentation')),
                          ],
                        ),
                      ],
                    ),
            ),
            if (_actionError != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpace.s16, 0, AppSpace.s16, AppSpace.s12),
                child: InlineBanner(
                  title: "Couldn't complete that",
                  message: _actionError,
                  actionLabel: 'Dismiss',
                  onAction: () => setState(() => _actionError = null),
                ),
              ),
            Expanded(
              child: switch (async) {
                AsyncData(:final value) => _slides(value),
                AsyncError(:final error) => ListView(
                    padding: const EdgeInsets.all(AppSpace.s16),
                    children: [
                      InlineBanner(
                        title: "Couldn't load this presentation",
                        message: error is ApiException ? error.message : null,
                        actionLabel: 'Retry',
                        onAction: () => ref.invalidate(presentationProvider(_id)),
                      ),
                    ],
                  ),
                _ => const Padding(
                    padding: EdgeInsets.all(AppSpace.s16),
                    child: SkeletonLoader(rows: 4, label: 'Loading slides'),
                  ),
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _slides(Presentation p) {
    if (p.slides.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(AppSpace.s16),
        children: [
          EmptyState(
            icon: Icons.slideshow_outlined,
            title: 'No slides yet',
            message: 'Add your first poll or quiz to start building this presentation.',
            actionLabel: 'Add slide',
            onAction: _addSlide,
          ),
        ],
      );
    }
    return RefreshIndicator(
      onRefresh: () => ref.read(presentationProvider(_id).notifier).reload(),
      child: ReorderableListView.builder(
        padding: const EdgeInsets.fromLTRB(AppSpace.s16, 0, AppSpace.s16, 96),
        buildDefaultDragHandles: false,
        header: const Padding(padding: EdgeInsets.only(bottom: AppSpace.s12), child: SectionLabel('Slides')),
        itemCount: p.slides.length,
        onReorderItem: (a, b) => _guard(() => ref.read(presentationProvider(_id).notifier).reorder(a, b)),
        itemBuilder: (context, i) {
          final s = p.slides[i];
          return Padding(
            key: ValueKey('slide-${s.id}'),
            padding: const EdgeInsets.only(bottom: AppSpace.s12),
            child: _SlideRow(
              slide: s,
              index: i,
              total: p.slides.length,
              onTap: () => _editSlide(s),
              onDelete: () => _deleteSlide(s),
              onMove: (to) => _guard(() => ref.read(presentationProvider(_id).notifier).reorder(i, to)),
            ),
          );
        },
      ),
    );
  }
}

class _SlideRow extends StatelessWidget {
  const _SlideRow({
    required this.slide,
    required this.index,
    required this.total,
    required this.onTap,
    required this.onDelete,
    required this.onMove,
  });

  final Slide slide;
  final int index;
  final int total;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  /// Accessible alternative to dragging: target index in ReorderableListView terms.
  final ValueChanged<int> onMove;

  @override
  Widget build(BuildContext context) {
    final quiz = slide.type == SlideType.quiz;
    return Semantics(
      customSemanticsActions: {
        if (index > 0) const CustomSemanticsAction(label: 'Move up'): () => onMove(index - 1),
        if (index < total - 1) const CustomSemanticsAction(label: 'Move down'): () => onMove(index + 1),
      },
      child: AppCard(
        onTap: onTap,
        padding: const EdgeInsets.fromLTRB(4, AppSpace.s8, 0, AppSpace.s8),
        child: Row(
          children: [
            ReorderableDragStartListener(
              index: index,
              child: const Tooltip(
                message: 'Drag to reorder',
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(Icons.drag_indicator_rounded, color: AppColors.textSecondary),
                ),
              ),
            ),
            ExcludeSemantics(
              child: Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: quiz ? const Color(0xFFFFEDD5) : AppColors.brandTint,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(
                  quiz ? Icons.emoji_events_outlined : Icons.bar_chart_rounded,
                  color: quiz ? const Color(0xFFC2410C) : AppColors.brand,
                ),
              ),
            ),
            const SizedBox(width: AppSpace.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${index + 1}. ${slide.question}', style: AppText.bodyStrong, maxLines: 2, overflow: TextOverflow.ellipsis),
                  Text('${slide.type.label} · ${plural(slide.options.length, 'option')}${slide.imageUrl != null ? ' · image' : ''}', style: AppText.caption),
                ],
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Slide options',
              onSelected: (v) => switch (v) {
                'edit' => onTap(),
                'up' => onMove(index - 1),
                'down' => onMove(index + 1),
                _ => onDelete(),
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit')),
                if (index > 0) const PopupMenuItem(value: 'up', child: Text('Move up')),
                if (index < total - 1) const PopupMenuItem(value: 'down', child: Text('Move down')),
                const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: AppColors.danger))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AddSlideSheet extends StatelessWidget {
  const _AddSlideSheet();

  @override
  Widget build(BuildContext context) {
    Widget tile(SlideType t, IconData icon, Color fg, Color bg, String desc) => Expanded(
          child: AppCard(
            key: ValueKey('add-slide-${t.api}'),
            onTap: () => Navigator.of(context).pop(t),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadius.sm)),
                  child: Icon(icon, color: fg),
                ),
                const SizedBox(height: AppSpace.s12),
                Text(t.label, style: AppText.bodyStrong),
                Text(desc, style: AppText.caption),
              ],
            ),
          ),
        );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.s16, 0, AppSpace.s16, AppSpace.s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(header: true, child: const Text('Add a slide', style: AppText.title)),
            const SizedBox(height: AppSpace.s4),
            const Text('Pick a type. You can change it later.', style: AppText.bodySecondary),
            const SizedBox(height: AppSpace.s16),
            Row(
              children: [
                tile(SlideType.poll, Icons.bar_chart_rounded, AppColors.brand, AppColors.brandTint, 'Opinions, no right answer'),
                const SizedBox(width: AppSpace.s12),
                tile(SlideType.quiz, Icons.emoji_events_outlined, const Color(0xFFC2410C), const Color(0xFFFFEDD5),
                    'One correct answer'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
