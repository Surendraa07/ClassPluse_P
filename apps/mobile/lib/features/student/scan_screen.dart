import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/common.dart';
import '../../widgets/inline_banner.dart';
import '../../widgets/secondary_button.dart';
import 'student_repository.dart';

/// Camera QR scanner. Pops with the 6-digit code when a ClassPluse QR is found.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _controller = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _done = false;
  bool _wrongCode = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final b in capture.barcodes) {
      final raw = b.rawValue;
      if (raw == null) continue;
      final code = parseSessionCode(raw);
      if (code != null) {
        _done = true;
        context.pop(code);
        return;
      }
    }
    if (!_wrongCode) setState(() => _wrongCode = true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(
              title: 'Scan QR code',
              subtitle: "Point your camera at the teacher's screen",
              onLeading: () => context.pop(),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.s16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  child: ColoredBox(
                    color: AppColors.textPrimary,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        MobileScanner(
                          controller: _controller,
                          onDetect: _onDetect,
                          errorBuilder: (context, error) => _CameraError(error: error),
                        ),
                        IgnorePointer(
                          child: Center(
                            child: Container(
                              width: 240,
                              height: 240,
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.white, width: 4),
                                borderRadius: BorderRadius.circular(AppRadius.xl),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: AppSpace.s24,
                          child: Text(
                            _wrongCode ? 'That is not a ClassPluse code' : 'Align the QR code inside the frame',
                            textAlign: TextAlign.center,
                            style: AppText.bodyStrong.copyWith(color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpace.s16),
              child: Column(
                children: [
                  SecondaryButton(label: 'Enter code instead', onPressed: () => context.pop()),
                  const SizedBox(height: AppSpace.s12),
                  const Text(
                    'Camera access is only used to read the QR code. Nothing is recorded or saved.',
                    style: AppText.caption,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CameraError extends StatelessWidget {
  const _CameraError({required this.error});
  final MobileScannerException error;

  @override
  Widget build(BuildContext context) {
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    return ColoredBox(
      color: AppColors.bgApp,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.s16),
          child: InlineBanner(
            title: denied ? 'Camera access is off' : "Camera isn't available",
            message: denied
                ? 'Allow camera access in your phone settings, or type the code instead.'
                : 'Type the 6-digit code instead.',
            actionLabel: 'Enter code instead',
            onAction: () => context.pop(),
          ),
        ),
      ),
    );
  }
}
