import 'dart:developer' as developer;
import 'dart:ui';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:smartnps360/src/screens/controllers/usercontroller.dart';
import 'package:smartnps360/src/screens/services/apiservice.dart';
import 'package:smartnps360/src/screens/utilities/const.dart';
import 'package:image_picker/image_picker.dart';

import 'package:smartnps360/src/screens/data/api.url.dart';
import 'package:smartnps360/src/screens/utilities/appsnackbar.dart';

void _log(String msg, {String tag = 'APP', Object? error, StackTrace? stack}) {
  if (kDebugMode) {
    developer.log(msg, name: tag, error: error, stackTrace: stack);
  }
}

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final textSize = 15.5;
  final RxBool _canSave = false.obs;
  String _initialName = '';
  final Rx<File?> _pickedImage = Rx<File?>(null);
  final RxBool _isLoading = false.obs;

  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _dobController = TextEditingController();
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _zipController = TextEditingController();
  final _emergencyNameController = TextEditingController();
  final _relationshipController = TextEditingController();
  final _emergencyPhoneController = TextEditingController();
  final _employeeController = TextEditingController();
  final _roleController = TextEditingController();
  final UserController _userCtrl = Get.find<UserController>();
  final ApiService _apiService = ApiService();

  @override
  void initState() {
    super.initState();
    if (_userCtrl.profileData.value == null) {
      _userCtrl.fetchProfileData().then((_) => _populateFromProfile());
    } else {
      _populateFromProfile();
    }

    ever(_userCtrl.profileData, (_) => _populateFromProfile());
    _nameController.addListener(_updateCanSave);
    // Add listener for picked image
    ever(_pickedImage, (_) => _updateCanSave());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _dobController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _zipController.dispose();
    _emergencyNameController.dispose();
    _relationshipController.dispose();
    _emergencyPhoneController.dispose();
    _employeeController.dispose();
    _roleController.dispose();
    super.dispose();
  }

  Future<void> pickImage(Rx<File?> fileVar, ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, imageQuality: 75);
    if (picked != null) {
      fileVar.value = File(picked.path);
    }
  }

  // Kept same as your previously used Change Photo bottom sheet.
  void _showImageSourceSheet(BuildContext context, Rx<File?> fileVar) {
    final h = MediaQuery.of(context).size.height;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDark
                      ? [
                          cDarkCardColor.withAlpha(230),
                          cDarkBackground.withAlpha(204),
                        ]
                      : [
                          Colors.white.withAlpha(115),
                          Colors.white.withAlpha(38),
                        ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
                border: Border.all(
                  color: isDark
                      ? cDarkBorderColor.withAlpha(166)
                      : Colors.white.withAlpha(64),
                ),
              ),
              padding: EdgeInsets.fromLTRB(16, 20, 16, h * 0.03),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 80,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 22),
                      decoration: BoxDecoration(
                        color: isDark
                            ? cDarkTextSecondary.withAlpha(166)
                            : Colors.white.withAlpha(179),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              Navigator.of(ctx).pop();
                              pickImage(fileVar, ImageSource.gallery);
                            },
                            child: Container(
                              height: 56,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                color: isDark
                                    ? cDarkInputFillColor
                                    : Colors.white.withAlpha(179),
                                border: Border.all(
                                  color: isDark
                                      ? cDarkBorderColor
                                      : Colors.white.withAlpha(204),
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  'Gallery',
                                  style: TextStyle(
                                    color: isDark ? cDarkTextPrimary : null,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              Navigator.of(ctx).pop();
                              pickImage(fileVar, ImageSource.camera);
                            },
                            child: Container(
                              height: 56,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                color: isDark
                                    ? cDarkInputFillColor
                                    : Colors.white.withAlpha(179),
                                border: Border.all(
                                  color: isDark
                                      ? cDarkBorderColor
                                      : Colors.white.withAlpha(204),
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  'Camera',
                                  style: TextStyle(
                                    color: isDark ? cDarkTextPrimary : null,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _updateCanSave() {
    _canSave.value =
        _nameController.text.trim() != _initialName ||
        _pickedImage.value != null; // Check if image is selected
  }

  void _populateFromProfile() {
    final p = _userCtrl.profileData.value ?? {};
    _nameController.text = p['fullName']?.toString() ?? '';
    _initialName = _nameController.text; // store initial name
    _usernameController.text = p['username']?.toString() ?? '';
    _emailController.text = p['email']?.toString() ?? '';
    _phoneController.text = p['phone']?.toString() ?? '';
    _dobController.text = p['dateOfBirth']?.toString() ?? '';
    _addressController.text = p['address']?.toString() ?? '';
    _cityController.text = p['city']?.toString() ?? '';
    _stateController.text = p['state']?.toString() ?? '';
    _zipController.text = p['zipCode']?.toString() ?? '';
    _emergencyNameController.text = p['emergencyContactName']?.toString() ?? '';
    _relationshipController.text =
        p['emergencyContactRelationship']?.toString() ?? '';
    _emergencyPhoneController.text =
        p['emergencyContactPhone']?.toString() ?? '';
    _employeeController.text = p['employeeId']?.toString() ?? '';
    _roleController.text = p['role']?.toString() ?? '';
    _updateCanSave();
  }

  String? _validateField(String? value, String label) {
    if (value == null || value.trim().isEmpty) {
      return "Please enter your $label";
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: false,
      // ignore: deprecated_member_use
      onPopInvoked: (didPop) {
        if (didPop) return;
        if (FocusManager.instance.primaryFocus != null &&
            FocusManager.instance.primaryFocus!.hasFocus) {
          FocusManager.instance.primaryFocus?.unfocus();
        } else {
          Get.back();
        }
      },
      child: Scaffold(
        backgroundColor: isDark ? cDarkBackground : cMainBg,
        body: Stack(
          children: [
            SafeArea(
              child: Column(
                children: [
                  _buildHeader(context),
                  Expanded(
                    child: Form(
                      key: _formKey,
                      child: ListView(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
                        children: [
                          _buildProfilePhotoSection(context),
                          const SizedBox(height: 18),
                          _sectionHeader("Personal Information"),
                          const SizedBox(height: 8),
                          _buildSectionCard(_personalInfoRows(context)),
                          const SizedBox(height: 18),
                          _sectionHeader("Emergency Contact"),
                          const SizedBox(height: 8),
                          _buildSectionCard(_emergencyInfoRows()),
                          const SizedBox(height: 18),
                          _sectionHeader("Employment Details"),
                          const SizedBox(height: 8),
                          _buildSectionCard(_employmentInfoRows()),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Obx(
              () => _isLoading.value
                  ? Container(
                      color: Colors.black.withAlpha(isDark ? 166 : 128),
                      child: const Center(child: CircularProgressIndicator()),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
        bottomNavigationBar: Obx(
          () => _isLoading.value
              ? const SizedBox.shrink()
              : _bottomButtons(context),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textTheme = theme.textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          _BackCircleButton(onTap: () => Get.back()),
          const SizedBox(width: 12),
          Expanded(
            child: Center(
              child: Text(
                'Edit Profile',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    textTheme.titleMedium?.copyWith(
                      color: isDark
                          ? cDarkTextPrimary
                          : const Color(0xFF0F172A),
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ) ??
                    TextStyle(
                      color: isDark
                          ? cDarkTextPrimary
                          : const Color(0xFF0F172A),
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildProfilePhotoSection(BuildContext context) {
    final p = _userCtrl.profileData.value ?? {};
    final photoUrl = p['photoURL']?.toString();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
      decoration: _iosCardDecoration(context),
      child: Column(
        children: [
          Obx(() {
            Widget avatar;
            if (_pickedImage.value != null) {
              avatar = CircleAvatar(
                radius: 50,
                backgroundColor: Colors.transparent,
                backgroundImage: FileImage(_pickedImage.value!),
              );
            } else if (photoUrl != null && photoUrl.isNotEmpty) {
              avatar = CircleAvatar(
                radius: 50,
                backgroundColor: Colors.transparent,
                backgroundImage: NetworkImage(photoUrl),
              );
            } else {
              avatar = CircleAvatar(
                radius: 50,
                backgroundColor: isDark
                    ? cDarkDividerColor
                    : const Color(0xFFE9EEF4),
                child: Icon(
                  Icons.person_rounded,
                  size: 48,
                  color: isDark ? cDarkIconColor : const Color(0xFF8B93A3),
                ),
              );
            }

            return Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isDark ? cDarkBorderColor : const Color(0xFFE6EAF0),
                  width: 1,
                ),
              ),
              child: avatar,
            );
          }),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: () => _showImageSourceSheet(context, _pickedImage),
            icon: const Icon(Icons.photo_camera_outlined, size: 18),
            label: const Text("Change Photo"),
            style: TextButton.styleFrom(
              foregroundColor: cPrimary,
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        color: isDark ? cDarkTextPrimary : const Color(0xFF1F2937),
      ),
    );
  }

  Widget _buildSectionCard(List<Widget> children) {
    final separated = <Widget>[];
    for (int i = 0; i < children.length; i++) {
      separated.add(children[i]);
      if (i != children.length - 1) separated.add(_iosDivider(context));
    }

    return Container(
      decoration: _iosCardDecoration(context),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(children: separated),
    );
  }

  List<Widget> _personalInfoRows(BuildContext context) {
    return [
      _editableNameRow(context),
      _readOnlyRow(
        context,
        label: 'Username',
        value: _usernameController.text,
        icon: Icons.account_circle_outlined,
      ),
      _readOnlyRow(
        context,
        label: 'Email',
        value: _emailController.text,
        icon: Icons.email_outlined,
      ),
      _readOnlyRow(
        context,
        label: 'Phone',
        value: _phoneController.text,
        icon: Icons.phone_outlined,
      ),
      _readOnlyRow(
        context,
        label: 'Date of Birth',
        value: _dobController.text,
        icon: Icons.calendar_today_outlined,
      ),
      _readOnlyRow(
        context,
        label: 'Address',
        value: _addressController.text,
        icon: Icons.location_on_outlined,
      ),
      _readOnlyRow(
        context,
        label: 'City',
        value: _cityController.text,
        icon: Icons.location_city_outlined,
      ),
      _cityStateRow(context),
    ];
  }

  List<Widget> _emergencyInfoRows() {
    return [
      _readOnlyRow(
        context,
        label: 'Emergency Contact Name',
        value: _emergencyNameController.text,
        icon: Icons.person_outline,
      ),
      _readOnlyRow(
        context,
        label: 'Relationship',
        value: _relationshipController.text,
        icon: Icons.group_outlined,
      ),
      _readOnlyRow(
        context,
        label: 'Emergency Phone',
        value: _emergencyPhoneController.text,
        icon: Icons.phone_iphone_outlined,
      ),
    ];
  }

  List<Widget> _employmentInfoRows() {
    return [
      _readOnlyRow(
        context,
        label: 'Employee #',
        value: _employeeController.text,
        icon: Icons.badge_outlined,
      ),
      _readOnlyRow(
        context,
        label: 'Role',
        value: _roleController.text,
        icon: Icons.security_outlined,
      ),
    ];
  }

  Widget _editableNameRow(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          _rowIcon(context, Icons.person_outline),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _rowLabel(context, 'Full Name'),
                TextFormField(
                  controller: _nameController,
                  validator: (v) => _validateField(v, "full name"),
                  textCapitalization: TextCapitalization.words,
                  cursorColor: cPrimary,
                  style: TextStyle(
                    fontSize: textSize,
                    fontWeight: FontWeight.w500,
                    color: isDark ? cDarkTextPrimary : const Color(0xFF111827),
                    height: 1.2,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Enter full name',
                    hintStyle: TextStyle(
                      color: isDark
                          ? cDarkTextSecondary
                          : const Color(0xFF9CA3AF),
                      fontSize: textSize,
                    ),
                    contentPadding: const EdgeInsets.only(top: 4, bottom: 2),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _readOnlyRow(
    BuildContext context, {
    required String label,
    required String? value,
    required IconData icon,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final displayValue = (value ?? '').trim().isEmpty
        ? '– – – – –'
        : value!.trim();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          _rowIcon(context, icon),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _rowLabel(context, label),
                const SizedBox(height: 3),
                Text(
                  displayValue,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: textSize,
                    fontWeight: FontWeight.w500,
                    color: isDark ? cDarkTextPrimary : const Color(0xFF111827),
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cityStateRow(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget compactItem({
      required String label,
      required String? value,
      required IconData icon,
    }) {
      final displayValue = (value ?? '').trim().isEmpty
          ? '– – – – –'
          : value!.trim();
      return Expanded(
        child: Row(
          children: [
            _rowIcon(context, icon),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _rowLabel(context, label),
                  const SizedBox(height: 3),
                  Text(
                    displayValue,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: textSize,
                      fontWeight: FontWeight.w500,
                      color: isDark
                          ? cDarkTextPrimary
                          : const Color(0xFF111827),
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          compactItem(
            label: 'ZIP Code',
            value: _zipController.text,
            icon: Icons.local_post_office_outlined,
          ),
          Container(
            width: 1,
            height: 42,
            margin: const EdgeInsets.symmetric(horizontal: 10),
            color: isDark ? cDarkBorderColor : const Color(0xFFE7EBF0),
          ),
          compactItem(
            label: 'State',
            value: _stateController.text,
            icon: Icons.map_outlined,
          ),
        ],
      ),
    );
  }

  Widget _rowIcon(BuildContext context, IconData icon) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: isDark ? cDarkInputFillColor : const Color(0xFFF3F6FA),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(
        icon,
        size: 22,
        color: isDark ? cDarkIconColor : const Color(0xFF6B7280),
      ),
    );
  }

  Widget _rowLabel(BuildContext context, String label) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w500,
        color: isDark ? cDarkTextSecondary : const Color(0xFF5F6B7A),
        height: 1.1,
      ),
    );
  }

  Widget _iosDivider(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(left: 54),
      child: Container(
        height: 1,
        color: isDark ? cDarkBorderColor : const Color(0xFFE9EDF3),
      ),
    );
  }

  BoxDecoration _iosCardDecoration(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return BoxDecoration(
      color: isDark ? cDarkCardColor : Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(
        color: isDark ? cDarkBorderColor : const Color(0xFFE8ECF2),
        width: 1,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withAlpha(isDark ? 46 : 10),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }

  Widget _bottomButtons(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      child: Container(
        padding: const EdgeInsets.all(0),
        child: Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 52,
                child: OutlinedButton(
                  onPressed: () {
                    FocusManager.instance.primaryFocus?.unfocus();
                    Get.back();
                  },
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: isDark
                          ? cDarkBorderColor
                          : const Color(0xFFC8CDD4),
                    ),
                    backgroundColor: isDark ? cDarkCardColor : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    "Cancel",
                    style: TextStyle(
                      fontSize: 16,
                      color: isDark
                          ? cDarkTextPrimary
                          : const Color(0xFF111827),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Obx(
                () => SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _canSave.value ? _saveProfile : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cPrimary,
                      disabledBackgroundColor: isDark
                          ? cDarkDividerColor
                          : const Color(0xFFD6D8DC),
                      elevation: _canSave.value ? 2 : 0,
                      shadowColor: cPrimary.withAlpha(70),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      "Save Changes",
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveProfile() async {
    FocusScope.of(context).unfocus();

    if (_pickedImage.value == null &&
        _nameController.text.trim() == _initialName) {
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    _isLoading.value = true;

    try {
      final payload = <String, dynamic>{
        'fullName': _nameController.text.trim(),
      };

      if (_pickedImage.value != null) {
        final response = await _apiService.postMultipartSingleFile(
          ApiURL.updateProfile,
          fields: payload,
          file: _pickedImage.value!,
          fileFieldName: 'photo',
        );
        if (response.statusCode == 200 && response.data != null) {
          final data = response.data;
          if (data is Map<String, dynamic>) {
            _userCtrl.profileData.value = Map<String, dynamic>.from(data);
          }
          if (mounted) {
            _isLoading.value = false;
            Get.back();
            AppSnackBar.show(
              context,
              'Profile updated successfully',
              type: SnackBarType.success,
            );
          }
        } else {
          if (mounted) {
            AppSnackBar.show(
              context,
              'Failed to update profile',
              type: SnackBarType.error,
            );
          }
        }
      } else {
        final resp = await _apiService.putData(ApiURL.updateProfile, payload);
        final data = resp.data;
        if (mounted) {
          _userCtrl.profileData.value = Map<String, dynamic>.from(data);
          Get.back();
          AppSnackBar.show(
            context,
            'Profile updated successfully',
            type: SnackBarType.success,
          );
        }
      }
    } catch (e) {
      _log('Error uploading profile', tag: 'Profile', error: e);
      if (mounted) {
        String errorMessage = 'Failed to update profile. Please try again.';
        if (e is Exception) {
          final exceptionMessage = e.toString().replaceFirst('Exception: ', '');
          if (exceptionMessage.isNotEmpty) {
            errorMessage = exceptionMessage;
          }
        }
        AppSnackBar.show(context, errorMessage, type: SnackBarType.error);
      }
    } finally {
      _isLoading.value = false;
    }
  }
}

class _BackCircleButton extends StatelessWidget {
  final VoidCallback onTap;

  const _BackCircleButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      overlayColor: const WidgetStatePropertyAll(cTransparent),
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: isDark ? cDarkCardColor : cWhite,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(isDark ? 45 : 10),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(
          Icons.arrow_back_ios_new_rounded,
          size: 19,
          color: isDark ? cDarkIconColor : const Color(0xFF0F172A),
        ),
      ),
    );
  }
}
