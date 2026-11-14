import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:smartnps360/src/screens/utilities/const.dart';
import 'package:smartnps360/src/screens/new_screens/Widgets/new_common_widgets.dart';
import 'new_profile_controller.dart';

class NewProfileScreen extends StatelessWidget {
  const NewProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(NewProfileController());
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 110),
      children: [
        Text('Profile', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 14),
        Obx(
          () => NewGlassCard(
            child: Column(
              children: [
                CircleAvatar(radius: 42, backgroundColor: cPrimary, child: Text(controller.initials, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 22))),
                const SizedBox(height: 12),
                Text(controller.name.value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                NewPill(text: controller.active.value ? 'Active · ${controller.role.value}' : controller.role.value, icon: Icons.verified_rounded, color: cGreen),
                const SizedBox(height: 16),
                _ProfileRow(icon: Icons.phone_rounded, title: 'Phone', value: controller.phone.value),
                _ProfileRow(icon: Icons.email_rounded, title: 'Email', value: controller.email.value),
                _ProfileRow(icon: Icons.location_on_rounded, title: 'Primary Site', value: 'BayCrest'),
                const SizedBox(height: 14),
                SizedBox(width: double.infinity, child: NewActionButton(text: 'Edit Profile', icon: Icons.edit_rounded, onTap: () => _openEdit(context, controller))),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        const NewGlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              NewSectionTitle(title: 'Account Summary', icon: Icons.badge_rounded),
              _StaticRow(title: 'Employee ID', value: 'NPS-1042'),
              _StaticRow(title: 'Role', value: 'On-Site Officer'),
              _StaticRow(title: 'Status', value: 'Available'),
              _StaticRow(title: 'App Version', value: 'v3.0 Preview'),
            ],
          ),
        ),
      ],
    );
  }

  void _openEdit(BuildContext context, NewProfileController controller) {
    controller.openEditDialog();
    Get.dialog(
      AlertDialog(
        title: const Text('Edit Profile'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(radius: 36, backgroundColor: cPrimary, child: Text(controller.initials, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900))),
              const SizedBox(height: 12),
              TextField(controller: controller.nameCtrl, decoration: const InputDecoration(labelText: 'Full Name', border: OutlineInputBorder())),
              const SizedBox(height: 10),
              TextField(controller: controller.phoneCtrl, decoration: const InputDecoration(labelText: 'Phone', border: OutlineInputBorder())),
              const SizedBox(height: 10),
              TextField(controller: controller.emailCtrl, decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder())),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: Get.back, child: const Text('Cancel')),
          ElevatedButton(onPressed: controller.saveProfile, child: const Text('Save')),
        ],
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({required this.icon, required this.title, required this.value});

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 19, color: cPrimary),
          const SizedBox(width: 10),
          Expanded(child: Text(title, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cDarkGreyclr, fontWeight: FontWeight.w700))),
          Flexible(child: Text(value, textAlign: TextAlign.right, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800))),
        ],
      ),
    );
  }
}

class _StaticRow extends StatelessWidget {
  const _StaticRow({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(child: Text(title, style: TextStyle(color: cDarkGreyclr, fontWeight: FontWeight.w700))),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}
