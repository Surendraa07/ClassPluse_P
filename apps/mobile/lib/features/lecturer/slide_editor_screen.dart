import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/models.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/uploads/image_uploader.dart';
import '../../widgets/common.dart';
import '../../widgets/image_widgets.dart';
import '../../widgets/inline_banner.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/skeleton_loader.dart';
import 'lecturer_repository.dart';
import 'presentations_controller.dart';

const _minOptions = 2;
const _maxOptions = 6;

class _OptionField {
  _OptionField({this.id, String label = '', this.isCorrect = false}) : controller = TextEditingController(text: label);
  final String? id;
  final TextEditingController controller;
  bool isCorrect;
}

/// Create or edit a poll/quiz slide. Pops `true` after a successful save.
class SlideEditorScreen extends ConsumerStatefulWidget {
  const SlideEditorScreen({super.key, required this.presentationId, this.slideId, this.initialType = SlideType.poll});

  final String presentationId;
  final String? slideId;
  final SlideType initialType;

  @override
  ConsumerState<SlideEditorScreen> createState() => _SlideEditorScreenState();
}

class _SlideEditorScreenState extends ConsumerState<SlideEditorScreen> {
  final _question = TextEditingController();
  late SlideType _type = widget.initialType;
  final List<_OptionField> _options = [];
  bool _loaded = false;
  bool _saving = false;
  bool _submitted = false;
  String? _serverError;
  String? _imageUrl;
  bool _uploading = false;
  double? _uploadProgress;
  String? _imageError;
  int _slideNumber = 0;
  int _slideTotal = 0;

  bool get _isNew => widget.slideId == null;

  @override
  void initState() {
    super.initState();
    if (_isNew) {
      _options.addAll([_OptionField(), _OptionField()]);
      _loaded = true;
    }
  }

  @override
  void dispose() {
    _question.dispose();
    for (final o in _options) {
      o.controller.dispose();
    }
    super.dispose();
  }

  void _hydrate(Presentation p) {
    if (_loaded) return;
    final index = p.slides.indexWhere((s) => s.id == widget.slideId);
    _slideTotal = p.slides.length + (_isNew ? 1 : 0);
    _slideNumber = _isNew ? p.slides.length + 1 : index + 1;
    if (index < 0) return;
    final s = p.slides[index];
    _type = s.type;
    _question.text = s.question;
    _imageUrl = s.imageUrl;
    _options.addAll([for (final o in s.options) _OptionField(id: o.id, label: o.label, isCorrect: o.isCorrect)]);
    _loaded = true;
  }

  // ---- validation (mirrors the server rules) ----
  String? get _questionError => _question.text.trim().isEmpty ? 'Enter a question' : null;

  String? _optionError(int i) {
    final label = _options[i].controller.text.trim();
    if (label.isEmpty) return 'Enter option ${i + 1}';
    final dup = _options.take(i).any((o) => o.controller.text.trim().toLowerCase() == label.toLowerCase());
    return dup ? 'Options must be different' : null;
  }

  String? get _correctError =>
      _type == SlideType.quiz && _options.where((o) => o.isCorrect).length != 1 ? 'Mark the correct answer' : null;

  bool get _valid =>
      _questionError == null && _correctError == null && List.generate(_options.length, _optionError).every((e) => e == null);

  Future<void> _save() async {
    setState(() {
      _submitted = true;
      _serverError = null;
    });
    if (!_valid) return;
    setState(() => _saving = true);
    final draft = SlideDraft(
      type: _type,
      question: _question.text,
      imageUrl: _imageUrl,
      options: [for (final o in _options) (id: o.id, label: o.controller.text, isCorrect: o.isCorrect)],
    );
    final repo = ref.read(lecturerRepositoryProvider);
    try {
      if (_isNew) {
        await repo.createSlide(widget.presentationId, draft);
      } else {
        await repo.updateSlide(widget.slideId!, draft);
      }
      if (mounted) context.pop(true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _serverError = e.code == 'SESSION_ACTIVE'
              ? 'This presentation is live. End the session before editing.'
              : (e.fieldErrors.values.isNotEmpty ? e.fieldErrors.values.first : e.message);
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changeImage() async {
    final action = await showImageSourceSheet(context, canRemove: _imageUrl != null);
    if (action == null || !mounted) return;
    if (action == ImageAction.remove) {
      setState(() {
        _imageUrl = null;
        _imageError = null;
      });
      return;
    }
    final file = await pickImage(sourceFor(action));
    if (file == null || !mounted) return;
    setState(() {
      _uploading = true;
      _uploadProgress = null;
      _imageError = null;
    });
    try {
      final url = await ref.read(imageUploaderProvider).upload(
            UploadKind.slide,
            bytes: await file.readAsBytes(),
            filename: file.name,
            onProgress: (p) => mounted ? setState(() => _uploadProgress = p) : null,
          );
      if (mounted) setState(() => _imageUrl = url);
    } on ApiException catch (e) {
      if (mounted) setState(() => _imageError = e.message);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Widget _imageSection() {
    final Widget body;
    if (_uploading) {
      body = Semantics(
        liveRegion: true,
        label: 'Uploading image',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(value: _uploadProgress, minHeight: 6, borderRadius: BorderRadius.circular(3)),
            const SizedBox(height: AppSpace.s8),
            Text(_uploadProgress == null ? 'Uploading…' : 'Uploading… ${(_uploadProgress! * 100).round()}%', style: AppText.caption),
          ],
        ),
      );
    } else if (_imageUrl != null) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SlideImage(_imageUrl!, maxHeight: 180),
          const SizedBox(height: AppSpace.s4),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                key: const ValueKey('image-change'),
                onPressed: _changeImage,
                icon: const Icon(Icons.swap_horiz_rounded),
                label: const Text('Replace'),
                style: TextButton.styleFrom(minimumSize: const Size(44, 48), textStyle: AppText.label),
              ),
              TextButton.icon(
                key: const ValueKey('image-remove'),
                onPressed: () => setState(() => _imageUrl = null),
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Remove'),
                style: TextButton.styleFrom(
                  minimumSize: const Size(44, 48),
                  textStyle: AppText.label,
                  foregroundColor: AppColors.danger,
                ),
              ),
            ],
          ),
        ],
      );
    } else {
      body = OutlinedButton.icon(
        key: const ValueKey('image-add'),
        onPressed: _changeImage,
        icon: const Icon(Icons.add_photo_alternate_outlined),
        label: const Text('Add image'),
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), textStyle: AppText.label),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Image (optional)'),
        const SizedBox(height: AppSpace.s8),
        body,
        if (_imageError != null) ...[
          const SizedBox(height: AppSpace.s8),
          Semantics(
            liveRegion: true,
            child: Row(
              children: [
                const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 18),
                const SizedBox(width: AppSpace.s8),
                Expanded(child: Text(_imageError!, style: AppText.label.copyWith(color: AppColors.danger))),
              ],
            ),
          ),
        ],
      ],
    );
  }

  void _setType(SlideType t) {
    setState(() {
      _type = t;
      if (t == SlideType.poll) {
        for (final o in _options) {
          o.isCorrect = false;
        }
      }
    });
  }

  void _addOption() {
    if (_options.length >= _maxOptions) return;
    setState(() => _options.add(_OptionField()));
  }

  void _removeOption(int i) {
    if (_options.length <= _minOptions) return;
    setState(() => _options.removeAt(i).controller.dispose());
  }

  void _markCorrect(int i) => setState(() {
        for (var j = 0; j < _options.length; j++) {
          _options[j].isCorrect = j == i;
        }
      });

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(presentationProvider(widget.presentationId));
    final p = async.value;
    if (p != null) _hydrate(p);

    final title = '${_isNew ? 'New' : 'Edit'} ${_type.label.toLowerCase()}';
    final subtitle = _slideTotal > 0 ? 'Slide $_slideNumber of $_slideTotal' : null;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(
              title: title,
              subtitle: subtitle,
              leadingIcon: Icons.close_rounded,
              leadingLabel: 'Close without saving',
              onLeading: () => context.pop(false),
            ),
            Expanded(
              child: !_loaded
                  ? (async.hasError
                      ? Padding(
                          padding: const EdgeInsets.all(AppSpace.s16),
                          child: InlineBanner(
                            title: "Couldn't load this slide",
                            actionLabel: 'Retry',
                            onAction: () => ref.invalidate(presentationProvider(widget.presentationId)),
                          ),
                        )
                      : const Padding(padding: EdgeInsets.all(AppSpace.s16), child: SkeletonLoader(rows: 4)))
                  : _form(),
            ),
            if (_loaded)
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpace.s16, AppSpace.s8, AppSpace.s16, AppSpace.s16),
                child: PrimaryButton(
                  key: const ValueKey('save-slide'),
                  label: 'Save slide',
                  loading: _saving,
                  loadingLabel: 'Saving…',
                  onPressed: _uploading ? null : _save,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _form() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpace.s16, AppSpace.s8, AppSpace.s16, AppSpace.s16),
      children: [
        if (_serverError != null) ...[
          InlineBanner(
            title: "Couldn't save changes",
            message: _serverError,
            actionLabel: 'Retry',
            onAction: _saving ? null : _save,
          ),
          const SizedBox(height: AppSpace.s16),
        ],
        const SectionLabel('Slide type'),
        const SizedBox(height: AppSpace.s8),
        SegmentedButton<SlideType>(
          segments: const [
            ButtonSegment(value: SlideType.poll, label: Text('Poll'), icon: Icon(Icons.bar_chart_rounded)),
            ButtonSegment(value: SlideType.quiz, label: Text('Quiz'), icon: Icon(Icons.emoji_events_outlined)),
          ],
          selected: {_type},
          onSelectionChanged: (s) => _setType(s.first),
          style: SegmentedButton.styleFrom(minimumSize: const Size(0, 48), textStyle: AppText.label),
        ),
        const SizedBox(height: AppSpace.s20),
        const SectionLabel('Question'),
        const SizedBox(height: AppSpace.s8),
        Semantics(
          label: 'Question',
          child: TextField(
            key: const ValueKey('slide-question'),
            controller: _question,
            maxLength: 300,
            minLines: 1,
            maxLines: 4,
            textInputAction: TextInputAction.next,
            style: AppText.body,
            onChanged: (_) => _submitted ? setState(() {}) : null,
            decoration: InputDecoration(
              hintText: 'e.g. Which loop always runs at least once?',
              helperText: 'Students see this on their phone',
              errorText: _submitted ? _questionError : null,
            ),
          ),
        ),
        const SizedBox(height: AppSpace.s8),
        _imageSection(),
        const SizedBox(height: AppSpace.s20),
        SectionLabel(_type == SlideType.quiz ? 'Answer options · tap the circle to mark the correct one' : 'Answer options'),
        const SizedBox(height: AppSpace.s8),
        for (var i = 0; i < _options.length; i++) ...[
          _optionRow(i),
          const SizedBox(height: AppSpace.s12),
        ],
        if (_submitted && _correctError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.s8),
            child: Row(
              children: [
                const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 18),
                const SizedBox(width: AppSpace.s8),
                Text(_correctError!, style: AppText.label.copyWith(color: AppColors.danger)),
              ],
            ),
          ),
        if (_options.length < _maxOptions)
          Align(
            alignment: Alignment.center,
            child: TextButton.icon(
              key: const ValueKey('add-option'),
              onPressed: _addOption,
              icon: const Icon(Icons.add_rounded),
              label: Text('Add option (${_options.length}/$_maxOptions)'),
              style: TextButton.styleFrom(minimumSize: const Size(44, 48), textStyle: AppText.label),
            ),
          )
        else
          Center(child: Text('Maximum of $_maxOptions options', style: AppText.caption)),
      ],
    );
  }

  Widget _optionRow(int i) {
    final o = _options[i];
    final quiz = _type == SlideType.quiz;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (quiz)
          Padding(
            padding: const EdgeInsets.only(right: AppSpace.s4),
            child: IconButton(
              key: ValueKey('option-correct-$i'),
              tooltip: o.isCorrect ? 'Correct answer' : 'Mark option ${i + 1} as correct',
              isSelected: o.isCorrect,
              onPressed: () => _markCorrect(i),
              icon: const Icon(Icons.radio_button_unchecked_rounded, color: AppColors.textSecondary),
              selectedIcon: const Icon(Icons.check_circle_rounded, color: AppColors.success),
            ),
          ),
        Expanded(
          child: Semantics(
            label: 'Option ${i + 1}${quiz && o.isCorrect ? ', correct answer' : ''}',
            child: TextField(
              key: ValueKey('option-field-$i'),
              controller: o.controller,
              maxLength: 120,
              textInputAction: TextInputAction.next,
              style: AppText.body,
              onChanged: (_) => _submitted ? setState(() {}) : null,
              decoration: InputDecoration(
                hintText: 'Option ${i + 1}',
                counterText: '',
                errorText: _submitted ? _optionError(i) : null,
                helperText: quiz && o.isCorrect ? 'Correct answer' : null,
                helperStyle: AppText.caption.copyWith(color: AppColors.success),
              ),
            ),
          ),
        ),
        if (_options.length > _minOptions)
          IconButton(
            key: ValueKey('option-remove-$i'),
            tooltip: 'Remove option ${i + 1}',
            onPressed: () => _removeOption(i),
            icon: const Icon(Icons.remove_circle_outline_rounded, color: AppColors.textSecondary),
          ),
      ],
    );
  }
}
