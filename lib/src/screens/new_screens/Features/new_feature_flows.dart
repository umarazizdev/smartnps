import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:smartnps360/src/screens/new_screens/Widgets/new_common_widgets.dart';
import 'package:smartnps360/src/screens/utilities/const.dart';

class NewFeatureFlows {
  static void open({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required List<NewFeatureStage> stages,
  }) {
    Get.to(
      () => NewFeatureFlowScreen(
        title: title,
        subtitle: subtitle,
        icon: icon,
        color: color,
        stages: stages,
      ),
      transition: Transition.cupertino,
    );
  }

  static void openReportIssue() => open(
    title: 'Report Issue',
    subtitle: 'Log a site issue with photo, note, and severity.',
    icon: Icons.flag_rounded,
    color: NewUi.warning,
    stages: const [
      NewFeatureStage(
        title: 'Issue details',
        fields: ['Category', 'Severity', 'Location', 'Description'],
        primaryLabel: 'Continue',
      ),
      NewFeatureStage(
        title: 'Evidence',
        fields: ['Add photo', 'Add note', 'Mark urgent'],
        primaryLabel: 'Submit issue',
      ),
    ],
  );

  static void openWalkthrough() => open(
    title: 'Site Walkthrough',
    subtitle: 'Setup, directives, and checkpoint capture.',
    icon: Icons.home_work_rounded,
    color: NewUi.teal,
    stages: const [
      NewFeatureStage(
        title: 'Setup',
        fields: ['Site', 'Walkthrough type', 'Start time'],
        primaryLabel: 'Start walkthrough',
      ),
      NewFeatureStage(
        title: 'Directive',
        fields: ['Areas to cover', 'Special instructions'],
        primaryLabel: 'Begin checkpoints',
      ),
      NewFeatureStage(
        title: 'Checkpoint',
        fields: ['Photo', 'GPS pin', 'Notes', 'Complete area'],
        primaryLabel: 'Finish walkthrough',
      ),
    ],
  );

  static void openPatrol() => open(
    title: 'Patrol',
    subtitle: 'Choose patrol method and complete route visits.',
    icon: Icons.location_on_rounded,
    color: NewUi.purple,
    stages: const [
      NewFeatureStage(
        title: 'Patrol method',
        fields: ['Round timer', 'QR patrol', 'Tour checklist', 'Route map'],
        primaryLabel: 'Continue',
      ),
      NewFeatureStage(
        title: 'Active patrol',
        fields: ['Next checkpoint', 'Mark visit', 'Capture photo'],
        primaryLabel: 'Complete patrol',
      ),
    ],
  );

  static void openPatrolPlan() => open(
    title: 'Patrol Plan',
    subtitle: 'Track remaining visits across the patrol route.',
    icon: Icons.checklist_rounded,
    color: NewUi.purple,
    stages: const [
      NewFeatureStage(
        title: 'Route progress',
        fields: [
          'Lobby ×2',
          'Parking B1 ×1',
          'Roof access ×1',
          'Loading dock ×1',
        ],
        primaryLabel: 'Open map',
      ),
    ],
  );

  static void openIncident() => open(
    title: 'Incident Report',
    subtitle: 'Create or review incident reports for dispatch.',
    icon: Icons.report_rounded,
    color: NewUi.danger,
    stages: const [
      NewFeatureStage(
        title: 'Incident list',
        fields: ['Open incidents', 'Drafts', 'Submitted'],
        primaryLabel: 'New incident',
      ),
      NewFeatureStage(
        title: 'Incident form',
        fields: ['Type', 'Severity', 'People involved', 'Narrative', 'Photos'],
        primaryLabel: 'Submit report',
      ),
    ],
  );

  static void openParking() => open(
    title: 'Parking Management',
    subtitle: 'Violations, visitor parking, lookup, and tow requests.',
    icon: Icons.local_parking_rounded,
    color: NewUi.textMutedLight,
    stages: const [
      NewFeatureStage(
        title: 'Parking menu',
        fields: [
          'Log violation',
          'Visitor parking',
          'Plate lookup',
          'Tow request',
        ],
        primaryLabel: 'Continue',
      ),
      NewFeatureStage(
        title: 'Plate capture',
        fields: ['Scan plate', 'Vehicle make', 'Location', 'Notes'],
        primaryLabel: 'Save entry',
      ),
    ],
  );

  static void openFleet() => open(
    title: 'Fleet',
    subtitle: 'Vehicle lookup, fuel, maintenance, and location history.',
    icon: Icons.directions_car_filled_rounded,
    color: const Color(0xFFEC4899),
    stages: const [
      NewFeatureStage(
        title: 'Fleet browse',
        fields: ['Lookup plate', 'Assigned vehicles', 'Available units'],
        primaryLabel: 'Open vehicle',
      ),
      NewFeatureStage(
        title: 'Vehicle detail',
        fields: ['Fuel log', 'Maintenance', 'Location', 'History'],
        primaryLabel: 'Save update',
      ),
    ],
  );

  static void openMoveInspection() => open(
    title: 'Pre/Post Inspection',
    subtitle: 'Unit move inspection with photos and signatures.',
    icon: Icons.home_work_rounded,
    color: NewUi.success,
    stages: const [
      NewFeatureStage(
        title: 'Inspection type',
        fields: ['Pre-move', 'Post-move', 'Unit number'],
        primaryLabel: 'Continue',
      ),
      NewFeatureStage(
        title: 'Areas',
        fields: ['Kitchen', 'Bathrooms', 'Living areas', 'Exterior'],
        primaryLabel: 'Capture area',
      ),
      NewFeatureStage(
        title: 'Complete',
        fields: ['Photos', 'Damage notes', 'Signature'],
        primaryLabel: 'Submit inspection',
      ),
    ],
  );

  static void openSiteManual() => open(
    title: 'Site Manual',
    subtitle: 'Post orders, emergency procedures, and site policies.',
    icon: Icons.menu_book_rounded,
    color: NewUi.purple,
    stages: const [
      NewFeatureStage(
        title: 'Manual sections',
        fields: [
          'Post orders',
          'Emergency procedures',
          'Access control',
          'Visitor policy',
          'Fire safety',
        ],
        primaryLabel: 'Close',
      ),
    ],
  );

  static void openFirewatch() => open(
    title: 'Firewatch',
    subtitle: 'Round history, signature capture, and status tracking.',
    icon: Icons.local_fire_department_rounded,
    color: NewUi.danger,
    stages: const [
      NewFeatureStage(
        title: 'Firewatch status',
        fields: ['Current round', 'Last check', 'Sign log'],
        primaryLabel: 'Start round',
      ),
      NewFeatureStage(
        title: 'Firewatch patrol',
        fields: ['Checkpoint list', 'Photo', 'Signature'],
        primaryLabel: 'Complete round',
      ),
    ],
  );

  static void openPayroll() => open(
    title: 'Payroll',
    subtitle: 'Timesheet, payments, and weekly summary.',
    icon: Icons.account_balance_wallet_rounded,
    color: NewUi.success,
    stages: const [
      NewFeatureStage(
        title: 'Timesheet',
        fields: ['This week hours', 'Approved shifts', 'Pending corrections'],
        primaryLabel: 'View payments',
      ),
      NewFeatureStage(
        title: 'Payments',
        fields: ['Last deposit', 'YTD earnings', 'Tax docs'],
        primaryLabel: 'Weekly summary',
      ),
      NewFeatureStage(
        title: 'Weekly summary',
        fields: ['Regular hours', 'OT hours', 'Breaks', 'Net pay estimate'],
        primaryLabel: 'Done',
      ),
    ],
  );

  static void openReportAssist() => open(
    title: 'Report Assist',
    subtitle: 'Dictate or type notes and generate a polished report draft.',
    icon: Icons.auto_awesome_rounded,
    color: NewUi.accent,
    stages: const [
      NewFeatureStage(
        title: 'Input',
        fields: ['Voice note', 'Typed notes', 'Language'],
        primaryLabel: 'Generate draft',
      ),
      NewFeatureStage(
        title: 'Thinking',
        fields: ['Structuring narrative', 'Checking severity cues'],
        primaryLabel: 'Show output',
      ),
      NewFeatureStage(
        title: 'Output',
        fields: ['Draft report', 'Copy', 'Send to incident form'],
        primaryLabel: 'Use draft',
      ),
    ],
  );
}

class NewFeatureStage {
  const NewFeatureStage({
    required this.title,
    required this.fields,
    required this.primaryLabel,
  });

  final String title;
  final List<String> fields;
  final String primaryLabel;
}

class NewFeatureFlowScreen extends StatefulWidget {
  const NewFeatureFlowScreen({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.stages,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final List<NewFeatureStage> stages;

  @override
  State<NewFeatureFlowScreen> createState() => _NewFeatureFlowScreenState();
}

class _NewFeatureFlowScreenState extends State<NewFeatureFlowScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final stage = widget.stages[_index];
    final isLast = _index >= widget.stages.length - 1;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: NewAnimatedShell(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 16, 8),
                child: Row(
                  children: [
                    NewBackButton(
                      onPressed: () {
                        if (_index == 0) {
                          Get.back();
                        } else {
                          setState(() => _index -= 1);
                        }
                      },
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: isDark ? NewUi.textDark : NewUi.textLight,
                            ),
                          ),
                          Text(
                            'Step ${_index + 1} of ${widget.stages.length}',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: isDark
                                  ? NewUi.textMutedDark
                                  : NewUi.textMutedLight,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        gradient: NewUi.accentGradient(widget.color),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(widget.icon, color: Colors.white, size: 22),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    NewGlassCard(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            stage.title,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: isDark ? NewUi.textDark : NewUi.textLight,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            widget.subtitle,
                            style: TextStyle(
                              fontSize: 13.5,
                              height: 1.4,
                              color: isDark
                                  ? NewUi.textMutedDark
                                  : NewUi.textMutedLight,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    ...stage.fields.map(
                      (field) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: NewGlassCard(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 14,
                          ),
                          onTap: () {},
                          child: Row(
                            children: [
                              Icon(
                                Icons.check_circle_outline_rounded,
                                color: widget.color,
                                size: 22,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  field,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: isDark
                                        ? NewUi.textDark
                                        : NewUi.textLight,
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.chevron_right_rounded,
                                color: isDark
                                    ? NewUi.textMutedDark
                                    : NewUi.textMutedLight,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cPrimary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: () {
                      if (isLast) {
                        Get.back();
                        Get.snackbar(
                          widget.title,
                          'Saved locally for this demo console.',
                          snackPosition: SnackPosition.BOTTOM,
                          margin: const EdgeInsets.all(16),
                        );
                      } else {
                        setState(() => _index += 1);
                      }
                    },
                    child: Text(
                      stage.primaryLabel,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
