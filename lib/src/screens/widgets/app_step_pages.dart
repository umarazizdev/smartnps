import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:smartnps360/src/screens/models/application_models.dart';
import 'package:smartnps360/src/screens/utilities/sf_time.dart';
import 'package:smartnps360/src/screens/widgets/common_widgets.dart';
import 'package:smartnps360/src/screens/widgets/nps_wizard_theme.dart';

ScrollPhysics _wizardScrollPhysics() {
  return const ClampingScrollPhysics();
}

const String _termsAgreementDescription =
    '''I hereby accept employment with National Protective Service and agree to abide by the rules and regulations of both NPS and any client to which I may be assigned. I will review the NPS Employee Handbook within one week of my hire date and agree to abide by its terms.

1. Employment with NPS is voluntary and at will.
2. Misuse of NPS or client equipment may result in immediate dismissal and reimbursement.
3. No personal calls or disclosure of assigned post phone numbers while on duty.
4. False alarm charges caused by the employee must be paid by the employee.
5. Leaving post before being properly relieved is post abandonment and may result in termination.
6. Reading materials, radios, televisions, games, cards, mobile phones, and other distractions are prohibited while on duty except post orders and related materials.
7. No personal guests on post while on duty.
8. If unable to report, employee must give at least four hours advance notice to the proper supervisor.
9. Leaving only a message is not sufficient call-off notice.
10. Calling off before or after payday, regular days off, holidays, or vacation may require a doctor's note or other documentation.
11. Disciplinary action is at NPS management discretion and employment remains at will.
12. Employee must be well groomed and in full NPS uniform while on duty. Hoodies are prohibited.
13. Employee must not discuss NPS internal matters with clients or others outside NPS management.
14. Employee must immediately notify NPS of any changes to contact or license information.
15. Employees must maintain working voicemail and respond to NPS calls within 24 hours unless told otherwise.
16. NPS does not guarantee permanent work assignments or wages.

The source document also states employees are paid according to the wage allowable by the billing rate for each client, and that on-duty meal periods may be paid when a guard cannot leave the site.''';

final Map<String, bool> _agreementDialogReadState = <String, bool>{};

Future<bool> _showAgreementDescriptionDialog({
  required BuildContext context,
  required String title,
  required Widget content,
}) async {
  final scrollController = ScrollController();
  var hasReachedEnd = false;
  var initialCheckScheduled = false;

  final acknowledged =
      await showDialog<bool>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.63),
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              if (!initialCheckScheduled) {
                initialCheckScheduled = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!scrollController.hasClients) return;
                  final position = scrollController.position;
                  final atEnd = position.maxScrollExtent <= 0;
                  if (atEnd != hasReachedEnd && context.mounted) {
                    setDialogState(() {
                      hasReachedEnd = atEnd;
                    });
                  }
                });
              }

              return Dialog(
                backgroundColor: Colors.transparent,
                elevation: 0,
                insetPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 24,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 860),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: NpsWizardColors.surfaceBorder.withValues(
                            alpha: 0.82,
                          ),
                        ),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: const [
                            NpsWizardColors.panel,
                            NpsWizardColors.panelBottom,
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.32),
                            blurRadius: 30,
                            offset: const Offset(0, 14),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(18, 16, 12, 10),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    title,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  onPressed: () =>
                                      Navigator.of(context).pop(false),
                                  icon: const Icon(
                                    Icons.close,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            height: 1,
                            color: NpsWizardColors.surfaceBorder.withValues(
                              alpha: 0.45,
                            ),
                          ),
                          Flexible(
                            child: NotificationListener<ScrollNotification>(
                              onNotification: (notification) {
                                final metrics = notification.metrics;
                                final atEnd =
                                    metrics.maxScrollExtent <= 0 ||
                                    metrics.pixels >=
                                        metrics.maxScrollExtent - 8;
                                if (atEnd != hasReachedEnd) {
                                  setDialogState(() {
                                    hasReachedEnd = atEnd;
                                  });
                                }
                                return false;
                              },
                              child: SingleChildScrollView(
                                controller: scrollController,
                                padding: const EdgeInsets.fromLTRB(
                                  18,
                                  16,
                                  18,
                                  10,
                                ),
                                child: content,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
                            decoration: BoxDecoration(
                              border: Border(
                                top: BorderSide(
                                  color: NpsWizardColors.surfaceBorder
                                      .withValues(alpha: 0.45),
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    hasReachedEnd
                                        ? 'Reading complete. You can continue.'
                                        : 'Scroll to the bottom to enable Continue.',
                                    style: const TextStyle(
                                      color: NpsWizardColors.secondary,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                ElevatedButton(
                                  onPressed: hasReachedEnd
                                      ? () => Navigator.of(context).pop(true)
                                      : null,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: NpsWizardColors.blueMid,
                                    foregroundColor: Colors.white,
                                    disabledBackgroundColor:
                                        NpsWizardColors.surface,
                                    disabledForegroundColor:
                                        NpsWizardColors.hint,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 18,
                                      vertical: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: const Text(
                                    'Continue',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ) ??
      false;

  scrollController.dispose();
  return acknowledged;
}

Widget _buildAgreementDialogContent({
  required BuildContext context,
  String? content,
  List<AgreementSection>? sections,
}) {
  final linkPattern = RegExp(r'https?://[^\s]+');

  String? extractLink(String value) {
    final match = linkPattern.firstMatch(value);
    return match?.group(0);
  }

  Future<void> copyLink(String link) async {
    await Clipboard.setData(ClipboardData(text: link));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Link copied to clipboard.')),
      );
    }
  }

  Future<void> openLink(String link) async {
    final uri = Uri.tryParse(link);
    if (uri == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Invalid link format.')));
      }
      return;
    }

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Unable to open the link.')));
    }
  }

  final children = <Widget>[];

  if (content != null && content.trim().isNotEmpty) {
    final contentLink = extractLink(content);
    children.addAll([
      const SizedBox(height: 10),
      Text(
        content,
        style: const TextStyle(
          color: NpsWizardColors.heading,
          fontSize: 14,
          height: 1.5,
        ),
      ),
      if (contentLink != null) ...[
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => copyLink(contentLink),
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('Copy Link'),
              style: OutlinedButton.styleFrom(
                foregroundColor: NpsWizardColors.heading,
                side: BorderSide(
                  color: NpsWizardColors.surfaceBorder.withValues(alpha: 0.78),
                ),
              ),
            ),
            ElevatedButton.icon(
              onPressed: () => openLink(contentLink),
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: const Text('Open Link'),
              style: ElevatedButton.styleFrom(
                backgroundColor: NpsWizardColors.blueMid,
                foregroundColor: NpsWizardColors.heading,
              ),
            ),
          ],
        ),
      ],
    ]);
  }

  if (sections != null && sections.isNotEmpty) {
    for (final section in sections) {
      final sectionLink = extractLink(section.content);
      children.addAll([
        const SizedBox(height: 14),
        Text(
          section.title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          section.content,
          style: const TextStyle(
            color: NpsWizardColors.body,
            fontSize: 14,
            height: 1.5,
          ),
        ),
        if (sectionLink != null) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => copyLink(sectionLink),
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Copy Link'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: NpsWizardColors.heading,
                  side: BorderSide(
                    color: NpsWizardColors.surfaceBorder.withValues(
                      alpha: 0.78,
                    ),
                  ),
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => openLink(sectionLink),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text('Open Link'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: NpsWizardColors.blueMid,
                  foregroundColor: NpsWizardColors.heading,
                ),
              ),
            ],
          ),
        ],
      ]);
    }
  }

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: children,
  );
}

class _AgreementDescriptionEntryCard extends StatelessWidget {
  final String title;
  final bool isRead;
  final VoidCallback onOpen;

  const _AgreementDescriptionEntryCard({
    required this.title,
    required this.isRead,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final leadingIcon = Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: const [NpsWizardColors.surface, NpsWizardColors.panel],
        ),
        border: Border.all(
          color: NpsWizardColors.surfaceBorder.withValues(alpha: 0.55),
        ),
      ),
      child: Icon(
        isRead ? Icons.check_circle : Icons.description_outlined,
        color: isRead ? NpsWizardColors.success : NpsWizardColors.inputIcon,
        size: 21,
      ),
    );

    final actionButton = TextButton(
      onPressed: onOpen,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        backgroundColor: NpsWizardColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: NpsWizardColors.surfaceBorder.withValues(alpha: 0.72),
          ),
        ),
      ),
      child: Text(
        isRead ? 'Reopen' : 'View',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: NpsWizardColors.surfaceBorder.withValues(alpha: 0.62),
        ),
        color: NpsWizardColors.surface.withValues(alpha: 0.7),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 440;

          final textColumn = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                isRead
                    ? 'Description reviewed. You can continue.'
                    : 'Open and scroll to the end to enable Next.',
                style: const TextStyle(
                  color: NpsWizardColors.secondary,
                  fontSize: 13,
                ),
              ),
            ],
          );

          if (isCompact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    leadingIcon,
                    const SizedBox(width: 12),
                    Expanded(child: textColumn),
                  ],
                ),
                const SizedBox(height: 12),
                Align(alignment: Alignment.centerRight, child: actionButton),
              ],
            );
          }

          return Row(
            children: [
              leadingIcon,
              const SizedBox(width: 12),
              Expanded(child: textColumn),
              const SizedBox(width: 12),
              actionButton,
            ],
          );
        },
      ),
    );
  }
}

class _KeyboardInsetPadding extends StatelessWidget {
  final Widget child;

  const _KeyboardInsetPadding({required this.child});

  @override
  Widget build(BuildContext context) {
    final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboardHeight),
      child: child,
    );
  }
}

class AppStepPage extends StatelessWidget {
  final ApplicationStep step;
  final UserAccount user;
  final VoidCallback onSave;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final bool isFirstPage;
  final bool isLastPage;
  final VoidCallback updateState;
  final VoidCallback? onGoThroughIncompleteSteps;

  const AppStepPage({
    super.key,
    required this.step,
    required this.user,
    required this.onSave,
    required this.onNext,
    required this.onPrevious,
    required this.isFirstPage,
    required this.isLastPage,
    required this.updateState,
    this.onGoThroughIncompleteSteps,
  });

  @override
  Widget build(BuildContext context) {
    switch (step.id) {
      case 'profile':
        return ProfilePage(
          user: user,
          step: step,
          onSave: onSave,
          onNext: onNext,
          onPrevious: onPrevious,
          isFirstPage: isFirstPage,
          isLastPage: isLastPage,
          updateState: updateState,
        );
      case 'terms':
        return TermsPage(
          user: user,
          step: step,
          onSave: onSave,
          onNext: onNext,
          onPrevious: onPrevious,
          isFirstPage: isFirstPage,
          isLastPage: isLastPage,
          updateState: updateState,
        );
      case 'review':
        return ReviewPage(
          user: user,
          step: step,
          onSave: onSave,
          onNext: onNext,
          onPrevious: onPrevious,
          isFirstPage: isFirstPage,
          isLastPage: isLastPage,
          updateState: updateState,
          onGoThroughIncompleteSteps: onGoThroughIncompleteSteps,
        );

      default:
        return AgreementPage(
          user: user,
          step: step,
          onSave: onSave,
          onNext: onNext,
          onPrevious: onPrevious,
          isFirstPage: isFirstPage,
          isLastPage: isLastPage,
          updateState: updateState,
        );
    }
  }
}

class ProfilePage extends StatefulWidget {
  final UserAccount user;
  final ApplicationStep step;
  final VoidCallback onSave;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final bool isFirstPage;
  final bool isLastPage;
  final VoidCallback updateState;

  const ProfilePage({
    super.key,
    required this.user,
    required this.step,
    required this.onSave,
    required this.onNext,
    required this.onPrevious,
    required this.isFirstPage,
    required this.isLastPage,
    required this.updateState,
  });

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _formKey = GlobalKey<FormState>();

  void _handleFieldChange() {
    widget.onSave();
  }

  DateTime _parseDateOrFallback(String value, DateTime fallback) {
    if (value.isEmpty) return fallback;

    final formats = [
      DateFormat('MM/dd/yyyy'),
      DateFormat('dd/MM/yyyy'),
      DateFormat('yyyy-MM-dd'),
    ];

    for (final format in formats) {
      try {
        return format.parseStrict(value);
      } catch (_) {}
    }

    return fallback;
  }

  Future<void> _pickDate({
    required String currentValue,
    required ValueChanged<String> onPicked,
    required DateTime firstDate,
    required DateTime lastDate,
  }) async {
    var initialDate = _parseDateOrFallback(currentValue, sfNow());

    if (initialDate.isBefore(firstDate)) {
      initialDate = firstDate;
    }

    if (initialDate.isAfter(lastDate)) {
      initialDate = lastDate;
    }

    final bool isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

    DateTime? pickedDate;

    if (isIOS) {
      DateTime tempPicked = initialDate;

      pickedDate = await showCupertinoModalPopup<DateTime>(
        context: context,
        builder: (context) {
          return Container(
            height: 320,
            decoration: BoxDecoration(
              color: NpsWizardColors.panel,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: () => Navigator.pop(context),
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                              color: NpsWizardColors.secondary,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Text(
                          'Select Date',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: NpsWizardColors.heading,
                          ),
                        ),
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: () => Navigator.pop(context, tempPicked),
                          child: const Text(
                            'Done',
                            style: TextStyle(
                              color: NpsWizardColors.focusedBorder,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: NpsWizardColors.surfaceBorder),
                  Expanded(
                    child: CupertinoTheme(
                      data: const CupertinoThemeData(
                        brightness: Brightness.dark,
                        primaryColor: NpsWizardColors.focusedBorder,
                      ),
                      child: CupertinoDatePicker(
                        mode: CupertinoDatePickerMode.date,
                        initialDateTime: initialDate,
                        minimumDate: firstDate,
                        maximumDate: lastDate,
                        onDateTimeChanged: (DateTime value) {
                          tempPicked = value;
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } else {
      pickedDate = await showDatePicker(
        context: context,
        initialDate: initialDate,
        firstDate: firstDate,
        lastDate: lastDate,
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: const ColorScheme.dark(
                primary: NpsWizardColors.blueMid,
                surface: NpsWizardColors.panel,
                onSurface: NpsWizardColors.heading,
              ),
              textButtonTheme: TextButtonThemeData(
                style: TextButton.styleFrom(
                  foregroundColor: NpsWizardColors.focusedBorder,
                ),
              ),
              dialogTheme: DialogThemeData(
                backgroundColor: NpsWizardColors.panel,
              ),
            ),
            child: child!,
          );
        },
      );
    }

    if (pickedDate != null) {
      final formatted = DateFormat('MM/dd/yyyy').format(pickedDate);

      if (formatted != currentValue) {
        onPicked(formatted);
        _handleFieldChange();

        if (mounted) {
          setState(() {});
        }
      }
    }
  }

  Widget _buildDatePickerField({
    required String label,
    required String value,
    required ValueChanged<String> onPicked,
    required DateTime firstDate,
    required DateTime lastDate,
    String hint = 'MM/dd/yyyy',
  }) {
    final displayHint = '$label ($hint)';

    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        _pickDate(
          currentValue: value,
          onPicked: onPicked,
          firstDate: firstDate,
          lastDate: lastDate,
        );
      },
      child: AbsorbPointer(
        child: AppTextField(
          label: label,
          initialValue: value,
          hint: displayHint,
        ),
      ),
    );
  }

  Widget _buildYesNoQuestion({
    required String label,
    required String value,
    required ValueChanged<String> onChanged,
  }) {
    Widget option({required String label, required String optionValue}) {
      final selected = value == optionValue;

      return InkWell(
        onTap: () {
          if (selected) return;
          onChanged(optionValue);
          _handleFieldChange();
          setState(() {});
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IgnorePointer(
              child: Checkbox(
                value: selected,
                onChanged: (_) {},
                activeColor: NpsWizardColors.blueMid,
                checkColor: Colors.white,
                side: BorderSide(color: NpsWizardColors.surfaceBorder),
              ),
            ),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            option(label: 'YES', optionValue: 'yes'),
            option(label: 'NO', optionValue: 'no'),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.user.application.profile;
    final availability = widget.user.application.availability;
    final isSmall = MediaQuery.sizeOf(context).width < 900;

    Widget twoCol(Widget left, Widget right) {
      if (isSmall) {
        return Column(children: [left, const SizedBox(height: 14), right]);
      }
      return Row(
        children: [
          Expanded(child: left),
          const SizedBox(width: 14),
          Expanded(child: right),
        ],
      );
    }

    Widget threeCol(Widget a, Widget b, Widget c) {
      if (isSmall) {
        return Column(
          children: [
            a,
            const SizedBox(height: 14),
            b,
            const SizedBox(height: 14),
            c,
          ],
        );
      }
      return Row(
        children: [
          Expanded(child: a),
          const SizedBox(width: 14),
          Expanded(child: b),
          const SizedBox(width: 14),
          Expanded(child: c),
        ],
      );
    }

    return Form(
      key: _formKey,
      child: _KeyboardInsetPadding(
        child: SingleChildScrollView(
          physics: _wizardScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RepaintBoundary(
                child: PageHeader(
                  step: widget.step,
                  stepNumber: 1,
                  totalSteps: applicationSteps.length,
                  lastSaved: widget.user.application.lastSavedAt,
                ),
              ),
              const SizedBox(height: 18),

              const SectionTitle('Applicant information'),
              const SizedBox(height: 14),

              threeCol(
                AppTextField(
                  label: 'Last Name',
                  initialValue: profile.lastName,
                  required: true,
                  onChanged: (v) {
                    profile.lastName = v;
                    _handleFieldChange();
                  },
                ),
                AppTextField(
                  label: 'First Name',
                  initialValue: profile.firstName,
                  required: true,
                  onChanged: (v) {
                    profile.firstName = v;
                    _handleFieldChange();
                  },
                ),
                AppTextField(
                  label: 'M.I.',
                  initialValue: profile.middleInitial,
                  onChanged: (v) {
                    profile.middleInitial = v;
                    _handleFieldChange();
                  },
                ),
              ),
              const SizedBox(height: 14),

              twoCol(
                AppTextField(
                  label: 'Street Address',
                  initialValue: profile.street,
                  onChanged: (v) {
                    profile.street = v;
                    _handleFieldChange();
                  },
                ),
                AppTextField(
                  label: 'Apartment / Unit #',
                  initialValue: profile.apartment,
                  onChanged: (v) {
                    profile.apartment = v;
                    _handleFieldChange();
                  },
                ),
              ),
              const SizedBox(height: 14),

              threeCol(
                AppTextField(
                  label: 'City',
                  initialValue: profile.city,
                  onChanged: (v) {
                    profile.city = v;
                    _handleFieldChange();
                  },
                ),
                AppTextField(
                  label: 'State',
                  initialValue: profile.state,
                  onChanged: (v) {
                    profile.state = v;
                    _handleFieldChange();
                  },
                ),
                AppTextField(
                  label: 'ZIP',
                  initialValue: profile.zip,
                  onChanged: (v) {
                    profile.zip = v;
                    _handleFieldChange();
                  },
                ),
              ),
              const SizedBox(height: 14),

              twoCol(
                AppTextField(
                  label: 'Phone',
                  initialValue: profile.phone,
                  required: true,
                  keyboardType: TextInputType.phone,
                  onChanged: (v) {
                    profile.phone = v;
                    _handleFieldChange();
                  },
                ),
                AppTextField(
                  label: 'Email Address',
                  initialValue: profile.email,
                  required: true,
                  keyboardType: TextInputType.emailAddress,
                  onChanged: (v) {
                    profile.email = v;
                    _handleFieldChange();
                  },
                ),
              ),
              const SizedBox(height: 14),

              twoCol(
                AppTextField(
                  label: 'Driver License #',
                  initialValue: profile.driversLicense,
                  onChanged: (v) {
                    profile.driversLicense = v;
                    _handleFieldChange();
                  },
                ),
                AppTextField(
                  label: 'Social Security No.',
                  initialValue: profile.ssn,
                  onChanged: (v) {
                    profile.ssn = v;
                    _handleFieldChange();
                  },
                ),
              ),
              const SizedBox(height: 14),

              threeCol(
                _buildDatePickerField(
                  label: 'DOB',
                  value: profile.dob,
                  hint: 'MM/dd/yyyy',
                  firstDate: DateTime(1900),
                  lastDate: sfNow(),
                  onPicked: (v) => profile.dob = v,
                ),
                AppTextField(
                  label: 'Hair Color',
                  initialValue: profile.hairColor,
                  onChanged: (v) {
                    profile.hairColor = v;
                    _handleFieldChange();
                  },
                ),
                AppTextField(
                  label: 'Eye Color',
                  initialValue: profile.eyeColor,
                  onChanged: (v) {
                    profile.eyeColor = v;
                    _handleFieldChange();
                  },
                ),
              ),
              const SizedBox(height: 14),

              twoCol(
                AppTextField(
                  label: 'Height',
                  initialValue: profile.height,
                  onChanged: (v) {
                    profile.height = v;
                    _handleFieldChange();
                  },
                ),
                AppTextField(
                  label: 'Weight',
                  initialValue: profile.weight,
                  onChanged: (v) {
                    profile.weight = v;
                    _handleFieldChange();
                  },
                ),
              ),
              const SizedBox(height: 18),

              _buildYesNoQuestion(
                label: 'Are you a citizen of the United States?',
                value: profile.citizen,
                onChanged: (v) => profile.citizen = v,
              ),
              const SizedBox(height: 14),

              _buildYesNoQuestion(
                label: 'If no, are you authorized to work in the U.S.?',
                value: profile.authorizedToWork,
                onChanged: (v) => profile.authorizedToWork = v,
              ),
              const SizedBox(height: 14),

              _buildYesNoQuestion(
                label: 'Have you ever worked for this company?',
                value: profile.workedBefore,
                onChanged: (v) => profile.workedBefore = v,
              ),
              if (profile.workedBefore == 'yes') ...[
                const SizedBox(height: 12),
                _buildDatePickerField(
                  label: 'If so, when?',
                  value: profile.workedBeforeWhen,
                  firstDate: DateTime(1900),
                  lastDate: sfNow(),
                  onPicked: (v) => profile.workedBeforeWhen = v,
                ),
              ],
              const SizedBox(height: 14),

              _buildYesNoQuestion(
                label: 'Have you ever been convicted of a felony?',
                value: profile.felony,
                onChanged: (v) => profile.felony = v,
              ),
              if (profile.felony == 'yes') ...[
                const SizedBox(height: 12),
                AppTextField(
                  label: 'If yes, explain',
                  initialValue: profile.felonyExplain,
                  maxLines: 3,
                  onChanged: (v) {
                    profile.felonyExplain = v;
                    _handleFieldChange();
                  },
                ),
              ],
              const SizedBox(height: 14),

              _buildYesNoQuestion(
                label: 'Have you ever worked under another name?',
                value: profile.otherName,
                onChanged: (v) => profile.otherName = v,
              ),
              if (profile.otherName == 'yes') ...[
                const SizedBox(height: 12),
                AppTextField(
                  label: 'If yes, explain',
                  initialValue: profile.otherNameExplain,
                  maxLines: 2,
                  onChanged: (v) {
                    profile.otherNameExplain = v;
                    _handleFieldChange();
                  },
                ),
              ],
              const SizedBox(height: 18),

              const SectionTitle('Most recent employment'),
              const SizedBox(height: 12),
              AppTextField(
                label: 'Employment details',
                initialValue: profile.recentEmployment,
                maxLines: 2,
                onChanged: (v) {
                  profile.recentEmployment = v;
                  _handleFieldChange();
                },
              ),
              const SizedBox(height: 14),
              twoCol(
                AppTextField(
                  label: 'Company',
                  initialValue: profile.recentCompany,
                  onChanged: (v) {
                    profile.recentCompany = v;
                    _handleFieldChange();
                  },
                ),
                AppTextField(
                  label: 'Phone',
                  initialValue: profile.recentPhone,
                  keyboardType: TextInputType.phone,
                  onChanged: (v) {
                    profile.recentPhone = v;
                    _handleFieldChange();
                  },
                ),
              ),
              const SizedBox(height: 14),
              twoCol(
                AppTextField(
                  label: 'Address',
                  initialValue: profile.recentAddress,
                  onChanged: (v) {
                    profile.recentAddress = v;
                    _handleFieldChange();
                  },
                ),
                AppTextField(
                  label: 'Job Title',
                  initialValue: profile.recentJobTitle,
                  onChanged: (v) {
                    profile.recentJobTitle = v;
                    _handleFieldChange();
                  },
                ),
              ),
              const SizedBox(height: 18),

              const SectionTitle('Work availability'),
              const SectionSubtitle('Mark all that apply for each day.'),
              const SizedBox(height: 12),
              AvailabilityGrid(
                availability: availability,
                onChanged: _handleFieldChange,
              ),

              const SizedBox(height: 18),
              const SectionTitle('Emergency contact'),
              const SizedBox(height: 12),
              twoCol(
                AppTextField(
                  label: 'Emergency Contact Name',
                  initialValue: profile.emergencyName,
                  onChanged: (v) {
                    profile.emergencyName = v;
                    _handleFieldChange();
                  },
                ),
                AppTextField(
                  label: 'Relationship',
                  initialValue: profile.emergencyRelationship,
                  onChanged: (v) {
                    profile.emergencyRelationship = v;
                    _handleFieldChange();
                  },
                ),
              ),
              const SizedBox(height: 14),
              twoCol(
                AppTextField(
                  label: 'Phone',
                  initialValue: profile.emergencyPhone,
                  keyboardType: TextInputType.phone,
                  onChanged: (v) {
                    profile.emergencyPhone = v;
                    _handleFieldChange();
                  },
                ),
                AppTextField(
                  label: 'Alternate Phone',
                  initialValue: profile.emergencyAltPhone,
                  keyboardType: TextInputType.phone,
                  onChanged: (v) {
                    profile.emergencyAltPhone = v;
                    _handleFieldChange();
                  },
                ),
              ),

              const SizedBox(height: 18),
              const SectionTitle('Permit information'),
              const SizedBox(height: 12),
              twoCol(
                AppTextField(
                  label: 'California Guard #',
                  initialValue: profile.guardCard,
                  onChanged: (v) {
                    profile.guardCard = v;
                    _handleFieldChange();
                  },
                ),
                _buildDatePickerField(
                  label: 'Guard Card Expiration Date',
                  value: profile.guardCardExpiry,
                  hint: 'MM/dd/yyyy',
                  firstDate: DateTime(1900),
                  lastDate: DateTime(2100),
                  onPicked: (v) => profile.guardCardExpiry = v,
                ),
              ),
              const SizedBox(height: 14),
              twoCol(
                AppTextField(
                  label: 'California Exposed Firearm Permit #',
                  initialValue: profile.firearmPermit,
                  onChanged: (v) {
                    profile.firearmPermit = v;
                    _handleFieldChange();
                  },
                ),
                _buildDatePickerField(
                  label: 'Firearm Permit Expiration Date',
                  value: profile.firearmPermitExpiry,
                  hint: 'MM/dd/yyyy',
                  firstDate: DateTime(1900),
                  lastDate: DateTime(2100),
                  onPicked: (v) => profile.firearmPermitExpiry = v,
                ),
              ),

              const SizedBox(height: 20),
              SignatureBlock(
                title: 'Employment Application Signature',
                signatureKey: 'profile',
                signature: widget.user.application.signatures['profile'],
                onSign: (signature) {
                  widget.user.application.signatures['profile'] = signature;
                  widget.updateState();
                  widget.onSave();
                },
              ),

              const SizedBox(height: 22),
              RepaintBoundary(
                child: PageNavigation(
                  onPrevious: widget.onPrevious,
                  onNext: widget.onNext,
                  onSave: widget.onSave,
                  isFirstPage: widget.isFirstPage,
                  isLastPage: widget.isLastPage,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TermsPage extends StatefulWidget {
  final UserAccount user;
  final ApplicationStep step;
  final VoidCallback onSave;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final bool isFirstPage;
  final bool isLastPage;
  final VoidCallback updateState;

  const TermsPage({
    super.key,
    required this.user,
    required this.step,
    required this.onSave,
    required this.onNext,
    required this.onPrevious,
    required this.isFirstPage,
    required this.isLastPage,
    required this.updateState,
  });

  @override
  State<TermsPage> createState() => _TermsPageState();
}

class _TermsPageState extends State<TermsPage> {
  Future<void> _openTermsDescriptionDialog() async {
    final acknowledged = await _showAgreementDescriptionDialog(
      context: context,
      title: 'Agreement and Terms of Employment',
      content: _buildAgreementDialogContent(
        context: context,
        content: _termsAgreementDescription,
      ),
    );

    if (acknowledged && mounted) {
      setState(() {
        _agreementDialogReadState['terms'] = true;
      });
      widget.onSave();
    }
  }

  @override
  Widget build(BuildContext context) {
    final agreements = widget.user.application.agreements;
    final hasReadTermsAgreement = _agreementDialogReadState['terms'] ?? false;

    return _KeyboardInsetPadding(
      child: SingleChildScrollView(
        physics: _wizardScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RepaintBoundary(
              child: PageHeader(
                step: widget.step,
                stepNumber: 2,
                totalSteps: applicationSteps.length,
                lastSaved: widget.user.application.lastSavedAt,
              ),
            ),
            const SizedBox(height: 18),

            RepaintBoundary(
              child: _AgreementDescriptionEntryCard(
                title: 'Agreement and Terms Description',
                isRead: hasReadTermsAgreement,
                onOpen: _openTermsDescriptionDialog,
              ),
            ),

            const SizedBox(height: 18),
            AppTextField(
              label: 'Base rate per hour (\$)',
              initialValue: agreements.baseRate,
              required: true,
              keyboardType: TextInputType.number,
              onChanged: (v) {
                agreements.baseRate = v;
                widget.onSave();
              },
            ),

            const SizedBox(height: 18),
            SignatureBlock(
              title: 'Agreement & Terms Signature',
              signatureKey: 'terms',
              signature: widget.user.application.signatures['terms'],
              onSign: (signature) {
                widget.user.application.signatures['terms'] = signature;
                widget.updateState();
                widget.onSave();
              },
            ),

            const SizedBox(height: 22),
            RepaintBoundary(
              child: PageNavigation(
                onPrevious: widget.onPrevious,
                onNext: widget.onNext,
                onSave: widget.onSave,
                isFirstPage: widget.isFirstPage,
                isLastPage: widget.isLastPage,
                canProceed: hasReadTermsAgreement,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AgreementPage extends StatelessWidget {
  final UserAccount user;
  final ApplicationStep step;
  final VoidCallback onSave;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final bool isFirstPage;
  final bool isLastPage;
  final VoidCallback updateState;

  const AgreementPage({
    super.key,
    required this.user,
    required this.step,
    required this.onSave,
    required this.onNext,
    required this.onPrevious,
    required this.isFirstPage,
    required this.isLastPage,
    required this.updateState,
  });

  @override
  Widget build(BuildContext context) {
    final stepData = _getStepData(step.id);
    final hasReadAgreement = _agreementDialogReadState[step.id] ?? false;

    Future<void> openAgreementDescriptionDialog() async {
      final acknowledged = await _showAgreementDescriptionDialog(
        context: context,
        title: stepData['title'] ?? step.title,
        content: _buildAgreementDialogContent(
          context: context,
          content: stepData['content'],
          sections: (stepData['sections'] as List<AgreementSection>?),
        ),
      );

      if (acknowledged) {
        _agreementDialogReadState[step.id] = true;
        updateState();
        onSave();
      }
    }

    return _KeyboardInsetPadding(
      child: SingleChildScrollView(
        physics: _wizardScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RepaintBoundary(
              child: PageHeader(
                step: step,
                stepNumber:
                    applicationSteps.indexWhere((s) => s.id == step.id) + 1,
                totalSteps: applicationSteps.length,
                lastSaved: user.application.lastSavedAt,
              ),
            ),
            const SizedBox(height: 18),

            if (stepData['banner'] != null)
              InfoBanner(
                message: stepData['banner'],
                type: stepData['bannerType'] ?? 'info',
              ),

            if (stepData['banner'] != null) const SizedBox(height: 16),

            RepaintBoundary(
              child: _AgreementDescriptionEntryCard(
                title: '${step.title} Description',
                isRead: hasReadAgreement,
                onOpen: openAgreementDescriptionDialog,
              ),
            ),

            if (stepData['additionalFields'] != null)
              ..._buildAdditionalFields(stepData['additionalFields']),

            if (stepData['showSignature'] != false) ...[
              const SizedBox(height: 18),
              SignatureBlock(
                title: '${step.title} Signature',
                signatureKey: stepData['signatureKey'],
                signature:
                    user.application.signatures[stepData['signatureKey']],
                onSign: (signature) {
                  user.application.signatures[stepData['signatureKey']] =
                      signature;
                  updateState();
                  onSave();
                },
              ),
            ],

            const SizedBox(height: 22),
            RepaintBoundary(
              child: PageNavigation(
                onPrevious: onPrevious,
                onNext: onNext,
                onSave: onSave,
                isFirstPage: isFirstPage,
                isLastPage: isLastPage,
                canProceed: hasReadAgreement,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Map<String, dynamic> _getStepData(String stepId) {
    final data = {
      'arbitration': {
        'title': 'At-Will Employment and Binding Arbitration Agreement',
        'content':
            'The uploaded agreement states employment and compensation may be terminated by the company or employee at any time, with or without cause or notice, and that covered employment-related disputes are subject to binding arbitration instead of court, except for matters like workers\' compensation, unemployment insurance, state or federal disability insurance claims, and certain agency proceedings. It also states there is no right to bring claims as a class, collective, representative, or private attorney general action in arbitration, unless a final court ruling makes that waiver unenforceable and such claims must then proceed in court. The employee and company both give up the right to jury trial by signing the agreement.\n\nFor readability, this page summarizes the long legal language. The printed application still keeps the acknowledgment record with signature, date, timestamp, and device details.',
        'signatureKey': 'arbitrationEmployee',
      },
      'eeo': {
        'title':
            'Equal Employment Opportunity, Zero Tolerance for Harassment, Discrimination and Retaliation',
        'content':
            'The uploaded policy says NPS is committed to equal employment opportunity and a work environment free from discrimination, harassment, and retaliation. It applies to employees, supervisors, clients, vendors, contractors, and visitors. It states employees must report illegal discrimination, harassment, or retaliation to a supervisor, manager, or Human Resources. It also explains investigation procedures, examples of verbal, physical, and visual harassment, and states that violations may lead to discipline up to immediate termination.\n\nThe original form includes acknowledgment of the investigation process, examples of harassment, sexual harassment language, and a final statement that discrimination, harassment, or retaliation in any form is prohibited.',
        'signatureKey': 'eeo',
      },
      'noncompete': {
        'sections': [
          AgreementSection(
            title: 'Non-Competitive Agreement',
            content:
                'The uploaded page states that for two years after separation from NPS, the employee will not contact any NPS client company of record, or any company that was a client during employment, for the purpose of inducing them to change security services. It also says the employee will not divulge client names or contacts for solicitation purposes.',
          ),
          AgreementSection(
            title: "Driver's Agreement - Company Vehicle",
            content:
                'The same page states that a driver of a company leased, owned, or rented vehicle is responsible for damages resulting from negligence and may not permit unauthorized persons to operate the vehicle. The paper form includes a Not Applicable box.',
          ),
        ],
        'additionalFields': [
          {
            'type': 'checkbox',
            'field': 'driverNotApplicable',
            'title': 'Driver agreement not applicable',
            'subtitle':
                'Check this if you will not be assigned as a company vehicle driver.',
          },
        ],
        'signatureKey': 'noncompete',
      },
      'release': {
        'title': 'Security Officer Notification and Release',
        'content':
            'The uploaded form states that in connection with application for employment, a consumer report may be requested and may include previous employers, reasons for termination, work experience, driving record, workers\' compensation claims, credit, bankruptcy proceedings, criminal records, and other public record information. It authorizes parties or agencies contacted by NPS to furnish that information and explains the employee\'s right to request information about the report from the agency.',
        'additionalFields': [
          {
            'type': 'text',
            'field': 'profile.ssn',
            'label': 'Social Security Number (SSN#)',
            'required': true,
          },
        ],
        'signatureKey': 'release',
      },
      'pay': {
        'title': 'Pay System and Pay Schedule',
        'content':
            'The uploaded pay page says payday is every Friday on a weekly schedule, subject to earlier paydays when holidays apply. It states the pay period runs from 12:01 AM Sunday through midnight Saturday, and the payday is the Friday following the Saturday when the pay period ended. It also reminds employees that they must sign in with their name and hours on the timesheet so the client can be billed and the employee can be paid.',
        'signatureKey': 'pay',
      },
      'uniformReceipt': {
        'title': 'Uniform Issue / Return Receipt',
        'content':
            'The source form lists uniform items such as NPS cap, bomber jacket, shirts, windbreaker, badge, slacks, black suit, blazer, ties, handcuffs and case, mase and case, rain gear, BDU pants, flashlight, and misc. Uniforms remain company property and the paper form says final pay is contingent on returning items in clean and serviceable condition.',
        'displayType': 'info',
        'infoType': 'info',
        'additionalFields': [
          {'type': 'uniformReceiptGrid'},
        ],
        'signatureKey': 'uniformReceipt',
      },
      'uniformStandards': {
        'title': 'Uniform Standards',
        'content':
            '• Clean shaven face, subject to supervisor or client discretion\n'
            '• Professional hairstyle, nothing extreme\n'
            '• Clean and ironed shirt with NPS patches only\n'
            '• Black or navy undershirt only\n'
            '• Plain belt or duty belt buckle only\n'
            '• Clean and ironed tailored pants in the right length with proper creases\n'
            '• Pants and shirts must fit properly and look professional, with no sagging\n'
            '• Jackets must be correct size with NPS patches only\n'
            '• Clean black shoes and black socks only\n'
            '• Badge must be worn on the shirt or jacket that is on top',
        'signatureKey': 'uniformStandards',
      },
      'tattoos': {
        'title': 'Visible Tattoos',
        'content':
            'The uploaded page says NPS grooming standards do not allow the display of large tattoos. Such tattoos must be covered by the uniform, cosmetics, or other suitable means while on duty. The sample paper form specifically mentions skull tattoos on both hands and says cosmetics used to cover tattoos must be visually unobtrusive and approximate the appearance of the employee\'s skin.',
        'additionalFields': [
          {
            'type': 'checkbox',
            'field': 'tattooNotApplicable',
            'title': 'Not applicable',
            'subtitle':
                'Check this if the tattoo coverage policy is not applicable to you.',
          },
        ],
        'signatureKey': 'tattoos',
      },
      'offDuty': {
        'title': 'Uniform While Off-Duty',
        'content':
            'The uploaded page states that off-duty officers still in uniform may reflect on the company, and therefore NPS requires removal or full covering of uniform items with NPS-specific identifiers such as jackets, shirts, caps, patches, and badges while off duty. The simplest option given is a light jacket fully covering the patches and badge. Violations may lead to discipline up to termination.',
        'signatureKey': 'offDuty',
      },
      'mealGuide': {
        'title': 'Guide to Lunch Break / Meal Periods',
        'content':
            'The uploaded guide says 0 to 5 hours worked requires 0 meal periods, 6 to 10 hours requires 1 meal period, and 11 to 16 hours requires 2 meal periods. It notes 30 minutes minimum, before the start of the 6th hour, and says meal periods cannot be combined with rest periods or used for arriving late or leaving early.\n\nThe page also says that because of the nature of security work, an on-duty meal period may sometimes be necessary when work prevents an employee from being relieved of all duty and the employee must remain on assigned post. It says an employee can revoke this agreement in writing to Human Resources, but in some cases revoking it may disqualify the employee from continued employment.',
        'additionalFields': [
          {
            'type': 'agreementChoiceCheckbox',
            'field': 'mealGuideAgree',
            'value': 'agree',
            'title': 'I agree to these terms',
          },
          {
            'type': 'agreementChoiceCheckbox',
            'field': 'mealGuideAgree',
            'value': 'disagree',
            'title': 'I do not agree to these terms',
          },
        ],
        'signatureKey': 'mealGuide',
      },
      'mealAgreement': {
        'sections': [
          AgreementSection(
            title: 'Agreement for On-Duty Meal Period',
            content:
                'The uploaded page explains California meal period law, says on-duty meal periods are only permitted when the nature of the work prevents the employee from being relieved of all duty, both employer and employee sign a written agreement, and the employee is paid for the on-duty meal period. It also states employees are not required to agree to an on-duty meal period and signing it is not a condition of employment, although the company may not always have open posts that allow an off-duty meal period. The page also states either the employee or the company may revoke the agreement in writing at any time.',
          ),
          AgreementSection(
            title: 'Rest Break Notice',
            content:
                'The uploaded page states rest breaks must be provided at the rate of 10 consecutive minutes for each four hours or major portion thereof worked, as near as possible to the middle of the work period. Rest breaks may not be combined with meal breaks or used to come late or leave early. It says National Protective Service pays employees for the on-duty meal break and rest breaks and expects the employee to remain on site during these breaks.',
          ),
        ],
        'signatureKey': 'mealAgreement',
      },
      'expectations': {
        'title': 'Expectations from Employees',
        'content':
            'The checklist in the uploaded application includes a final page called Expectations from the employees on page 19. The uploaded snippets do not provide the full body text for that page, so this step captures a clear final acknowledgment that the applicant understands the expected standards and instructions covered throughout the application.',
        'displayType': 'info',
        'infoType': 'info',
        'additionalFields': [
          {'type': 'expectationsChecklist'},
          {'type': 'expectationsFinalNotes'},
        ],
        'signatureKey': 'expectations',
      },
      'w4': {
        'title': 'W-4 Form (Federal Withholding Form)',
        'banner':
            'Employees are required to complete a current IRS Form W-4 (Employee\'s Withholding Certificate) as part of the onboarding process.',
        'bannerType': 'info',
        'sections': [
          AgreementSection(
            title: 'Official IRS Form Link',
            content:
                'You may download and complete the form using the official IRS link below:\nhttps://www.irs.gov/pub/irs-pdf/fw4.pdf\n\nOnce completed, please submit the signed form to your supervisor, manager, or HR representative.',
          ),
          AgreementSection(
            title: 'Important Notice',
            content:
                'This link is provided for convenience only and directs to the official IRS website. It is the employee\'s responsibility to ensure the form is completed accurately. National Protective Service does not provide tax advice. Employees are encouraged to consult a tax professional or the IRS directly if they have any questions regarding withholding.\n\nCompletion and submission of the W-4 form is required prior to or at the start of employment. Failure to provide a completed form may result in default withholding in accordance with IRS guidelines.',
          ),
        ],
        'showSignature': false,
        'signatureKey': 'w4',
      },
    };

    return data[stepId] ??
        {
          'title': step.title,
          'content': 'Agreement content for ${step.title}',
          'signatureKey': stepId,
        };
  }

  List<Widget> _buildAdditionalFields(List<Map<String, dynamic>> fields) {
    return fields.map((field) {
      if (field['type'] == 'text' && field['field'] == 'profile.ssn') {
        return Padding(
          padding: const EdgeInsets.only(top: 14),
          child: AppTextField(
            label: field['label'] ?? 'Social Security Number (SSN#)',
            initialValue: user.application.profile.ssn,
            required: field['required'] == true,
            onChanged: (value) {
              user.application.profile.ssn = value;
              updateState();
              onSave();
            },
          ),
        );
      }

      if (field['type'] == 'checkbox' &&
          field['field'] == 'driverNotApplicable') {
        return Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: NpsWizardColors.surface.withValues(alpha: 0.84),
              border: Border.all(
                color: NpsWizardColors.surfaceBorder.withValues(alpha: 0.70),
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Transform.scale(
                  scale: 1.04,
                  child: Checkbox(
                    value: user.application.agreements.driverNotApplicable,
                    onChanged: (value) {
                      user.application.agreements.driverNotApplicable =
                          value ?? false;
                      updateState();
                      onSave();
                    },
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    side: BorderSide(
                      color: NpsWizardColors.secondary,
                      width: 1.5,
                    ),
                    checkColor: Colors.white,
                    fillColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) {
                        return NpsWizardColors.blueMid;
                      }
                      return NpsWizardColors.surface;
                    }),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        field['title'] ?? 'Not applicable',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: NpsWizardColors.heading,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        field['subtitle'] ?? '',
                        style: const TextStyle(
                          fontSize: 14,
                          color: NpsWizardColors.body,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }

      if (field['type'] == 'checkbox' &&
          field['field'] == 'tattooNotApplicable') {
        return Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: NpsWizardColors.surface.withValues(alpha: 0.84),
              border: Border.all(
                color: NpsWizardColors.surfaceBorder.withValues(alpha: 0.70),
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Transform.scale(
                  scale: 1.04,
                  child: Checkbox(
                    value: user.application.agreements.tattooNotApplicable,
                    onChanged: (value) {
                      user.application.agreements.tattooNotApplicable =
                          value ?? false;
                      updateState();
                      onSave();
                    },
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    side: BorderSide(
                      color: NpsWizardColors.secondary,
                      width: 1.5,
                    ),
                    checkColor: Colors.white,
                    fillColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) {
                        return NpsWizardColors.blueMid;
                      }
                      return NpsWizardColors.surface;
                    }),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        field['title'] ?? 'Not applicable',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: NpsWizardColors.heading,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        field['subtitle'] ?? '',
                        style: const TextStyle(
                          fontSize: 14,
                          color: NpsWizardColors.body,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }

      if (field['type'] == 'agreementChoiceCheckbox' &&
          field['field'] == 'mealGuideAgree') {
        final optionValue = (field['value'] ?? '').toString();

        return Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: NpsWizardColors.surface.withValues(alpha: 0.84),
              border: Border.all(
                color: NpsWizardColors.surfaceBorder.withValues(alpha: 0.70),
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Checkbox(
                  value:
                      user.application.agreements.mealGuideAgree == optionValue,
                  onChanged: (value) {
                    user.application.agreements.mealGuideAgree = value == true
                        ? optionValue
                        : '';
                    updateState();
                    onSave();
                  },
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  side: BorderSide(
                    color: NpsWizardColors.secondary,
                    width: 1.5,
                  ),
                  checkColor: Colors.white,
                  fillColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return NpsWizardColors.blueMid;
                    }
                    return NpsWizardColors.surface;
                  }),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    field['title'] ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.left,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: NpsWizardColors.heading,
                      height: 1.25,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }

      if (field['type'] == 'expectationsChecklist') {
        final checklistItems = [
          {
            'title': 'I understand company policies and site instructions',
            'subtitle':
                'I understand I must follow NPS policies, post orders, and client rules.',
            'value': user.application.expectations.understandsPolicies,
            'onChanged': (bool value) {
              user.application.expectations.understandsPolicies = value;
            },
          },
          {
            'title': 'I understand reporting expectations',
            'subtitle':
                'I understand I must report incidents, schedule issues, and important changes honestly and promptly.',
            'value': user.application.expectations.understandsReporting,
            'onChanged': (bool value) {
              user.application.expectations.understandsReporting = value;
            },
          },
          {
            'title': 'I understand attendance expectations',
            'subtitle':
                'I understand call-offs, being late, or leaving post without relief may lead to discipline.',
            'value': user.application.expectations.understandsAttendance,
            'onChanged': (bool value) {
              user.application.expectations.understandsAttendance = value;
            },
          },
          {
            'title': 'I understand professionalism expectations',
            'subtitle':
                'I understand that uniform, conduct, attention, and professionalism matter at all times on duty.',
            'value': user.application.expectations.understandsProfessionalism,
            'onChanged': (bool value) {
              user.application.expectations.understandsProfessionalism = value;
            },
          },
          {
            'title':
                'I confirm that the information I entered is true and complete',
            'subtitle':
                'This final confirmation is required before completion.',
            'value': user.application.expectations.finalEmployeeConfirm,
            'onChanged': (bool value) {
              user.application.expectations.finalEmployeeConfirm = value;
            },
          },
        ];

        return Column(
          children: checklistItems.map((item) {
            return Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: NpsWizardColors.surface.withValues(alpha: 0.84),
                  border: Border.all(
                    color: NpsWizardColors.surfaceBorder.withValues(
                      alpha: 0.70,
                    ),
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Checkbox(
                      value: item['value'] as bool,
                      onChanged: (value) {
                        final onChanged = item['onChanged'] as Function(bool);
                        onChanged(value ?? false);
                        updateState();
                        onSave();
                      },
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      side: BorderSide(
                        color: NpsWizardColors.secondary,
                        width: 1.5,
                      ),
                      checkColor: Colors.white,
                      fillColor: WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.selected)) {
                          return NpsWizardColors.blueMid;
                        }
                        return NpsWizardColors.surface;
                      }),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item['title'] as String,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: NpsWizardColors.heading,
                              height: 1.25,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item['subtitle'] as String,
                            style: const TextStyle(
                              fontSize: 14,
                              color: NpsWizardColors.body,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      }

      if (field['type'] == 'expectationsFinalNotes') {
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Stack(
            children: [
              TextFormField(
                initialValue: user.application.expectations.finalNotes,
                maxLines: 4,
                textAlignVertical: TextAlignVertical.top,
                style: const TextStyle(
                  color: NpsWizardColors.heading,
                  fontWeight: FontWeight.w500,
                ),
                decoration: InputDecoration(
                  hintText: 'Final notes',
                  hintStyle: TextStyle(
                    color: NpsWizardColors.hint,
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                  ),
                  filled: true,
                  fillColor: NpsWizardColors.surface,
                  contentPadding: const EdgeInsets.fromLTRB(54, 14, 18, 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: const BorderSide(
                      color: NpsWizardColors.surfaceBorder,
                      width: 1.2,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: const BorderSide(
                      color: NpsWizardColors.surfaceBorder,
                      width: 1.2,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: const BorderSide(
                      color: NpsWizardColors.focusedBorder,
                      width: 1.4,
                    ),
                  ),
                ),
                onChanged: (value) {
                  user.application.expectations.finalNotes = value;
                  updateState();
                  onSave();
                },
              ),
              Positioned(
                left: 16,
                top: 18,
                child: IgnorePointer(
                  child: Icon(
                    Icons.edit_outlined,
                    color: NpsWizardColors.inputIcon,
                    size: 22,
                  ),
                ),
              ),
            ],
          ),
        );
      }

      if (field['type'] == 'uniformReceiptGrid') {
        final items = <Map<String, String>>[
          {'key': 'nps_cap', 'title': 'NPS Cap'},
          {'key': 'bomber_jacket', 'title': 'Bomber Jacket'},
          {'key': 'navy_blue_shirt_l_s', 'title': 'Navy Blue Shirt - L.S.'},
          {'key': 'wind_breaker', 'title': 'Wind Breaker'},
          {'key': 'nps_badge', 'title': 'NPS Badge'},
          {'key': 'navy_blue_shirt_s_s', 'title': 'Navy Blue Shirt - S.S.'},
          {'key': 'grey_shirt_l_s', 'title': 'Grey Shirt - L.S.'},
          {'key': 'grey_shirt_s_s', 'title': 'Grey Shirt - S.S.'},
          {'key': 'white_shirt_l_s', 'title': 'White Shirt - L.S.'},
          {'key': 'white_shirt_s_s', 'title': 'White Shirt - S.S.'},
          {'key': 'bdu_shirt', 'title': 'BDU Shirt'},
          {'key': 'tan_khaki_pants', 'title': 'Tan Khaki Pants'},
          {'key': 'navy_blue_slacks', 'title': 'Navy Blue Slacks'},
          {'key': 'grey_slacks', 'title': 'Grey Slacks'},
          {'key': 'black_suit', 'title': 'Black Suit'},
          {'key': 'blazer', 'title': 'Blazer'},
          {'key': 'tie_f', 'title': 'Tie (F)'},
          {'key': 'tie_m', 'title': 'Tie (M)'},
          {'key': 'handcuffs_case', 'title': 'Handcuffs & Case'},
          {'key': 'mase_case', 'title': 'Mase & Case'},
          {'key': 'rain_gear', 'title': 'Rain Gear'},
          {'key': 'bdu_pants', 'title': 'BDU Pants'},
          {'key': 'flashlight', 'title': 'Flashlight'},
          {'key': 'misc', 'title': 'Misc'},
        ];

        return Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: NpsWizardColors.surface.withValues(alpha: 0.80),
              border: Border.all(
                color: NpsWizardColors.surfaceBorder.withValues(alpha: 0.65),
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final twoCols = constraints.maxWidth >= 760;
                final compactFields = constraints.maxWidth < 420;
                final left = <Map<String, String>>[];
                final right = <Map<String, String>>[];

                for (var i = 0; i < items.length; i++) {
                  if (i.isEven) {
                    left.add(items[i]);
                  } else {
                    right.add(items[i]);
                  }
                }

                Widget buildItem(Map<String, String> item) {
                  final key = item['key']!;
                  final title = item['title']!;
                  final data = user.application.uniformReceipt.putIfAbsent(
                    key,
                    () => UniformItemData(),
                  );

                  InputDecoration inputDecoration(String hint) {
                    return InputDecoration(
                      hintText: hint,
                      hintStyle: TextStyle(
                        color: NpsWizardColors.secondary,
                        fontSize: compactFields ? 12 : 13,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 9,
                      ),
                      filled: true,
                      fillColor: NpsWizardColors.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: NpsWizardColors.surfaceBorder.withValues(
                            alpha: 0.65,
                          ),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: NpsWizardColors.surfaceBorder.withValues(
                            alpha: 0.65,
                          ),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: NpsWizardColors.focusedBorder,
                          width: 1.5,
                        ),
                      ),
                    );
                  }

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: NpsWizardColors.heading,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                initialValue: data.size,
                                style: const TextStyle(
                                  color: NpsWizardColors.heading,
                                  fontSize: 13.5,
                                ),
                                decoration: inputDecoration('Size'),
                                onChanged: (value) {
                                  data.size = value;
                                  updateState();
                                  onSave();
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextFormField(
                                initialValue: data.received,
                                keyboardType: TextInputType.number,
                                style: const TextStyle(
                                  color: NpsWizardColors.heading,
                                  fontSize: 13.5,
                                ),
                                decoration: inputDecoration(
                                  compactFields ? 'Received' : '# received',
                                ),
                                onChanged: (value) {
                                  data.received = value;
                                  updateState();
                                  onSave();
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextFormField(
                                initialValue: data.returned,
                                keyboardType: TextInputType.number,
                                style: const TextStyle(
                                  color: NpsWizardColors.heading,
                                  fontSize: 13.5,
                                ),
                                decoration: inputDecoration(
                                  compactFields ? 'Returned' : '# returned',
                                ),
                                onChanged: (value) {
                                  data.returned = value;
                                  updateState();
                                  onSave();
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }

                if (!twoCols) {
                  return Column(children: items.map(buildItem).toList());
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(children: left.map(buildItem).toList()),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(children: right.map(buildItem).toList()),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      }

      return const SizedBox.shrink();
    }).toList();
  }
}

class ReviewPage extends StatelessWidget {
  final UserAccount user;
  final ApplicationStep step;
  final VoidCallback onSave;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final bool isFirstPage;
  final bool isLastPage;
  final VoidCallback updateState;
  final VoidCallback? onGoThroughIncompleteSteps;

  const ReviewPage({
    super.key,
    required this.user,
    required this.step,
    required this.onSave,
    required this.onNext,
    required this.onPrevious,
    required this.isFirstPage,
    required this.isLastPage,
    required this.updateState,
    this.onGoThroughIncompleteSteps,
  });

  @override
  Widget build(BuildContext context) {
    final profile = user.application.profile;
    final incompleteSteps = applicationSteps
        .take(applicationSteps.length - 1)
        .where((s) => !_isStepComplete(s.id))
        .toList();
    final completedCount = applicationSteps
        .where((s) => _isStepComplete(s.id))
        .length;

    return _KeyboardInsetPadding(
      child: SingleChildScrollView(
        physics: _wizardScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RepaintBoundary(
              child: PageHeader(
                step: step,
                stepNumber: applicationSteps.length,
                totalSteps: applicationSteps.length,
                lastSaved: user.application.lastSavedAt,
              ),
            ),
            const SizedBox(height: 18),

            ReviewCard(
              title: 'Completion summary',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$completedCount of ${applicationSteps.length} steps completed.',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: NpsWizardColors.heading,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Any step still not completed should be opened from the left and finished before final printing or export.',
                    style: TextStyle(
                      color: NpsWizardColors.secondary,
                      fontSize: 14,
                    ),
                  ),
                  if (incompleteSteps.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: NpsWizardColors.warning.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: NpsWizardColors.warning.withValues(
                            alpha: 0.38,
                          ),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Incomplete steps',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: NpsWizardColors.heading,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...incompleteSteps.map(
                            (step) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                '- ${step.title}',
                                style: const TextStyle(
                                  color: NpsWizardColors.heading,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                          if (onGoThroughIncompleteSteps != null) ...[
                            const SizedBox(height: 10),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: ElevatedButton.icon(
                                onPressed: onGoThroughIncompleteSteps,
                                icon: const Icon(
                                  Icons.alt_route_rounded,
                                  size: 18,
                                ),
                                label: const Text(
                                  'Go Through All Incomplete Steps',
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: NpsWizardColors.blueMid,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            ReviewCard(
              title: 'Applicant',
              child: KeyValueGrid(
                items: {
                  'Name':
                      '${profile.firstName} ${profile.middleInitial} ${profile.lastName}',
                  'Phone': profile.phone,
                  'Email': profile.email,
                  'DOB': profile.dob,
                  'Last Saved': _formatLastSaved(user.application.lastSavedAt),
                },
              ),
            ),

            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: ElevatedButton(
                onPressed: incompleteSteps.isEmpty ? onSave : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: NpsWizardColors.surface,
                  foregroundColor: NpsWizardColors.heading,
                  disabledBackgroundColor: NpsWizardColors.panelBottom,
                  disabledForegroundColor: NpsWizardColors.hint,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 13,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: const BorderSide(
                      color: NpsWizardColors.surfaceBorder,
                    ),
                  ),
                ),
                child: const Text('Save Draft'),
              ),
            ),

            const SizedBox(height: 22),
            RepaintBoundary(
              child: PageNavigation(
                onPrevious: onPrevious,
                onNext: onNext,
                onSave: onSave,
                isFirstPage: isFirstPage,
                isLastPage: isLastPage,
                canProceed: incompleteSteps.isEmpty,
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isStepComplete(String stepId) {
    final app = user.application;

    switch (stepId) {
      case 'profile':
        return app.profile.firstName.isNotEmpty &&
            app.profile.lastName.isNotEmpty &&
            app.profile.phone.isNotEmpty &&
            app.profile.email.isNotEmpty &&
            app.profile.dob.isNotEmpty &&
            app.signatures.containsKey('profile');

      case 'terms':
        return app.agreements.baseRate.isNotEmpty &&
            app.signatures.containsKey('terms');

      case 'arbitration':
        return app.signatures.containsKey('arbitrationEmployee');

      case 'eeo':
        return app.signatures.containsKey('eeo');

      case 'noncompete':
        return app.signatures.containsKey('noncompete');

      case 'release':
        return app.profile.ssn.isNotEmpty &&
            app.signatures.containsKey('release');

      case 'pay':
        return app.signatures.containsKey('pay');

      case 'uniformReceipt':
        return app.signatures.containsKey('uniformReceipt');

      case 'uniformStandards':
        return app.signatures.containsKey('uniformStandards');

      case 'tattoos':
        return app.signatures.containsKey('tattoos');

      case 'offDuty':
        return app.signatures.containsKey('offDuty');

      case 'mealGuide':
        return app.agreements.mealGuideAgree.isNotEmpty &&
            app.signatures.containsKey('mealGuide');

      case 'mealAgreement':
        return app.signatures.containsKey('mealAgreement');

      case 'expectations':
        return app.expectations.finalEmployeeConfirm &&
            app.signatures.containsKey('expectations');

      case 'w4':
        return true;

      case 'review':
        return applicationSteps
            .take(applicationSteps.length - 1)
            .every((s) => _isStepComplete(s.id));

      default:
        return false;
    }
  }

  String _formatLastSaved(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Not saved yet';
    }

    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      return 'Not saved yet';
    }

    return parsed.toLocal().toString();
  }
}
