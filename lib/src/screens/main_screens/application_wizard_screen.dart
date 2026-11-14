import 'dart:async' show Timer, unawaited;
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:smartnps360/src/screens/controllers/auth_controller.dart';
import 'package:smartnps360/src/screens/models/application_models.dart';
import 'package:smartnps360/src/screens/services/storage_service.dart';
import 'package:smartnps360/src/screens/widgets/app_step_pages.dart';
import 'package:smartnps360/src/screens/widgets/nps_wizard_theme.dart';
import 'auth_screen.dart';

class ApplicationWizardScreen extends StatefulWidget {
  final UserAccount user;

  const ApplicationWizardScreen({super.key, required this.user});

  @override
  State<ApplicationWizardScreen> createState() =>
      _ApplicationWizardScreenState();
}

class _ApplicationWizardScreenState extends State<ApplicationWizardScreen> {
  late UserAccount _currentUser;
  Map<String, UserAccount> _allUsers = {};
  final _storageService = StorageService();
  final _pageController = PageController();
  final _contentRefreshTick = ValueNotifier<int>(0);
  Timer? _autoSaveTimer;
  bool _isSavingDraft = false;
  bool _saveQueued = false;
  bool _guidedIncompleteFlowActive = false;

  int get _currentPage => _currentUser.application.currentPage;

  @override
  void initState() {
    super.initState();
    _currentUser = widget.user;
    _loadUsers();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_currentPage > 0 && _currentPage < applicationSteps.length) {
        _pageController.jumpToPage(_currentPage);
      }
    });
  }

  Future<void> _loadUsers() async {
    _allUsers = await _storageService.loadUsers();
  }

  Future<void> _saveDraft({
    bool unfocus = false,
    bool refreshUi = false,
  }) async {
    if (_isSavingDraft) {
      _saveQueued = true;
      return;
    }

    if (unfocus) {
      FocusManager.instance.primaryFocus?.unfocus();
    }

    _isSavingDraft = true;
    _currentUser.application.lastSavedAt = DateTime.now().toIso8601String();
    _currentUser.application.currentPage = _currentPage;

    _allUsers[_currentUser.id] = _currentUser;
    try {
      await _storageService.saveUsers(_allUsers);
    } finally {
      _isSavingDraft = false;
    }

    if (mounted && refreshUi) {
      setState(() {});
    }

    if (_saveQueued) {
      _saveQueued = false;
      unawaited(_saveDraft(unfocus: false, refreshUi: refreshUi));
    }
  }

  void _autoSave([Duration delay = const Duration(milliseconds: 700)]) {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(delay, () {
      _saveDraft(unfocus: false, refreshUi: false);
    });
  }

  void _goToPage(int index) {
    if (index < 0 || index >= applicationSteps.length) return;
    _autoSaveTimer?.cancel();

    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _pageController.jumpToPage(index);
    } else {
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  void _goNext() {
    final lastPageIndex = applicationSteps.length - 1;
    if (_currentPage < lastPageIndex) {
      if (_guidedIncompleteFlowActive) {
        _advanceGuidedIncompleteFlow();
      } else {
        _goToPage(_currentPage + 1);
      }
      return;
    }

    _handleFinalReviewContinue();
  }

  void _goPrevious() {
    if (_currentPage > 0) {
      _goToPage(_currentPage - 1);
    }
  }

  List<ApplicationStep> _getIncompleteStepsBeforeReview() {
    return applicationSteps
        .take(applicationSteps.length - 1)
        .where((step) => !_isStepComplete(step.id))
        .toList();
  }

  void _startGuidedIncompleteFlow() {
    final incompleteSteps = _getIncompleteStepsBeforeReview();
    if (incompleteSteps.isEmpty) {
      _guidedIncompleteFlowActive = false;
      _showMessage('All steps are already complete.');
      return;
    }

    _guidedIncompleteFlowActive = true;
    final firstIncomplete = incompleteSteps.first;
    final firstIndex = applicationSteps.indexWhere(
      (s) => s.id == firstIncomplete.id,
    );
    if (firstIndex >= 0) {
      _goToPage(firstIndex);
      _showMessage(
        'Guided mode started: ${incompleteSteps.length} incomplete step(s).',
      );
    }
  }

  void _advanceGuidedIncompleteFlow() {
    final lastPageIndex = applicationSteps.length - 1;
    if (_currentPage >= lastPageIndex) {
      return;
    }

    final currentStep = applicationSteps[_currentPage];
    if (!_isStepComplete(currentStep.id)) {
      _showMessage('Please complete this step before continuing.');
      return;
    }

    final incompleteIndices = <int>[];
    for (var i = 0; i < lastPageIndex; i++) {
      if (!_isStepComplete(applicationSteps[i].id)) {
        incompleteIndices.add(i);
      }
    }

    if (incompleteIndices.isEmpty) {
      _guidedIncompleteFlowActive = false;
      _goToPage(lastPageIndex);
      _showMessage(
        'All incomplete steps are complete. Returned to Review & Finish.',
      );
      return;
    }

    final nextAfterCurrent = incompleteIndices.where((i) => i > _currentPage);
    final targetIndex = nextAfterCurrent.isNotEmpty
        ? nextAfterCurrent.first
        : incompleteIndices.first;
    _goToPage(targetIndex);
  }

  Future<void> _handleFinalReviewContinue() async {
    final incompleteSteps = _getIncompleteStepsBeforeReview();

    if (incompleteSteps.isEmpty) {
      _guidedIncompleteFlowActive = false;
      _showMessage(
        'All required steps are complete. You can now finish/export.',
      );
      return;
    }

    final firstIncomplete = incompleteSteps.first;
    final firstIndex = applicationSteps.indexWhere(
      (s) => s.id == firstIncomplete.id,
    );
    if (firstIndex >= 0) {
      _guidedIncompleteFlowActive = true;
      _goToPage(firstIndex);
      _showMessage(
        'Incomplete steps found. Moved to: ${firstIncomplete.title}',
      );
    }
  }

  Future<void> _handleLogout() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await _saveDraft(unfocus: false, refreshUi: true);
    await _storageService.setLastUserId(null);

    if (Get.isRegistered<AuthController>()) {
      Get.delete<AuthController>(force: true);
    }
    Get.offAll(() => const AuthScreen());
  }

  Future<void> _downloadJSON() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await _saveDraft(unfocus: false, refreshUi: true);

    final jsonData = json.encode(_currentUser.application.toJson());
    final fileName =
        '${_currentUser.firstName}_${_currentUser.lastName}_nps_application.json'
            .replaceAll(' ', '_');

    if (kIsWeb) {
      _showMessage('JSON export: Use share button or see console');
      debugPrint(jsonData);
    } else {
      try {
        final directory =
            await _resolveDownloadDirectory() ??
            await getApplicationDocumentsDirectory();
        if (!directory.existsSync()) {
          directory.createSync(recursive: true);
        }

        final file = File('${directory.path}/$fileName');
        await file.writeAsString(jsonData);
        _showMessage('Downloaded JSON to: ${file.path}');
      } catch (e) {
        _showMessage('Download failed: $e');
      }
    }
  }

  Future<Directory?> _resolveDownloadDirectory() async {
    try {
      final downloads = await getDownloadsDirectory();
      if (downloads != null) {
        return downloads;
      }
    } catch (_) {}

    if (Platform.isAndroid) {
      final androidCandidates = [
        '/storage/emulated/0/Download',
        '/sdcard/Download',
      ];
      for (final path in androidCandidates) {
        final dir = Directory(path);
        if (dir.existsSync()) {
          return dir;
        }
      }
    }

    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home != null && home.isNotEmpty) {
      final dir = Directory('$home${Platform.pathSeparator}Downloads');
      if (dir.existsSync()) {
        return dir;
      }
    }

    return null;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  bool _isStepComplete(String stepId) {
    final app = _currentUser.application;

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

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _pageController.dispose();
    _contentRefreshTick.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isSmall = size.width < 980;

    return Theme(
      data: NpsWizardTheme.data,
      child: Scaffold(
        backgroundColor: NpsWizardColors.background,
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            const Positioned.fill(
              child: RepaintBoundary(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: NpsWizardColors.backgroundGradient,
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  RepaintBoundary(child: _buildTopBar(context)),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: isSmall ? 12 : 18,
                        vertical: isSmall ? 12 : 18,
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1120),
                        child: isSmall
                            ? RepaintBoundary(child: _buildMainContent())
                            : Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 290,
                                    child: RepaintBoundary(
                                      child: _buildSidebar(),
                                    ),
                                  ),
                                  const SizedBox(width: 18),
                                  Expanded(
                                    child: RepaintBoundary(
                                      child: _buildMainContent(),
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: null,
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isSmall = width < 720;
    final compactActions = width < 980;
    final logoSize = isSmall ? 52.0 : 62.0;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isSmall ? 16 : 22,
        vertical: isSmall ? 12 : 14,
      ),
      decoration: BoxDecoration(
        gradient: NpsWizardColors.panelGradient,
        border: Border(
          bottom: BorderSide(
            color: NpsWizardColors.surfaceBorder.withValues(alpha: 0.50),
          ),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: logoSize,
            height: logoSize,
            child: Image.asset(
              'assets/images/npslogo.png',
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
            ),
          ),
          SizedBox(width: isSmall ? 10 : 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'National Protective Service',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: NpsWizardColors.heading,
                    fontSize: isSmall ? 16 : 20,
                    height: 1.17,
                    letterSpacing: -0.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Digital registration and application portal',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: NpsWizardColors.secondary,
                    fontSize: isSmall ? 11.5 : 13.5,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          if (compactActions)
            PopupMenuButton<String>(
              tooltip: 'Application actions',
              color: NpsWizardColors.panel,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: NpsWizardColors.surfaceBorder.withValues(alpha: 0.8),
                ),
              ),
              icon: const Icon(
                Icons.more_vert_rounded,
                color: NpsWizardColors.heading,
              ),
              onSelected: (action) {
                switch (action) {
                  case 'save':
                    unawaited(_saveDraft());
                    break;
                  case 'export':
                    unawaited(_downloadJSON());
                    break;
                  case 'logout':
                    unawaited(_handleLogout());
                    break;
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'save', child: Text('Save draft')),
                PopupMenuItem(value: 'export', child: Text('Download JSON')),
                PopupMenuItem(
                  value: 'logout',
                  child: Text(
                    'Log out',
                    style: TextStyle(color: NpsWizardColors.error),
                  ),
                ),
              ],
            )
          else ...[
            const SizedBox(width: 18),
            Wrap(
              spacing: 10,
              children: [
                _buildTopButton('Save Draft', _saveDraft),
                _buildTopButton('Download JSON', _downloadJSON),
                _buildTopButton('Logout', _handleLogout, isDanger: true),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTopButton(
    String label,
    VoidCallback onPressed, {
    bool isDanger = false,
  }) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: isDanger
            ? NpsWizardColors.error
            : NpsWizardColors.heading,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        backgroundColor: isDanger
            ? NpsWizardColors.error.withValues(alpha: 0.075)
            : NpsWizardColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: isDanger
                ? NpsWizardColors.error.withValues(alpha: 0.34)
                : NpsWizardColors.surfaceBorder.withValues(alpha: 0.75),
          ),
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
      ),
    );
  }

  Widget _buildSidebar({bool isSmall = false}) {
    final completed = applicationSteps
        .where((step) => _isStepComplete(step.id))
        .length;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: NpsWizardColors.panelGradient,
        border: Border.all(
          color: NpsWizardColors.surfaceBorder.withValues(alpha: 0.62),
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'APPLICATION PROGRESS',
            style: TextStyle(
              color: NpsWizardColors.hint,
              fontSize: 11,
              letterSpacing: 1.0,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            '${_currentUser.firstName} ${_currentUser.lastName}',
            style: const TextStyle(
              color: NpsWizardColors.heading,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 7),
          Text(
            '$completed of ${applicationSteps.length} steps complete',
            style: const TextStyle(
              color: NpsWizardColors.secondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(
                begin: 0,
                end: completed / applicationSteps.length,
              ),
              duration:
                  (MediaQuery.maybeOf(context)?.disableAnimations ?? false)
                  ? Duration.zero
                  : const Duration(milliseconds: 420),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 5,
                backgroundColor: NpsWizardColors.surface,
                valueColor: const AlwaysStoppedAnimation(
                  NpsWizardColors.blueMid,
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          if (!isSmall)
            Flexible(
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: Column(
                  children: List.generate(
                    applicationSteps.length,
                    (index) => Padding(
                      padding: const EdgeInsets.only(bottom: 7),
                      child: _buildStepButton(index),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStepButton(int index) {
    final step = applicationSteps[index];
    final isActive = index == _currentPage;
    final isComplete = _isStepComplete(step.id);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _goToPage(index),
        borderRadius: BorderRadius.circular(13),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: isActive
                ? NpsWizardColors.blueMid.withValues(alpha: 0.18)
                : NpsWizardColors.surface.withValues(alpha: 0.70),
            border: Border.all(
              color: isActive
                  ? NpsWizardColors.focusedBorder.withValues(alpha: 0.72)
                  : NpsWizardColors.surfaceBorder.withValues(alpha: 0.36),
            ),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isComplete
                      ? NpsWizardColors.success.withValues(alpha: 0.13)
                      : isActive
                      ? NpsWizardColors.blueMid.withValues(alpha: 0.28)
                      : NpsWizardColors.surface,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: isComplete
                    ? const Icon(
                        Icons.check_rounded,
                        color: NpsWizardColors.success,
                        size: 16,
                      )
                    : Text(
                        '${index + 1}',
                        style: TextStyle(
                          color: isActive
                              ? NpsWizardColors.heading
                              : NpsWizardColors.secondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      step.title,
                      style: const TextStyle(
                        color: NpsWizardColors.heading,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                    if (step.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        step.subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: NpsWizardColors.secondary,
                          fontSize: 11.5,
                          height: 1.30,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompactStepProgress() {
    final count = applicationSteps.length;
    final current = _currentPage.clamp(0, count - 1);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Semantics(
      label: 'Application step ${current + 1} of $count',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(2, 0, 2, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'APPLICATION STEPS',
                    style: TextStyle(
                      color: NpsWizardColors.hint,
                      fontSize: 11,
                      letterSpacing: 1.0,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  'Step ${current + 1} of $count',
                  style: const TextStyle(
                    color: NpsWizardColors.secondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: (current + 1) / count),
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 420),
                curve: Curves.easeOutCubic,
                builder: (context, value, _) => LinearProgressIndicator(
                  value: value,
                  minHeight: 5,
                  backgroundColor: NpsWizardColors.surface,
                  valueColor: const AlwaysStoppedAnimation(
                    NpsWizardColors.blueMid,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    final width = MediaQuery.sizeOf(context).width;
    final isSmall = width < 720;
    final isCompact = width < 980;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    final form = Container(
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        gradient: NpsWizardColors.panelGradient,
        border: Border.all(
          color: NpsWizardColors.surfaceBorder.withValues(alpha: 0.62),
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(isSmall ? 16 : 22),
        child: ValueListenableBuilder<int>(
          valueListenable: _contentRefreshTick,
          builder: (context, _, _) {
            return RepaintBoundary(
              child: PageView.builder(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (index) {
                  if (!mounted) return;
                  _currentUser.application.currentPage = index;
                  _autoSave(const Duration(milliseconds: 500));

                  setState(() {});
                },
                itemCount: applicationSteps.length,
                itemBuilder: (context, index) {
                  final page = AppStepPage(
                    step: applicationSteps[index],
                    user: _currentUser,
                    onSave: _autoSave,
                    onNext: _goNext,
                    onPrevious: _goPrevious,
                    isFirstPage: index == 0,
                    isLastPage: index == applicationSteps.length - 1,
                    onGoThroughIncompleteSteps: _startGuidedIncompleteFlow,
                    updateState: () {
                      _contentRefreshTick.value++;
                    },
                  );
                  if (reduceMotion) return page;

                  return AnimatedBuilder(
                    animation: _pageController,
                    child: page,
                    builder: (context, child) {
                      final distance = _pageController.hasClients
                          ? ((_pageController.page ?? index.toDouble()) - index)
                                .abs()
                                .clamp(0.0, 1.0)
                          : 0.0;
                      return Opacity(
                        opacity: 1.0 - (0.16 * distance),
                        child: Transform.translate(
                          offset: Offset(0, 8.0 * distance),
                          child: child,
                        ),
                      );
                    },
                  );
                },
              ),
            );
          },
        ),
      ),
    );

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: reduceMotion ? 1.0 : 0.0, end: 1.0),
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      builder: (context, progress, child) => Opacity(
        opacity: progress,
        child: Transform.translate(
          offset: Offset(0, (1.0 - progress) * 12.0),
          child: child,
        ),
      ),
      child: Column(
        children: [
          if (isCompact) _buildCompactStepProgress(),
          Expanded(child: form),
        ],
      ),
    );
  }
}
