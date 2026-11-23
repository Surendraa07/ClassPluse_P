/// Plain data classes for API and socket payloads.
library;

enum SlideType {
  poll('POLL', 'Poll'),
  quiz('QUIZ', 'Quiz');

  const SlideType(this.api, this.label);
  final String api;
  final String label;

  static SlideType parse(Object? v) => v == 'QUIZ' ? SlideType.quiz : SlideType.poll;
}

enum SessionStatus {
  waiting,
  live,
  ended;

  static SessionStatus parse(Object? v) => switch (v) {
        'LIVE' => SessionStatus.live,
        'ENDED' => SessionStatus.ended,
        _ => SessionStatus.waiting,
      };
}

enum PulseState {
  following('FOLLOWING'),
  lost('LOST');

  const PulseState(this.api);
  final String api;

  static PulseState? parse(Object? v) => switch (v) {
        'FOLLOWING' => PulseState.following,
        'LOST' => PulseState.lost,
        _ => null,
      };
}

DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;

class PresentationSummary {
  const PresentationSummary({required this.id, required this.title, required this.slideCount, this.updatedAt});

  final String id;
  final String title;
  final int slideCount;
  final DateTime? updatedAt;

  factory PresentationSummary.fromJson(Map<String, dynamic> j) => PresentationSummary(
        id: j['id'] as String,
        title: j['title'] as String,
        slideCount: (j['slideCount'] as num?)?.toInt() ?? 0,
        updatedAt: _date(j['updatedAt']),
      );
}

class SlideOption {
  const SlideOption({required this.id, required this.label, this.isCorrect = false});

  final String id;
  final String label;
  final bool isCorrect;

  factory SlideOption.fromJson(Map<String, dynamic> j) => SlideOption(
        id: j['id'] as String,
        label: j['label'] as String,
        isCorrect: j['isCorrect'] == true,
      );
}

class Slide {
  const Slide({
    required this.id,
    required this.type,
    required this.question,
    required this.options,
    this.order = 0,
    this.imageUrl,
  });

  final String id;
  final int order;
  final SlideType type;
  final String question;
  final String? imageUrl;
  final List<SlideOption> options;

  factory Slide.fromJson(Map<String, dynamic> j) => Slide(
        id: j['id'] as String,
        order: (j['order'] as num?)?.toInt() ?? (j['index'] as num?)?.toInt() ?? 0,
        type: SlideType.parse(j['type']),
        question: j['question'] as String,
        imageUrl: j['imageUrl'] as String?,
        options: [for (final o in (j['options'] as List? ?? const [])) SlideOption.fromJson(o as Map<String, dynamic>)],
      );
}

class Presentation {
  const Presentation({required this.id, required this.title, required this.slides, this.updatedAt});

  final String id;
  final String title;
  final List<Slide> slides;
  final DateTime? updatedAt;

  factory Presentation.fromJson(Map<String, dynamic> j) => Presentation(
        id: j['id'] as String,
        title: j['title'] as String,
        updatedAt: _date(j['updatedAt']),
        slides: [for (final s in (j['slides'] as List? ?? const [])) Slide.fromJson(s as Map<String, dynamic>)],
      );

  Presentation copyWith({String? title, List<Slide>? slides}) =>
      Presentation(id: id, title: title ?? this.title, slides: slides ?? this.slides, updatedAt: updatedAt);
}

/// Payload of `session:state`. Lecturer-only fields are null for students.
class LiveState {
  const LiveState({
    required this.sessionId,
    required this.status,
    required this.showResultsToStudents,
    required this.totalSlides,
    this.currentSlide,
    this.currentIndex,
    this.code,
    this.presentationTitle,
    this.isLastSlide = false,
  });

  final String sessionId;
  final SessionStatus status;
  final bool showResultsToStudents;
  final int totalSlides;
  final Slide? currentSlide;
  final int? currentIndex;
  final String? code;
  final String? presentationTitle;
  final bool isLastSlide;

  factory LiveState.fromJson(Map<String, dynamic> j) {
    final cs = j['currentSlide'] as Map<String, dynamic>?;
    return LiveState(
      sessionId: j['sessionId'] as String,
      status: SessionStatus.parse(j['status']),
      showResultsToStudents: j['showResultsToStudents'] == true,
      totalSlides: (j['totalSlides'] as num?)?.toInt() ?? 0,
      currentSlide: cs == null ? null : Slide.fromJson(cs),
      currentIndex: (cs?['index'] as num?)?.toInt(),
      code: j['code'] as String?,
      presentationTitle: j['presentationTitle'] as String?,
      isLastSlide: j['isLastSlide'] == true,
    );
  }
}

/// Payload of `results:update` (aggregates only).
class LiveResults {
  const LiveResults({required this.slideId, required this.counts, required this.answered, required this.participants});

  final String slideId;
  final Map<String, int> counts;
  final int answered;
  final int participants;

  int countFor(String optionId) => counts[optionId] ?? 0;
  double percentFor(String optionId) => answered == 0 ? 0 : countFor(optionId) * 100 / answered;

  factory LiveResults.fromJson(Map<String, dynamic> j) => LiveResults(
        slideId: j['slideId'] as String,
        counts: {
          for (final c in (j['counts'] as List? ?? const []))
            (c as Map)['optionId'] as String: (c['count'] as num).toInt(),
        },
        answered: (j['answered'] as num?)?.toInt() ?? 0,
        participants: (j['participants'] as num?)?.toInt() ?? 0,
      );
}

/// Payload of `pulse:update`.
class PulseTotals {
  const PulseTotals({this.following = 0, this.lost = 0});

  final int following;
  final int lost;
  int get total => following + lost;
  double get followingPct => total == 0 ? 0 : following * 100 / total;
  double get lostPct => total == 0 ? 0 : lost * 100 / total;

  factory PulseTotals.fromJson(Map<String, dynamic> j) =>
      PulseTotals(following: (j['following'] as num?)?.toInt() ?? 0, lost: (j['lost'] as num?)?.toInt() ?? 0);
}

class SummaryOption {
  const SummaryOption({required this.id, required this.label, required this.isCorrect, required this.count, required this.percent});

  final String id;
  final String label;
  final bool isCorrect;
  final int count;
  final double percent;

  factory SummaryOption.fromJson(Map<String, dynamic> j) => SummaryOption(
        id: j['id'] as String,
        label: j['label'] as String,
        isCorrect: j['isCorrect'] == true,
        count: (j['count'] as num).toInt(),
        percent: (j['percent'] as num).toDouble(),
      );
}

class SummarySlide {
  const SummarySlide({
    required this.slideId,
    required this.index,
    required this.type,
    required this.question,
    required this.responses,
    required this.options,
    this.percentCorrect,
  });

  final String slideId;
  final int index;
  final SlideType type;
  final String question;
  final int responses;
  final List<SummaryOption> options;
  final double? percentCorrect;

  SummaryOption? get topOption {
    if (responses == 0 || options.isEmpty) return null;
    return options.reduce((a, b) => b.count > a.count ? b : a);
  }

  factory SummarySlide.fromJson(Map<String, dynamic> j) => SummarySlide(
        slideId: j['slideId'] as String,
        index: (j['index'] as num).toInt(),
        type: SlideType.parse(j['type']),
        question: j['question'] as String,
        responses: (j['responses'] as num).toInt(),
        options: [for (final o in j['options'] as List) SummaryOption.fromJson(o as Map<String, dynamic>)],
        percentCorrect: (j['percentCorrect'] as num?)?.toDouble(),
      );
}

class SessionSummary {
  const SessionSummary({
    required this.sessionId,
    required this.presentationTitle,
    required this.status,
    required this.participants,
    required this.pulse,
    required this.slides,
    this.endedAt,
  });

  final String sessionId;
  final String presentationTitle;
  final SessionStatus status;
  final int participants;
  final PulseTotals pulse;
  final List<SummarySlide> slides;
  final DateTime? endedAt;

  int get totalResponses => slides.fold(0, (a, s) => a + s.responses);

  factory SessionSummary.fromJson(Map<String, dynamic> j) => SessionSummary(
        sessionId: j['sessionId'] as String,
        presentationTitle: j['presentationTitle'] as String,
        status: SessionStatus.parse(j['status']),
        participants: (j['participants'] as num).toInt(),
        pulse: PulseTotals.fromJson(j['pulse'] as Map<String, dynamic>),
        slides: [for (final s in j['slides'] as List) SummarySlide.fromJson(s as Map<String, dynamic>)],
        endedAt: _date(j['endedAt']),
      );
}
