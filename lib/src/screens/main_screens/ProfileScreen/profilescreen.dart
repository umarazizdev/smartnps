import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:smartnps360/src/screens/controllers/usercontroller.dart';
import 'package:smartnps360/src/screens/main_screens/ProfileScreen/editprofilescreen.dart';
import 'package:smartnps360/src/screens/main_screens/SettingsScreen/settingscreen.dart';
import 'package:smartnps360/src/screens/utilities/const.dart';
import 'package:shimmer/shimmer.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final UserController _userCtrl = Get.find<UserController>();

  bool _isRefreshing = false;

  Future<void> _onRefresh() async {
    setState(() => _isRefreshing = true);

    await _userCtrl.fetchProfileData(forceRefresh: true, enableLoading: false);

    if (mounted) {
      setState(() => _isRefreshing = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _userCtrl.fetchProfileData(enableLoading: false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: isDark ? cDarkBackground : cMainBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            children: [
              _isRefreshing
                  ? Align(
                      alignment: Alignment.centerLeft,
                      child: Shimmer.fromColors(
                        baseColor: isDark
                            ? cDarkBorderColor
                            : Colors.grey.shade300,
                        highlightColor: isDark
                            ? cDarkCardColor.withAlpha(128)
                            : Colors.grey.shade100,
                        child: Container(
                          height: 30,
                          width: 155,
                          decoration: BoxDecoration(
                            color: isDark
                                ? cDarkBorderColor.withAlpha(179)
                                : Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'My Profile',
                          style:
                              textTheme.headlineMedium?.copyWith(
                                fontSize: 24,
                                height: 1.05,
                                fontWeight: FontWeight.w700,
                                color: isDark
                                    ? cDarkTextPrimary
                                    : const Color(0xFF0F172A),
                                letterSpacing: -0.5,
                              ) ??
                              TextStyle(
                                fontSize: 30,
                                height: 1.05,
                                fontWeight: FontWeight.w700,
                                color: isDark
                                    ? cDarkTextPrimary
                                    : const Color(0xFF0F172A),
                                letterSpacing: -0.5,
                              ),
                        ),
                        _SettingsButton(
                          onTap: () => showSettingsBottomSheet(context),
                        ),
                      ],
                    ),
              const SizedBox(height: 16),
              Expanded(
                child: Obx(() {
                  if (_userCtrl.profileData.value == null) {
                    return _buildProfileShimmer();
                  }

                  final profile = _userCtrl.profileData.value ?? {};
                  final name = _displayValue(
                    profile['fullName'],
                    'Officer Name',
                  );
                  final email = _displayValue(
                    profile['email'],
                    'no-email@example.com',
                  );
                  final photo = profile['photoURL'] as String?;

                  final content = RefreshIndicator(
                    displacement: 36.0,
                    strokeWidth: 2.5,
                    color: cPrimary,
                    onRefresh: _onRefresh,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(bottom: 118),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildProfileHeaderCard(
                            context: context,
                            name: name,
                            email: email,
                            photo: photo,
                          ),
                          const SizedBox(height: 16),
                          _sectionHeader('Personal Information'),
                          const SizedBox(height: 8),
                          _buildInfoCard(
                            children: [
                              _ProfileInfoRow(
                                icon: Icons.person_outline_rounded,
                                label: 'Username',
                                value: _displayValue(profile['username']),
                              ),
                              _ProfileInfoRow(
                                icon: Icons.phone_outlined,
                                label: 'Phone',
                                value: _displayValue(profile['phone']),
                              ),
                              _ProfileInfoRow(
                                icon: Icons.calendar_today_outlined,
                                label: 'Date of Birth',
                                value: _displayValue(profile['dateOfBirth']),
                              ),
                              _ProfileInfoRow(
                                icon: Icons.location_on_outlined,
                                label: 'Address',
                                value: _displayValue(profile['address']),
                              ),
                              _ProfileInfoRow(
                                icon: Icons.location_city_outlined,
                                label: 'City',
                                value: _displayValue(profile['city']),
                              ),
                              _ProfileInfoRowPair(
                                leftIcon: Icons.map_outlined,
                                leftLabel: 'State',
                                leftValue: _displayValue(profile['state']),
                                rightIcon: Icons.local_post_office_outlined,
                                rightLabel: 'ZIP Code',
                                rightValue: _displayValue(profile['zipCode']),
                                showDivider: false,
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _sectionHeader('Emergency Contact'),
                          const SizedBox(height: 8),
                          _buildInfoCard(
                            children: [
                              _ProfileInfoRow(
                                icon: Icons.person_outline_rounded,
                                label: 'Contact Name',
                                value: _displayValue(
                                  profile['emergencyContactName'],
                                ),
                              ),
                              _ProfileInfoRow(
                                icon: Icons.group_outlined,
                                label: 'Relationship',
                                value: _displayValue(
                                  profile['emergencyContactRelationship'],
                                ),
                              ),
                              _ProfileInfoRow(
                                icon: Icons.phone_iphone_outlined,
                                label: 'Emergency Phone',
                                value: _displayValue(
                                  profile['emergencyContactPhone'],
                                ),
                                showDivider: false,
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _sectionHeader('Employment Details'),
                          const SizedBox(height: 8),
                          _buildInfoCard(
                            children: [
                              _ProfileInfoRow(
                                icon: Icons.badge_outlined,
                                label: 'Employee #',
                                value: _displayValue(profile['employeeId']),
                              ),
                              _ProfileInfoRow(
                                icon: Icons.security_outlined,
                                label: 'Role',
                                value: _displayValue(
                                  profile['role']?.toString().toUpperCase(),
                                ),
                                showDivider: false,
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _sectionHeader('Documents'),
                          const SizedBox(height: 8),
                          _buildDocumentsCard(),
                        ],
                      ),
                    ),
                  );

                  return _withRefreshShimmerOverlay(child: content);
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _displayValue(dynamic value, [String fallback = 'N/A']) {
    final str = value?.toString().trim() ?? '';
    return str.isNotEmpty ? str : fallback;
  }

  Widget _buildProfileHeaderCard({
    required BuildContext context,
    required String name,
    required String email,
    required String? photo,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _softCardDecoration(context),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDark ? cDarkBorderColor : Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(isDark ? 45 : 12),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: CircleAvatar(
              radius: 29,
              backgroundColor: isDark
                  ? cDarkBorderColor
                  : const Color(0xFFE9EEF5),
              backgroundImage: photo != null && photo.isNotEmpty
                  ? NetworkImage(photo)
                  : null,
              child: photo == null || photo.isEmpty
                  ? Text(
                      name.isNotEmpty ? name[0].toUpperCase() : 'O',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: isDark ? cDarkTextPrimary : cPrimary,
                      ),
                    )
                  : null,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      textTheme.titleMedium?.copyWith(
                        fontSize: 17,
                        height: 1.15,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? cDarkTextPrimary
                            : const Color(0xFF111827),
                        letterSpacing: -0.2,
                      ) ??
                      TextStyle(
                        fontSize: 20,
                        height: 1.15,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? cDarkTextPrimary
                            : const Color(0xFF111827),
                      ),
                ),
                const SizedBox(height: 5),
                Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodyMedium?.copyWith(
                    fontSize: 14,
                    height: 1.2,
                    color: isDark
                        ? cDarkTextSecondary
                        : const Color(0xFF6B7280),
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          InkWell(
            overlayColor: const WidgetStatePropertyAll(cTransparent),
            borderRadius: BorderRadius.circular(16),
            onTap: () => Get.to(const EditProfileScreen()),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isDark ? cDarkInputFillColor : const Color(0xFFF4F7FB),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(
                  color: isDark ? cDarkBorderColor : const Color(0xFFE6EBF2),
                  width: 1,
                ),
              ),
              child: Center(
                child: Image.asset(
                  'assets/Icons/edit-text.png',
                  color: isDark ? cDarkIconColor : cPrimary,
                  height: 19,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Text(
      title,
      style: TextStyle(
        fontSize: 16,
        height: 1.15,
        fontWeight: FontWeight.w700,
        color: isDark ? cDarkTextPrimary : const Color(0xFF111827),
        letterSpacing: -0.1,
      ),
    );
  }

  Widget _buildInfoCard({required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 3),
      decoration: _softCardDecoration(context),
      child: Column(children: children),
    );
  }

  Widget _buildDocumentsCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _softCardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _InfoIconBox(icon: Icons.credit_card_outlined, isDark: isDark),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Driver’s License / ID / Passport',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.25,
                    color: isDark ? cDarkTextPrimary : const Color(0xFF111827),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildDocumentPreview(),
        ],
      ),
    );
  }

  BoxDecoration _softCardDecoration(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return BoxDecoration(
      color: isDark ? cDarkCardColor : Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color: isDark
            ? cDarkBorderColor.withAlpha(130)
            : const Color(0xFFE9EEF5),
        width: 1,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withAlpha(isDark ? 42 : 10),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }

  Widget _withRefreshShimmerOverlay({required Widget child}) {
    if (!_isRefreshing) return child;

    return Stack(
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            ignoring: true,
            child: Container(
              color:
                  (Theme.of(context).brightness == Brightness.dark
                          ? cDarkBackground
                          : cMainBg)
                      .withAlpha(166),
              child: _buildProfileShimmer(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDocumentPreview() {
    return InkWell(
      onTap: () {
        showDialog(
          context: context,
          barrierColor: Colors.black.withAlpha(
            Theme.of(context).brightness == Brightness.dark ? 217 : 242,
          ),
          builder: (_) {
            final size = MediaQuery.of(context).size;
            return Dialog(
              insetPadding: EdgeInsets.zero,
              backgroundColor: Colors.transparent,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: SizedBox(
                  width: size.width,
                  height: size.height,
                  child: InteractiveViewer(
                    child: Center(
                      child: Image.network(
                        'https://acko-cms.ackoassets.com/how_to_get_duplicate_driving_licence_1cac56a965.jpg',
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
      borderRadius: BorderRadius.circular(16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Image.network(
            'https://acko-cms.ackoassets.com/how_to_get_duplicate_driving_licence_1cac56a965.jpg',
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              final isDark = Theme.of(context).brightness == Brightness.dark;
              return Container(
                color: isDark ? cDarkBorderColor : const Color(0xFFF1F5F9),
                child: Icon(
                  Icons.broken_image_outlined,
                  color: isDark ? cDarkIconColor : const Color(0xFF94A3B8),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildProfileShimmer() {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: _softCardDecoration(context),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: const [
                _SContentCircle(size: 58),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SContentLine(height: 18, widthFactor: 0.56, radius: 8),
                      SizedBox(height: 8),
                      _SContentLine(height: 14, widthFactor: 0.42, radius: 8),
                    ],
                  ),
                ),
                SizedBox(width: 10),
                _SContentBox(height: 38, width: 38, radius: 13),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const _SContentLine(height: 18, widthFactor: 0.42, radius: 8),
          const SizedBox(height: 8),
          _buildShimmerCard(rows: 6),
          const SizedBox(height: 16),
          const _SContentLine(height: 18, widthFactor: 0.40, radius: 8),
          const SizedBox(height: 8),
          _buildShimmerCard(rows: 3),
          const SizedBox(height: 16),
          const _SContentLine(height: 18, widthFactor: 0.40, radius: 8),
          const SizedBox(height: 8),
          _buildShimmerCard(rows: 2),
          const SizedBox(height: 128),
        ],
      ),
    );
  }

  Widget _buildShimmerCard({required int rows}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 3),
      decoration: _softCardDecoration(context),
      child: Column(
        children: List.generate(rows, (index) {
          return const _ProfileFieldRowShimmer();
        }),
      ),
    );
  }
}

class _SettingsButton extends StatelessWidget {
  final VoidCallback onTap;

  const _SettingsButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      overlayColor: const WidgetStatePropertyAll(cTransparent),
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: isDark ? cDarkCardColor : Colors.white,
          shape: BoxShape.circle,
          border: Border.all(
            color: isDark
                ? cDarkBorderColor.withAlpha(130)
                : const Color(0xFFE9EEF5),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(isDark ? 44 : 12),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Center(
          child: Image.asset(
            'assets/Icons/setting.png',
            color: isDark ? cDarkIconColor : const Color(0xFF0F172A),
            height: 19,
          ),
        ),
      ),
    );
  }
}

class _ProfileInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool showDivider;

  const _ProfileInfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _InfoIconBox(icon: icon, isDark: isDark),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.15,
                        fontWeight: FontWeight.w500,
                        color: isDark
                            ? cDarkTextSecondary
                            : const Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.2,
                        fontWeight: FontWeight.w500,
                        color: isDark
                            ? cDarkTextPrimary
                            : const Color(0xFF111827),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            thickness: 0.7,
            indent: 50,
            color: isDark
                ? cDarkBorderColor.withAlpha(140)
                : const Color(0xFFE9EEF5),
          ),
      ],
    );
  }
}

class _ProfileInfoRowPair extends StatelessWidget {
  final IconData leftIcon;
  final String leftLabel;
  final String leftValue;
  final IconData rightIcon;
  final String rightLabel;
  final String rightValue;
  final bool showDivider;

  const _ProfileInfoRowPair({
    required this.leftIcon,
    required this.leftLabel,
    required this.leftValue,
    required this.rightIcon,
    required this.rightLabel,
    required this.rightValue,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _ProfilePairItem(
                  icon: leftIcon,
                  label: leftLabel,
                  value: leftValue,
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ProfilePairItem(
                  icon: rightIcon,
                  label: rightLabel,
                  value: rightValue,
                  isDark: isDark,
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            thickness: 0.7,
            indent: 50,
            color: isDark
                ? cDarkBorderColor.withAlpha(140)
                : const Color(0xFFE9EEF5),
          ),
      ],
    );
  }
}

class _ProfilePairItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool isDark;

  const _ProfilePairItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _InfoIconBox(icon: icon, isDark: isDark),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.15,
                  fontWeight: FontWeight.w500,
                  color: isDark ? cDarkTextSecondary : const Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.2,
                  fontWeight: FontWeight.w500,
                  color: isDark ? cDarkTextPrimary : const Color(0xFF111827),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoIconBox extends StatelessWidget {
  final IconData icon;
  final bool isDark;

  const _InfoIconBox({required this.icon, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: isDark ? cDarkInputFillColor : const Color(0xFFF4F7FB),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Icon(
        icon,
        size: 20,
        color: isDark ? cDarkIconColor : const Color(0xFF667085),
      ),
    );
  }
}

class _ProfileFieldRowShimmer extends StatelessWidget {
  const _ProfileFieldRowShimmer();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _SContentBox(height: 38, width: 38, radius: 13),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SContentLine(height: 11, widthFactor: 0.30, radius: 6),
                SizedBox(height: 7),
                _SContentLine(height: 15, widthFactor: 0.55, radius: 6),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SContentLine extends StatelessWidget {
  final double height;
  final double widthFactor;
  final double radius;

  const _SContentLine({
    required this.height,
    required this.widthFactor,
    this.radius = 6,
  });

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final width = (w * widthFactor).clamp(60.0, w);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Shimmer.fromColors(
      baseColor: isDark ? cDarkBorderColor : Colors.grey.shade300,
      highlightColor: isDark
          ? cDarkCardColor.withAlpha(128)
          : Colors.grey.shade100,
      child: Container(
        height: height,
        width: width,
        decoration: BoxDecoration(
          color: isDark
              ? cDarkBorderColor.withAlpha(179)
              : Colors.grey.shade300,
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}

class _SContentBox extends StatelessWidget {
  final double height;
  final double width;
  final double radius;

  const _SContentBox({
    required this.height,
    required this.width,
    this.radius = 8,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Shimmer.fromColors(
      baseColor: isDark ? cDarkBorderColor : Colors.grey.shade300,
      highlightColor: isDark
          ? cDarkCardColor.withAlpha(128)
          : Colors.grey.shade100,
      child: Container(
        height: height,
        width: width,
        decoration: BoxDecoration(
          color: isDark
              ? cDarkBorderColor.withAlpha(179)
              : Colors.grey.shade300,
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}

class _SContentCircle extends StatelessWidget {
  final double size;
  const _SContentCircle({required this.size});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Shimmer.fromColors(
      baseColor: isDark ? cDarkBorderColor : Colors.grey.shade300,
      highlightColor: isDark
          ? cDarkCardColor.withAlpha(128)
          : Colors.grey.shade100,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: isDark ? cDarkBorderColor.withAlpha(179) : Colors.grey,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
