import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import 'lecturer_repository.dart';

/// The lecturer's presentation list (home screen).
final presentationsProvider = AsyncNotifierProvider<PresentationsController, List<PresentationSummary>>(
  PresentationsController.new,
);

class PresentationsController extends AsyncNotifier<List<PresentationSummary>> {
  @override
  Future<List<PresentationSummary>> build() => ref.read(lecturerRepositoryProvider).listPresentations();

  Future<void> refresh() async {
    state = await AsyncValue.guard(() => ref.read(lecturerRepositoryProvider).listPresentations());
  }

  Future<Presentation> create(String title) async {
    final p = await ref.read(lecturerRepositoryProvider).createPresentation(title);
    await refresh();
    return p;
  }

  Future<void> delete(String id) async {
    await ref.read(lecturerRepositoryProvider).deletePresentation(id);
    await refresh();
  }
}

/// One presentation with its slides (builder screen).
final presentationProvider = AsyncNotifierProvider.family<PresentationController, Presentation, String>(
  PresentationController.new,
);

class PresentationController extends AsyncNotifier<Presentation> {
  PresentationController(this.id);
  final String id;

  LecturerRepository get _repo => ref.read(lecturerRepositoryProvider);

  @override
  Future<Presentation> build() => _repo.getPresentation(id);

  Future<void> reload() async {
    state = await AsyncValue.guard(() => _repo.getPresentation(id));
  }

  Future<void> rename(String title) async {
    final p = await _repo.renamePresentation(id, title);
    state = AsyncData(p);
    ref.invalidate(presentationsProvider);
  }

  Future<void> deleteSlide(String slideId) async {
    await _repo.deleteSlide(slideId);
    await reload();
    ref.invalidate(presentationsProvider);
  }

  /// Optimistic reorder (newIndex = final position); rolls back if the server rejects it.
  Future<void> reorder(int oldIndex, int newIndex) async {
    final current = state.value;
    if (current == null) return;
    final slides = [...current.slides];
    final moved = slides.removeAt(oldIndex);
    slides.insert(newIndex.clamp(0, slides.length), moved);
    state = AsyncData(current.copyWith(slides: slides));
    try {
      final saved = await _repo.reorderSlides(id, [for (final s in slides) s.id]);
      state = AsyncData(current.copyWith(slides: saved));
    } catch (_) {
      state = AsyncData(current);
      rethrow;
    }
  }

  void onSlideSaved() {
    reload();
    ref.invalidate(presentationsProvider);
  }
}
