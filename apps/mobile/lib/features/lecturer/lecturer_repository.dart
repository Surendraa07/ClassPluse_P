import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/models.dart';
import '../../core/providers.dart';

final lecturerRepositoryProvider = Provider<LecturerRepository>((ref) => LecturerRepository(ref.watch(apiClientProvider)));

/// Draft of a slide sent to the server; options may carry an id to keep it.
class SlideDraft {
  SlideDraft({required this.type, required this.question, required this.options, this.imageUrl});

  final SlideType type;
  final String question;
  final String? imageUrl;
  final List<({String? id, String label, bool isCorrect})> options;

  Map<String, dynamic> toJson() => {
        'type': type.api,
        'question': question.trim(),
        'imageUrl': imageUrl,
        'options': [
          for (final o in options)
            {
              if (o.id != null) 'id': o.id,
              'label': o.label.trim(),
              'isCorrect': type == SlideType.quiz && o.isCorrect,
            },
        ],
      };
}

class LecturerRepository {
  LecturerRepository(this._api);
  final ApiClient _api;

  Future<List<PresentationSummary>> listPresentations() async {
    final list = await _api.get<List<dynamic>>('/presentations');
    return [for (final p in list) PresentationSummary.fromJson(p as Map<String, dynamic>)];
  }

  Future<Presentation> getPresentation(String id) async =>
      Presentation.fromJson(await _api.get<Map<String, dynamic>>('/presentations/$id'));

  Future<Presentation> createPresentation(String title) async =>
      Presentation.fromJson(await _api.post<Map<String, dynamic>>('/presentations', {'title': title.trim()}));

  Future<Presentation> renamePresentation(String id, String title) async =>
      Presentation.fromJson(await _api.patch<Map<String, dynamic>>('/presentations/$id', {'title': title.trim()}));

  Future<void> deletePresentation(String id) => _api.delete('/presentations/$id');

  Future<Slide> createSlide(String presentationId, SlideDraft draft) async =>
      Slide.fromJson(await _api.post<Map<String, dynamic>>('/presentations/$presentationId/slides', draft.toJson()));

  Future<Slide> updateSlide(String slideId, SlideDraft draft) async =>
      Slide.fromJson(await _api.patch<Map<String, dynamic>>('/slides/$slideId', draft.toJson()));

  Future<void> deleteSlide(String slideId) => _api.delete('/slides/$slideId');

  Future<List<Slide>> reorderSlides(String presentationId, List<String> slideIds) async {
    final res = await _api.patch<Map<String, dynamic>>('/presentations/$presentationId/slides/reorder', {'slideIds': slideIds});
    return [for (final s in res['slides'] as List) Slide.fromJson(s as Map<String, dynamic>)];
  }

  /// Starts (or resumes) a live session.
  Future<({String sessionId, String code})> startSession(String presentationId) async {
    final res = await _api.post<Map<String, dynamic>>('/sessions', {'presentationId': presentationId});
    return (sessionId: res['sessionId'] as String, code: res['code'] as String);
  }

  Future<SessionSummary> summary(String sessionId) async =>
      SessionSummary.fromJson(await _api.get<Map<String, dynamic>>('/sessions/$sessionId/summary'));
}
