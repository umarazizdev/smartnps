import 'dart:ui' as ui;
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_signaturepad/signaturepad.dart';
import 'package:smartnps360/src/screens/models/application_models.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

class SignatureModal extends StatefulWidget {
  final String title;
  final String signatureKey;
  final SignatureData? existingSignature;
  final Function(SignatureData) onSave;

  const SignatureModal({
    super.key,
    required this.title,
    required this.signatureKey,
    this.existingSignature,
    required this.onSave,
  });

  @override
  State<SignatureModal> createState() => _SignatureModalState();
}

class _SignatureModalState extends State<SignatureModal> {
  static const _cardTop = Color(0xFF1B3454);
  static const _cardMid = Color(0xFF172B45);
  static const _cardBottom = Color(0xFF0E203C);
  static const _border = Color(0xFF496B94);
  static const _heading = Color(0xFFF8FAFC);
  static const _body = Color(0xFFB6C8DF);
  static const _canvas = Color(0xFFF8FAFC);
  static const _ink = Color(0xFF111827);
  static const _clearBg = Color(0xFF263C59);
  static const _closeFill = Color(0xFF314B70);
  static const _cancelBg = Color(0xFF203650);
  static const _blueTop = Color(0xFF2F9BFF);
  static const _blueBottom = Color(0xFF155EEF);
  static const _success = Color(0xFF39CFA1);

  final GlobalKey<SfSignaturePadState> _signaturePadKey = GlobalKey();
  String _metaText = 'No signature saved yet.';
  bool _hasNewSignatureInput = false;

  bool get _useReducedEffects => !kIsWeb && Platform.isAndroid;
  bool get _canSave =>
      widget.existingSignature == null || _hasNewSignatureInput;

  @override
  void initState() {
    super.initState();
    if (widget.existingSignature != null) {
      _updateMetaText();
    }
  }

  void _updateMetaText() {
    setState(() {
      _metaText = 'Draw your signature, then tap Save signature.';
    });
  }

  Future<void> _handleSave() async {
    final signaturePad = _signaturePadKey.currentState;

    if (signaturePad == null) return;

    if (!_hasNewSignatureInput) {
      _showAlert('Please sign before saving.');
      return;
    }

    final image = await signaturePad.toImage();
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      _showAlert('Failed to save signature.');
      return;
    }

    final pngBytes = byteData.buffer.asUint8List();

    final base64String = 'data:image/png;base64,${base64Encode(pngBytes)}';

    final signatureData = SignatureData(
      dataUrl: base64String,
      signedAt: DateTime.now().toIso8601String(),
      device: _getDeviceInfo(),
    );

    if (!mounted) return;
    final navigator = Navigator.of(context);
    navigator.pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onSave(signatureData);
    });
  }

  void _handleClear() {
    _signaturePadKey.currentState?.clear();
    if (_hasNewSignatureInput) {
      setState(() {
        _hasNewSignatureInput = false;
      });
    }
    _updateMetaText();
  }

  void _handleSignatureDrawStart() {
    if (!_hasNewSignatureInput) {
      setState(() {
        _hasNewSignatureInput = true;
      });
    }
  }

  void _showAlert(String message) {
    showDialog(
      context: context,
      barrierColor: const Color(0xAD040B17),
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 360),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _border.withValues(alpha: 0.85)),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_cardTop, _cardMid, _cardBottom],
              stops: [0, 0.52, 1],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 28,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Notice',
                style: TextStyle(
                  color: _heading,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: const TextStyle(
                  color: _body,
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: _MutedButton(
                  label: 'OK',
                  onTap: () => Navigator.pop(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getDeviceInfo() {
    if (kIsWeb) {
      return 'Web Browser';
    } else if (Platform.isAndroid) {
      return 'Android Device';
    } else if (Platform.isIOS) {
      return 'iOS Device';
    } else if (Platform.isMacOS) {
      return 'macOS';
    } else if (Platform.isWindows) {
      return 'Windows';
    } else {
      return 'Flutter App';
    }
  }

  Uint8List? _base64ToBytes(String dataUrl) {
    try {
      final base64 = dataUrl.split(',').last;
      return base64Decode(base64);
    } catch (_) {
      return null;
    }
  }

  String _formatExistingDate(String isoString) {
    try {
      final dt = DateTime.parse(isoString);
      final now = DateTime.now();
      final diff = now.difference(dt);

      if (diff.inMinutes < 1) {
        return 'just now';
      } else if (diff.inHours < 1) {
        return '${diff.inMinutes} minute${diff.inMinutes == 1 ? '' : 's'} ago';
      } else if (diff.inDays < 1) {
        return '${diff.inHours} hour${diff.inHours == 1 ? '' : 's'} ago';
      } else if (diff.inDays < 7) {
        return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
      } else {
        return DateFormat('MMM d, yyyy').format(dt.toLocal());
      }
    } catch (_) {
      return 'previously';
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final isSmall = size.width < 720;
    final maxDialogHeight = (size.height - viewInsets.bottom - 48).clamp(
      420.0,
      size.height * 0.92,
    );

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: EdgeInsets.fromLTRB(
        isSmall ? 12 : 20,
        isSmall ? 16 : 24,
        isSmall ? 12 : 20,
        isSmall ? 16 : 24,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 760, maxHeight: maxDialogHeight),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _border.withValues(alpha: 0.9)),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_cardTop, _cardMid, _cardBottom],
              stops: [0, 0.52, 1],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: _useReducedEffects ? 0.32 : 0.42,
                ),
                blurRadius: _useReducedEffects ? 24 : 36,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                          color: _heading,
                        ),
                      ),
                    ),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => Navigator.of(context).pop(),
                        customBorder: const CircleBorder(),
                        child: SizedBox(
                          width: 42,
                          height: 42,
                          child: Center(
                            child: Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _closeFill.withValues(alpha: 0.9),
                              ),
                              alignment: Alignment.center,
                              child: const Icon(
                                Icons.close_rounded,
                                size: 20,
                                color: Color(0xFFF1F6FF),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(height: 1, color: _border.withValues(alpha: 0.35)),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                  physics: const ClampingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Sign inside the box below using your finger on mobile or mouse on desktop.',
                        style: TextStyle(
                          color: _body,
                          fontSize: 14.5,
                          height: 1.5,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (widget.existingSignature != null &&
                          widget.existingSignature!.dataUrl.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: _success.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: _success.withValues(alpha: 0.38),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(
                                    Icons.check_circle_rounded,
                                    color: _success,
                                    size: 18,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'CURRENT SIGNATURE',
                                    style: TextStyle(
                                      color: _success,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.4,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Container(
                                height: 84,
                                width: double.infinity,
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: _canvas,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: _border.withValues(alpha: 0.45),
                                  ),
                                ),
                                child: Builder(
                                  builder: (context) {
                                    final bytes = _base64ToBytes(
                                      widget.existingSignature!.dataUrl,
                                    );
                                    if (bytes == null) {
                                      return const Center(
                                        child: Text(
                                          'Error loading signature',
                                          style: TextStyle(
                                            color: Color(0xFFFF858E),
                                            fontSize: 12,
                                          ),
                                        ),
                                      );
                                    }
                                    return Image.memory(
                                      bytes,
                                      fit: BoxFit.contain,
                                      errorBuilder:
                                          (context, error, stackTrace) {
                                            return const Center(
                                              child: Text(
                                                'Failed to display signature',
                                                style: TextStyle(
                                                  color: Color(0xFFFF858E),
                                                  fontSize: 12,
                                                ),
                                              ),
                                            );
                                          },
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Signed ${_formatExistingDate(widget.existingSignature!.signedAt)}',
                                style: const TextStyle(
                                  color: _body,
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Draw a new signature below to replace it:',
                          style: TextStyle(
                            color: _heading,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: _border),
                          borderRadius: BorderRadius.circular(18),
                          color: _cardMid,
                        ),
                        child: Column(
                          children: [
                            Container(
                              height: isSmall ? 220 : 240,
                              decoration: const BoxDecoration(
                                color: _canvas,
                                borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(17),
                                ),
                              ),
                              child: ClipRRect(
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(17),
                                ),
                                child: SfSignaturePad(
                                  key: _signaturePadKey,
                                  minimumStrokeWidth: 2.2,
                                  maximumStrokeWidth: 2.2,
                                  strokeColor: _ink,
                                  backgroundColor: _canvas,
                                  onDrawStart: () {
                                    _handleSignatureDrawStart();
                                    return false;
                                  },
                                  onDraw: (_, _) {
                                    _handleSignatureDrawStart();
                                  },
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.fromLTRB(
                                14,
                                12,
                                12,
                                12,
                              ),
                              decoration: BoxDecoration(
                                color: _cancelBg.withValues(alpha: 0.55),
                                border: Border(
                                  top: BorderSide(
                                    color: _border.withValues(alpha: 0.55),
                                  ),
                                ),
                                borderRadius: const BorderRadius.vertical(
                                  bottom: Radius.circular(17),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'Draw your signature clearly. It will be saved with date, time, and device details.',
                                      style: TextStyle(
                                        color: _body,
                                        fontSize: 13.5,
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  _MutedButton(
                                    label: 'Clear',
                                    background: _clearBg,
                                    onTap: _handleClear,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Container(height: 1, color: _border.withValues(alpha: 0.35)),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
                child: isSmall
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            _metaText,
                            style: const TextStyle(
                              color: _body,
                              fontSize: 13.5,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _MutedButton(
                                  label: 'Cancel',
                                  expand: true,
                                  onTap: () => Navigator.pop(context),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                flex: 2,
                                child: _PrimaryButton(
                                  label: 'Save Signature',
                                  enabled: _canSave,
                                  onTap: _canSave ? _handleSave : null,
                                ),
                              ),
                            ],
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(
                            child: Text(
                              _metaText,
                              style: const TextStyle(
                                color: _body,
                                fontSize: 13.5,
                                height: 1.4,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          _MutedButton(
                            label: 'Cancel',
                            onTap: () => Navigator.pop(context),
                          ),
                          const SizedBox(width: 10),
                          _PrimaryButton(
                            label: 'Save Signature',
                            enabled: _canSave,
                            onTap: _canSave ? _handleSave : null,
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MutedButton extends StatelessWidget {
  const _MutedButton({
    required this.label,
    required this.onTap,
    this.background = _SignatureModalState._cancelBg,
    this.expand = false,
  });

  final String label;
  final VoidCallback onTap;
  final Color background;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final child = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          height: 48,
          padding: EdgeInsets.symmetric(horizontal: expand ? 12 : 18),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _SignatureModalState._border.withValues(alpha: 0.72),
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 14.5,
              ),
            ),
          ),
        ),
      ),
    );

    return expand ? child : IntrinsicWidth(child: child);
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: enabled
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      _SignatureModalState._blueTop,
                      _SignatureModalState._blueBottom,
                    ],
                  )
                : null,
            color: enabled ? null : const Color(0xFF243652),
            border: Border.all(
              color: enabled
                  ? const Color(0xFF78B9FF).withValues(alpha: 0.45)
                  : _SignatureModalState._border.withValues(alpha: 0.4),
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: enabled
                    ? Colors.white
                    : _SignatureModalState._body.withValues(alpha: 0.6),
                fontWeight: FontWeight.w700,
                fontSize: 14.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
