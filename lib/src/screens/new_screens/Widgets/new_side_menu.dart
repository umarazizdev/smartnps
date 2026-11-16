import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../Dashboard/new_dashboard_controller.dart';
import 'new_common_widgets.dart';

class NewSideMenu extends StatelessWidget {
  const NewSideMenu({super.key, required this.open, required this.onClose});

  final bool open;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      children: [
        if (open)
          Positioned.fill(
            child: GestureDetector(
              onTap: onClose,
              child: ColoredBox(
                color: isDark
                    ? Colors.black.withAlpha(150)
                    : const Color(0xFF0F172A).withAlpha(90),
              ),
            ),
          ),
        AnimatedPositioned(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          left: open ? 0 : -310,
          top: 0,
          bottom: 0,
          width: 284,
          child: SafeArea(
            child: Container(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
              decoration: BoxDecoration(
                gradient: isDark
                    ? const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF0C1020), Color(0xFF070912)])
                    : const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.white, Color(0xFFF5F7FB)]),
                border: Border(right: BorderSide(color: isDark ? Colors.white.withAlpha(18) : const Color(0xFFE2E8F0))),
                boxShadow: [BoxShadow(color: Colors.black.withAlpha(isDark ? 130 : 45), blurRadius: 60, offset: const Offset(30, 0))],
              ),
              child: const _SideContent(),
            ),
          ),
        ),
      ],
    );
  }
}

class _SideContent extends StatelessWidget {
  const _SideContent();

  @override
  Widget build(BuildContext context) {
    final c = Get.find<NewDashboardController>();
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Obx(
          () => _ProfileButton(
            initials: c.initials,
            name: c.officerName.value,
            role: 'Security Officer',
            onTap: c.openProfileScreen,
          ),
        ),
        const _MenuSection('Quick Access'),
        _MenuItem(Icons.home_work_rounded, 'On-Site SCH', c.showInfoOnsite),
        _MenuItem(Icons.location_on_rounded, 'Patrol Officer SCH', c.showInfoPatrol),
        const _MenuSection('Account'),
        _MenuItem(Icons.person_rounded, 'Profile', c.openProfileScreen),
        _MenuItem(Icons.settings_rounded, 'Settings', c.showInfoSettings),
        const _MenuSection('Career'),
        _MenuItem(Icons.business_center_rounded, 'Job Applications', c.showInfoJobs),
        _MenuItem(Icons.school_rounded, 'Training & Onboarding', c.showInfoTraining),
        Obx(
          () => Column(
            children: [
              _MenuItem(
                Icons.verified_user_rounded,
                'Compliance Center',
                c.toggleCompliance,
                trailing: AnimatedRotation(
                  turns: c.complianceExpanded.value ? .5 : 0,
                  duration: const Duration(milliseconds: 220),
                  child: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
                ),
              ),
              AnimatedCrossFade(
                firstChild: const SizedBox.shrink(),
                secondChild: Padding(
                  padding: const EdgeInsets.only(left: 16, top: 2, bottom: 6),
                  child: Column(children: c.complianceItems.map((e) => _SubItem(e, () => c.showInfoText(e, 'Compliance document preview.'))).toList()),
                ),
                crossFadeState: c.complianceExpanded.value ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 220),
              ),
            ],
          ),
        ),
        const _MenuSection('Support'),
        _MenuItem(Icons.phone_rounded, 'Contact Dispatch', c.showInfoDispatch),
        const SizedBox(height: 8),
        _MenuItem(Icons.logout_rounded, 'Logout', c.showLogoutConfirm, color: NewUi.danger),
      ],
    );
  }
}

class _ProfileButton extends StatelessWidget {
  const _ProfileButton({required this.initials, required this.name, required this.role, required this.onTap});

  final String initials;
  final String name;
  final String role;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withAlpha(10) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: isDark ? Colors.white.withAlpha(18) : const Color(0xFFE5EAF1)),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: NewUi.accentGradient(NewUi.accent),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(color: NewUi.accent.withAlpha(65), blurRadius: 14, offset: const Offset(0, 5))],
              ),
              child: Center(child: Text(initials, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16))),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -0.1)),
                  const SizedBox(height: 5),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 5,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: NewUi.success.withAlpha(26), borderRadius: BorderRadius.circular(99)),
                        child: const Text('ACTIVE', style: TextStyle(color: NewUi.success, fontSize: 8.5, fontWeight: FontWeight.w900, letterSpacing: .5)),
                      ),
                      Text(role, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: isDark ? NewUi.textMutedDark : NewUi.textMutedLight, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 20, color: isDark ? NewUi.textMutedDark : NewUi.textMutedLight),
          ],
        ),
      ),
    );
  }
}

class _MenuSection extends StatelessWidget {
  const _MenuSection(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 18, 6, 6),
      child: Text(text, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).brightness == Brightness.dark ? NewUi.textMutedDark : NewUi.textMutedLight, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
    );
  }
}

class _MenuItem extends StatefulWidget {
  const _MenuItem(this.icon, this.text, this.onTap, {this.trailing, this.color});

  final IconData icon;
  final String text;
  final VoidCallback onTap;
  final Widget? trailing;
  final Color? color;

  @override
  State<_MenuItem> createState() => _MenuItemState();
}

class _MenuItemState extends State<_MenuItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.color ?? (Theme.of(context).brightness == Brightness.dark ? NewUi.textDark : NewUi.textLight);
    final activeColor = widget.color ?? NewUi.accent2;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          margin: const EdgeInsets.symmetric(vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(color: _hover ? activeColor.withAlpha(18) : Colors.transparent, borderRadius: BorderRadius.circular(12)),
          child: Row(
            children: [
              Icon(widget.icon, size: 18, color: _hover ? activeColor : c.withAlpha(205)),
              const SizedBox(width: 11),
              Expanded(child: Text(widget.text, style: TextStyle(color: _hover ? activeColor : c, fontSize: 13.5, fontWeight: FontWeight.w800))),
              if (widget.trailing != null) widget.trailing!,
            ],
          ),
        ),
      ),
    );
  }
}

class _SubItem extends StatelessWidget {
  const _SubItem(this.text, this.onTap);

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).brightness == Brightness.dark ? NewUi.textMutedDark : NewUi.textMutedLight;
    return InkWell(
      borderRadius: BorderRadius.circular(9),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(
          children: [
            Container(width: 4, height: 4, decoration: BoxDecoration(color: muted, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: muted))),
          ],
        ),
      ),
    );
  }
}
