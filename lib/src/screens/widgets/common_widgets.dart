import 'dart:async';

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:smartnps360/src/screens/models/application_models.dart';
import 'package:smartnps360/src/screens/utilities/app_colors.dart';
import 'package:smartnps360/src/screens/utilities/const.dart';
import 'signature_modal.dart';

class PageHeader extends StatelessWidget {
  final ApplicationStep step;
  final int stepNumber;
  final int totalSteps;
  final String? lastSaved;

  const PageHeader({
    super.key,
    required this.step,
    required this.stepNumber,
    required this.totalSteps,
    this.lastSaved,
  });

  @override
  Widget build(BuildContext context) {
    final progress = totalSteps == 0 ? 0.0 : stepNumber / totalSteps;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(40),
                border: Border.all(color: cWhite.withValues(alpha: 0.25)),
              ),
              child: Text(
                'Step $stepNumber of $totalSteps',
                style: const TextStyle(
                  color: cWhite,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
            const Spacer(),
            if (lastSaved != null && lastSaved!.isNotEmpty)
              Text(
                'Last saved ${_formatLastSaved(lastSaved!)}',
                style: const TextStyle(color: Color(0xffF1F5F9), fontSize: 12),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          step.title,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: cWhite,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          step.subtitle,
          style: const TextStyle(
            fontSize: 14,
            color: Color(0xffF1F5F9),
            height: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: progress.clamp(0, 1),
            minHeight: 8,
            backgroundColor: Colors.white.withValues(alpha: 0.2),
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        ),
      ],
    );
  }

  String _formatLastSaved(String iso) {
    try {
      return DateFormat('MMM d, h:mm a').format(DateTime.parse(iso).toLocal());
    } catch (_) {
      return 'recently';
    }
  }
}

class SectionTitle extends StatelessWidget {
  final String title;

  const SectionTitle(this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: cWhite,
      ),
    );
  }
}

// SECTION SUBTITLE
class SectionSubtitle extends StatelessWidget {
  final String subtitle;

  const SectionSubtitle(this.subtitle, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      subtitle,
      style: const TextStyle(
        color: Color(0xffF1F5F9),
        fontSize: 15,
        height: 1.55,
      ),
    );
  }
}

// TEXT FIELD
class AppTextField extends StatefulWidget {
  final String label;
  final String? initialValue;
  final bool required;
  final bool obscureText;
  final TextInputType keyboardType;
  final int? maxLines;
  final Function(String)? onChanged;
  final String? hint;

  const AppTextField({
    super.key,
    required this.label,
    this.initialValue,
    this.required = false,
    this.obscureText = false,
    this.keyboardType = TextInputType.text,
    this.maxLines = 1,
    this.onChanged,
    this.hint,
  });

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  late FocusNode _focusNode;
  Timer? _focusScrollTimer;
  bool _focusScrollScheduled = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _focusNode.addListener(() {
      if (!mounted) return;

      if (_focusNode.hasFocus) {
        if (_focusScrollScheduled) return;
        _focusScrollScheduled = true;

        // Delay once so the IME transition can start before we request scrolling.
        _focusScrollTimer?.cancel();
        _focusScrollTimer = Timer(const Duration(milliseconds: 140), () {
          if (!mounted || !_focusNode.hasFocus) {
            _focusScrollScheduled = false;
            return;
          }
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !_focusNode.hasFocus) {
              _focusScrollScheduled = false;
              return;
            }
            Scrollable.ensureVisible(
              context,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
            );
          });
        });
      } else {
        _focusScrollScheduled = false;
        _focusScrollTimer?.cancel();
      }
    });
  }

  @override
  void dispose() {
    _focusScrollTimer?.cancel();
    _focusScrollScheduled = false;
    _focusNode.dispose();
    super.dispose();
  }

  IconData _resolveIcon(String value) {
    final key = value.toLowerCase();

    // Form-specific icons
    if (key == 'm.i.' || key == 'm.i') return Icons.text_fields;
    if (key.contains('apt') || key.contains('unit')) return Icons.apartment;
    if (key.contains('social security') || key.contains('ssn')) {
      return Icons.verified_user_outlined;
    }
    if (key.contains('citizen')) return Icons.flag_outlined;
    if (key.contains('authorization')) return Icons.verified_outlined;
    if (key.contains('employment details')) return Icons.work_outline;
    if (key.contains('most recent company')) return Icons.business_outlined;
    if (key.contains('felony')) return Icons.gavel;
    if (key.contains('alias')) return Icons.person_outline;
    if (key.contains('explain')) return Icons.note_outlined;
    if (key.contains('emergency contact')) return Icons.emergency;
    if (key.contains('alternate phone')) return Icons.phone_outlined;
    if (key.contains('guard card')) return Icons.badge_outlined;
    if (key.contains('firearm permit')) return Icons.local_police_outlined;
    if (key.contains('base rate') || key.contains('dollar')) {
      return Icons.attach_money;
    }

    // General field icons
    if (key.contains('name')) return Icons.person_outline;
    if (key.contains('email')) return Icons.email_outlined;
    if (key.contains('phone')) return Icons.phone_outlined;
    if (key.contains('password')) return Icons.lock_outline;
    if (key.contains('date') || key == 'dob' || key.contains('when')) {
      return Icons.calendar_month_outlined;
    }
    if (key.contains('address') || key.contains('street')) {
      return Icons.home_outlined;
    }
    if (key.contains('city')) return Icons.location_city_outlined;
    if (key.contains('state')) return Icons.map_outlined;
    if (key.contains('zip')) return Icons.pin_drop_outlined;
    if (key.contains('driver') || key.contains('license')) {
      return Icons.badge_outlined;
    }
    if (key.contains('hair') || key.contains('eye')) {
      return Icons.visibility_outlined;
    }
    if (key.contains('height') || key.contains('weight')) {
      return Icons.straighten_outlined;
    }
    if (key.contains('company')) return Icons.business_outlined;
    if (key.contains('job')) return Icons.work_outline;
    if (key.contains('relationship')) return Icons.group_outlined;
    if (key.contains('permit') || key.contains('guard')) {
      return Icons.security_outlined;
    }

    return Icons.edit_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final isSingleLine = (widget.maxLines ?? 1) == 1;
    final fieldRadius = isSingleLine ? 40.0 : 18.0;
    final icon = _resolveIcon(widget.label);
    final placeholder = (widget.hint != null && widget.hint!.isNotEmpty)
        ? widget.hint!
        : widget.label;

    return TextFormField(
      focusNode: _focusNode,
      initialValue: widget.initialValue,
      obscureText: widget.obscureText,
      keyboardType: widget.keyboardType,
      textAlignVertical: isSingleLine
          ? TextAlignVertical.center
          : TextAlignVertical.top,
      maxLines: widget.maxLines,
      validator: widget.required
          ? (value) => value?.isEmpty ?? true ? 'Required' : null
          : null,
      onChanged: widget.onChanged,
      style: const TextStyle(color: cWhite, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        hintText: placeholder,
        alignLabelWithHint: !isSingleLine,
        filled: true,
        fillColor: Colors.transparent,
        prefixIcon: Align(
          alignment: isSingleLine ? Alignment.center : Alignment.topCenter,
          widthFactor: 1,
          heightFactor: 1,
          child: Padding(
            padding: EdgeInsets.only(
              left: isSingleLine ? 2 : 4,
              top: isSingleLine ? 0 : 10,
            ),
            child: Icon(icon, color: cWhite.withValues(alpha: 0.85), size: 24),
          ),
        ),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 58,
          minHeight: 50,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(fieldRadius),
          borderSide: BorderSide(color: cWhite, width: 1.2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(fieldRadius),
          borderSide: BorderSide(color: cWhite, width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(fieldRadius),
          borderSide: BorderSide(color: cWhite, width: 2.0),
        ),
        hintStyle: TextStyle(
          color: cWhite.withValues(alpha: 0.7),
          fontSize: 15,
          fontWeight: FontWeight.w400,
        ),
        isDense: isSingleLine,
        contentPadding: isSingleLine
            ? const EdgeInsets.symmetric(horizontal: 18, vertical: 13)
            : const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        constraints: isSingleLine ? const BoxConstraints(minHeight: 50) : null,
      ),
    );
  }
}

// AGREEMENT CARD
class AgreementCard extends StatelessWidget {
  final String title;
  final String content;

  const AgreementCard({super.key, required this.title, required this.content});

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final maxCardHeight = (screenHeight * 0.50).clamp(360.0, 520.0);

    return Container(
      constraints: BoxConstraints(maxHeight: maxCardHeight),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        border: Border.all(color: cWhite.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(18),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: cWhite,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              content,
              style: const TextStyle(
                color: Color(0xffF1F5F9),
                fontSize: 14,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// MULTI-SECTION AGREEMENT CARD
class MultiAgreementCard extends StatelessWidget {
  final List<AgreementSection> sections;

  const MultiAgreementCard({super.key, required this.sections});

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final maxCardHeight = (screenHeight * 0.50).clamp(360.0, 520.0);

    return Container(
      constraints: BoxConstraints(maxHeight: maxCardHeight),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        border: Border.all(color: cWhite.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(18),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int i = 0; i < sections.length; i++) ...[
              if (i > 0) const SizedBox(height: 24),
              _buildSection(sections[i]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSection(AgreementSection section) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          section.title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: cWhite,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          section.content,
          style: const TextStyle(
            color: Color(0xffF1F5F9),
            fontSize: 14,
            height: 1.6,
          ),
        ),
      ],
    );
  }
}

// Agreement Section Model
class AgreementSection {
  final String title;
  final String content;

  const AgreementSection({required this.title, required this.content});
}

// SIGNATURE BLOCK
class SignatureBlock extends StatelessWidget {
  final String title;
  final String signatureKey;
  final SignatureData? signature;
  final Function(SignatureData) onSign;

  const SignatureBlock({
    super.key,
    required this.title,
    required this.signatureKey,
    this.signature,
    required this.onSign,
  });

  @override
  Widget build(BuildContext context) {
    final hasSignature = signature != null && signature!.dataUrl.isNotEmpty;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.12),
                Colors.white.withValues(alpha: 0.06),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.14),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              compact
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHeader(context, hasSignature),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: _buildActionButton(
                            context,
                            hasSignature,
                            false,
                          ),
                        ),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _buildHeader(context, hasSignature)),
                        const SizedBox(width: 16),
                        _buildActionButton(context, hasSignature, false),
                      ],
                    ),
              const SizedBox(height: 12),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: hasSignature
                    ? _buildSignedState(context)
                    : _buildEmptyState(context),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, bool hasSignature) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.20),
                Colors.white.withValues(alpha: 0.08),
              ],
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child: const Icon(Icons.draw_outlined, color: Colors.white, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: hasSignature
                      ? const Color(0xFF22C55E).withValues(alpha: 0.16)
                      : Colors.white.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: hasSignature
                        ? const Color(0xFF86EFAC).withValues(alpha: 0.55)
                        : Colors.white.withValues(alpha: 0.18),
                  ),
                ),
                child: Text(
                  hasSignature ? 'Signature saved' : 'Signature required',
                  style: TextStyle(
                    color: hasSignature
                        ? const Color(0xFFD1FAE5)
                        : const Color(0xffF8FAFC),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  height: 1.25,
                  color: cWhite,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                hasSignature
                    ? 'Captured on ${_formatDateTime(signature!.signedAt)}'
                    : 'Review the section and add your signature to continue this application.',
                style: const TextStyle(
                  color: Color(0xffE2E8F0),
                  fontSize: 12.5,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton(
    BuildContext context,
    bool hasSignature,
    bool fullWidth,
  ) {
    final button = ElevatedButton.icon(
      onPressed: () => _showSignatureModal(context),
      style: ElevatedButton.styleFrom(
        elevation: 0,
        foregroundColor: cPrimary,
        backgroundColor: Colors.white,
        minimumSize: Size(fullWidth ? double.infinity : 0, 42),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      icon: Icon(
        hasSignature ? Icons.edit_outlined : Icons.border_color_outlined,
        size: 18,
      ),
      label: Text(
        hasSignature ? 'Update Signature' : 'Add Signature',
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
      ),
    );

    if (fullWidth) {
      return SizedBox(width: double.infinity, child: button);
    }

    return button;
  }

  Widget _buildSignedState(BuildContext context) {
    return Container(
      key: const ValueKey('signed-state'),
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 68,
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Image.memory(
              _base64ToBytes(signature!.dataUrl),
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: const [
              Icon(Icons.verified_outlined, color: Color(0xFFBBF7D0), size: 15),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Saved for this step. You can update it before submission.',
                  style: TextStyle(
                    color: Color(0xffE2E8F0),
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Container(
      key: const ValueKey('empty-state'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        children: const [
          Icon(Icons.gesture_outlined, color: Color(0xffE2E8F0), size: 18),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'No signature yet. Tap Add Signature to continue.',
              style: TextStyle(
                color: Color(0xffE2E8F0),
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSignatureModal(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => SignatureModal(
        title: title,
        signatureKey: signatureKey,
        existingSignature: signature,
        onSave: onSign,
      ),
    );
  }

  String _formatDateTime(String isoString) {
    try {
      final dt = DateTime.parse(isoString);
      return DateFormat('MMM d, yyyy h:mm a').format(dt.toLocal());
    } catch (e) {
      return 'Not signed yet';
    }
  }

  Uint8List _base64ToBytes(String dataUrl) {
    // Extract base64 from data:image/png;base64,...
    final base64 = dataUrl.split(',').last;
    return base64Decode(base64);
  }
}

// PAGE NAVIGATION
class PageNavigation extends StatelessWidget {
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onSave;
  final bool isFirstPage;
  final bool isLastPage;
  final bool canProceed;

  const PageNavigation({
    super.key,
    required this.onPrevious,
    required this.onNext,
    required this.onSave,
    required this.isFirstPage,
    required this.isLastPage,
    this.canProceed = true,
  });

  void _saveAndAdvance(BuildContext context) {
    FocusScope.of(context).unfocus();
    onSave();
    onNext();
  }

  void _handlePrevious(BuildContext context) {
    onPrevious();
    // Defer unfocus so the page transition starts immediately.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      FocusScope.of(context).unfocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmall = screenWidth < 980;

    return Container(
      padding: const EdgeInsets.only(top: 18),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: isSmall
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: isFirstPage
                            ? null
                            : () => _handlePrevious(context),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          backgroundColor: Colors.white.withValues(alpha: 0.15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(40),
                            side: BorderSide(
                              color: cWhite.withValues(alpha: 0.3),
                            ),
                          ),
                        ),
                        child: const Text(
                          'Previous',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: cWhite,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: canProceed
                            ? () => _saveAndAdvance(context)
                            : null,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          backgroundColor: cWhite,
                          foregroundColor: cPrimary,
                          disabledBackgroundColor: const Color(0xFF9CAEC9),
                          disabledForegroundColor: const Color(0xFFF7FAFF),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(40),
                          ),
                        ),
                        child: Text(
                          isLastPage ? 'Save & Finish' : 'Save & Continue',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Previous Button
                Flexible(
                  child: TextButton(
                    onPressed: isFirstPage
                        ? null
                        : () => _handlePrevious(context),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 13,
                      ),
                      backgroundColor: Colors.white.withValues(alpha: 0.15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(40),
                        side: BorderSide(color: cWhite.withValues(alpha: 0.3)),
                      ),
                    ),
                    child: const Text(
                      'Previous',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: cWhite,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: ElevatedButton(
                    onPressed: canProceed
                        ? () => _saveAndAdvance(context)
                        : null,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 13,
                      ),
                      backgroundColor: cWhite,
                      foregroundColor: cPrimary,
                      disabledBackgroundColor: const Color(0xFF9CAEC9),
                      disabledForegroundColor: const Color(0xFFF7FAFF),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(40),
                      ),
                    ),
                    child: Text(
                      isLastPage ? 'Save & Finish' : 'Save & Continue',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class AvailabilityGrid extends StatefulWidget {
  final AvailabilityData availability;
  final VoidCallback onChanged;

  const AvailabilityGrid({
    super.key,
    required this.availability,
    required this.onChanged,
  });

  @override
  State<AvailabilityGrid> createState() => _AvailabilityGridState();
}

class _AvailabilityGridState extends State<AvailabilityGrid> {
  static const _headerBg = Color(0xFF263C59);
  static const _typeBg = Color(0xFF203650);
  static const _typeLabel = Color(0xFFE5EEFB);
  static const _rowBg = Color(0xFF172B45);
  static const _border = Color(0xFF395575);
  static const _checkboxBlue = Color(0xFF2F9BFF);
  static const _dayLabel = Color(0xFFCAD5E7);
  static const _rowHeight = 52.0;
  static const _headerHeight = 48.0;
  static const _dayColWidth = 56.0;

  final _hScroll = ScrollController();
  bool _canScrollMore = false;

  final days = [
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday',
  ];

  final types = {
    'fullTime': 'Full Time',
    'partTime': 'Part Time',
    'evening': 'Evening',
    'night': 'Night',
    'onCall': 'On Call',
  };

  @override
  void initState() {
    super.initState();
    _hScroll.addListener(_updateScrollHint);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateScrollHint());
  }

  @override
  void dispose() {
    _hScroll.removeListener(_updateScrollHint);
    _hScroll.dispose();
    super.dispose();
  }

  void _updateScrollHint() {
    if (!_hScroll.hasClients) return;
    final position = _hScroll.position;
    final more =
        position.maxScrollExtent > 0 &&
        position.pixels < position.maxScrollExtent - 4;
    if (more != _canScrollMore && mounted) {
      setState(() => _canScrollMore = more);
    }
  }

  String _dayLabelText(String day) =>
      '${day[0].toUpperCase()}${day.substring(1, 3)}';

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final typeColumnWidth = screenWidth < 480 ? 104.0 : 132.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: _rowBg,
            border: Border.all(color: _border.withValues(alpha: 0.9)),
            borderRadius: BorderRadius.circular(16),
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: typeColumnWidth,
                decoration: const BoxDecoration(
                  border: Border(right: BorderSide(color: _border, width: 1)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      height: _headerHeight,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.centerLeft,
                      color: _headerBg,
                      child: const Text(
                        'Type',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          letterSpacing: 0.1,
                          color: _typeLabel,
                        ),
                      ),
                    ),
                    ...types.entries.map((entry) {
                      return Container(
                        height: _rowHeight,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        alignment: Alignment.centerLeft,
                        decoration: const BoxDecoration(
                          color: _typeBg,
                          border: Border(
                            top: BorderSide(color: _border, width: 0.8),
                          ),
                        ),
                        child: Text(
                          entry.value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            height: 1.2,
                            color: _typeLabel,
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
              Expanded(
                child: Stack(
                  children: [
                    NotificationListener<ScrollNotification>(
                      onNotification: (notification) {
                        _updateScrollHint();
                        return false;
                      },
                      child: SingleChildScrollView(
                        controller: _hScroll,
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(
                          parent: AlwaysScrollableScrollPhysics(),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              height: _headerHeight,
                              color: _headerBg,
                              child: Row(
                                children: days.map((day) {
                                  return SizedBox(
                                    width: _dayColWidth,
                                    child: Center(
                                      child: Text(
                                        _dayLabelText(day),
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.15,
                                          color: _dayLabel,
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                            ...types.entries.map((entry) {
                              final map = _getMapForType(entry.key);
                              return Container(
                                height: _rowHeight,
                                decoration: const BoxDecoration(
                                  color: _rowBg,
                                  border: Border(
                                    top: BorderSide(color: _border, width: 0.8),
                                  ),
                                ),
                                child: Row(
                                  children: days.map((day) {
                                    return SizedBox(
                                      width: _dayColWidth,
                                      child: Center(
                                        child: SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: Checkbox(
                                            value: map[day] ?? false,
                                            materialTapTargetSize:
                                                MaterialTapTargetSize
                                                    .shrinkWrap,
                                            visualDensity:
                                                VisualDensity.compact,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(5),
                                            ),
                                            side: BorderSide(
                                              color: _checkboxBlue.withValues(
                                                alpha: 0.88,
                                              ),
                                              width: 1.5,
                                            ),
                                            fillColor:
                                                WidgetStateProperty.resolveWith(
                                                  (states) {
                                                    if (states.contains(
                                                      WidgetState.selected,
                                                    )) {
                                                      return _checkboxBlue;
                                                    }
                                                    return Colors.transparent;
                                                  },
                                                ),
                                            checkColor: Colors.white,
                                            onChanged: (value) {
                                              setState(() {
                                                map[day] = value ?? false;
                                              });
                                              widget.onChanged();
                                            },
                                          ),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
                    if (_canScrollMore)
                      Positioned(
                        top: 0,
                        right: 0,
                        bottom: 0,
                        width: 44,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [
                                _rowBg.withValues(alpha: 0),
                                _rowBg.withValues(alpha: 0.92),
                                _rowBg,
                              ],
                              stops: const [0, 0.45, 1],
                            ),
                          ),
                          child: Center(
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () {
                                  if (!_hScroll.hasClients) return;
                                  final next = (_hScroll.offset +
                                          (_dayColWidth * 2))
                                      .clamp(
                                        0.0,
                                        _hScroll.position.maxScrollExtent,
                                      );
                                  _hScroll.animateTo(
                                    next,
                                    duration: const Duration(milliseconds: 280),
                                    curve: Curves.easeOutCubic,
                                  );
                                },
                                customBorder: const CircleBorder(),
                                child: Container(
                                  width: 30,
                                  height: 30,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _headerBg,
                                    border: Border.all(
                                      color: _checkboxBlue.withValues(
                                        alpha: 0.9,
                                      ),
                                      width: 1.4,
                                    ),
                                  ),
                                  alignment: Alignment.center,
                                  child: Icon(
                                    Icons.arrow_forward_ios_rounded,
                                    size: 13,
                                    color: _checkboxBlue,
                                    weight: 700,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (_canScrollMore)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Icon(
                  Icons.swipe_rounded,
                  size: 16,
                  color: _checkboxBlue.withValues(alpha: 0.95),
                ),
                const SizedBox(width: 6),
                const Text(
                  'Swipe to see all days',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFCAD5E7),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Map<String, bool> _getMapForType(String type) {
    switch (type) {
      case 'fullTime':
        return widget.availability.fullTime;
      case 'partTime':
        return widget.availability.partTime;
      case 'evening':
        return widget.availability.evening;
      case 'night':
        return widget.availability.night;
      case 'onCall':
        return widget.availability.onCall;
      default:
        return {};
    }
  }
}

// INFO BANNER (renamed to avoid conflict with Flutter's Banner widget)
class InfoBanner extends StatelessWidget {
  final String message;
  final String type; // 'info', 'warn', 'success'

  const InfoBanner({super.key, required this.message, this.type = 'info'});

  @override
  Widget build(BuildContext context) {
    Color bg, border, text;
    Gradient? gradient;
    List<BoxShadow>? shadow;

    switch (type) {
      case 'warn':
        bg = AppColors.warnBg;
        border = AppColors.warnBorder;
        text = AppColors.warnText;
        gradient = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.warnBg.withValues(alpha: 0.96),
            AppColors.warnBg.withValues(alpha: 0.88),
          ],
        );
        break;
      case 'success':
        bg = AppColors.successBg;
        border = AppColors.successBorder;
        text = AppColors.successText;
        gradient = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.successBg.withValues(alpha: 0.96),
            AppColors.successBg.withValues(alpha: 0.88),
          ],
        );
        break;
      default:
        bg = const Color(0xFFDBEAFE).withValues(alpha: 0.86);
        border = Colors.white.withValues(alpha: 0.34);
        text = const Color(0xFF1E3A63);
        gradient = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFFEAF3FF).withValues(alpha: 0.95),
            const Color(0xFFD9E9FF).withValues(alpha: 0.90),
          ],
        );
        shadow = [
          BoxShadow(
            color: const Color(0xFF1D4ED8).withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ];
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: bg,
        gradient: gradient,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(18),
        boxShadow: shadow,
      ),
      child: Text(
        message,
        softWrap: true,
        overflow: TextOverflow.visible,
        style: TextStyle(
          color: text,
          fontSize: 14,
          height: 1.55,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

// REVIEW CARD
class ReviewCard extends StatelessWidget {
  final String title;
  final Widget child;

  const ReviewCard({super.key, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

// KEY-VALUE GRID
class KeyValueGrid extends StatelessWidget {
  final Map<String, String> items;

  const KeyValueGrid({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: items.entries.map((e) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 150,
                child: Text(
                  e.key,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF3D4E63),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  e.value,
                  style: const TextStyle(color: AppColors.text),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
