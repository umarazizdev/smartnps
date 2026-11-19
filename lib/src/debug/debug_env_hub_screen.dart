import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/native_theme_controller.dart';
import '../dispatch/dispatch_request_screen.dart';
import '../push/notifications/push_notification_service.dart';
import '../utilities/app_config.dart';
import 'debug_env_api_responses_screen.dart';
import 'debug_env_logs_screen.dart';
import 'debug_env_theme.dart';
import 'debug_env_urls_screen.dart';

class DebugEnvHubScreen extends StatelessWidget {
  const DebugEnvHubScreen({super.key});

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  Future<void> _runTestAlert(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await PushNotificationService.instance.showTestAlert();
    final ok = result['ok'] == true;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Urgent tone + 30s vibration started (debug only).'
              : 'Test alert failed: ${result['error'] ?? 'unknown'}',
        ),
      ),
    );
  }

  Future<void> _openDispatchTest(BuildContext context) async {
    final defaults = const DispatchRequestScreen().request;
    final site = await showDialog<_DispatchSiteCoords>(
      context: context,
      builder: (context) => _DispatchSiteCoordsDialog(
        initial: _DispatchSiteCoords(
          latitude: defaults.siteLatitude,
          longitude: defaults.siteLongitude,
        ),
      ),
    );
    if (!context.mounted || site == null) return;
    _open(
      context,
      DispatchRequestScreen(
        request: DispatchRequestData(
          address: defaults.address,
          city: defaults.city,
          summary: defaults.summary,
          score: defaults.score,
          arrivalMinutes: defaults.arrivalMinutes,
          distanceMiles: defaults.distanceMiles,
          siteLatitude: site.latitude,
          siteLongitude: site.longitude,
          responseSeconds: defaults.responseSeconds,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = NativeThemeController.instance.isDark;
    final colors = DebugEnvColors.of(isDark);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: const Color(AppConfig.cPrimary),
        foregroundColor: Colors.white,
        centerTitle: false,
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text(
          'Developer tools',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        children: [
          _HubCard(
            colors: colors,
            icon: Icons.notifications_active_rounded,
            title: 'Test push alert + vibration',
            onTap: () => _runTestAlert(context),
          ),
          const SizedBox(height: 14),
          _HubCard(
            colors: colors,
            icon: Icons.map_rounded,
            title: 'Dispatch response (test)',
            onTap: () => _openDispatchTest(context),
          ),
          const SizedBox(height: 14),
          _HubCard(
            colors: colors,
            icon: Icons.terminal_rounded,
            title: 'Diagnostic logging',
            onTap: () => _open(context, const DebugEnvLogsScreen()),
          ),
          const SizedBox(height: 14),
          _HubCard(
            colors: colors,
            icon: Icons.data_object_rounded,
            title: 'API response logging',
            onTap: () => _open(context, const DebugEnvApiResponsesScreen()),
          ),
          const SizedBox(height: 14),
          _HubCard(
            colors: colors,
            icon: Icons.language_rounded,
            title: 'Environment endpoints',
            onTap: () => _open(context, const DebugEnvUrlsScreen()),
          ),
        ],
      ),
    );
  }
}

@immutable
class _DispatchSiteCoords {
  const _DispatchSiteCoords({
    required this.latitude,
    required this.longitude,
  });

  final double latitude;
  final double longitude;
}

class _DispatchSiteCoordsDialog extends StatefulWidget {
  const _DispatchSiteCoordsDialog({required this.initial});

  final _DispatchSiteCoords initial;

  @override
  State<_DispatchSiteCoordsDialog> createState() =>
      _DispatchSiteCoordsDialogState();
}

class _DispatchSiteCoordsDialogState extends State<_DispatchSiteCoordsDialog> {
  late final TextEditingController _latController;
  late final TextEditingController _lngController;
  String? _error;

  @override
  void initState() {
    super.initState();
    _latController = TextEditingController(
      text: widget.initial.latitude.toString(),
    );
    _lngController = TextEditingController(
      text: widget.initial.longitude.toString(),
    );
  }

  @override
  void dispose() {
    _latController.dispose();
    _lngController.dispose();
    super.dispose();
  }

  void _submit() {
    final lat = double.tryParse(_latController.text.trim());
    final lng = double.tryParse(_lngController.text.trim());
    if (lat == null || lng == null) {
      setState(() => _error = 'Enter valid latitude and longitude.');
      return;
    }
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
      setState(() => _error = 'Latitude/longitude out of range.');
      return;
    }
    Navigator.of(context).pop(
      _DispatchSiteCoords(latitude: lat, longitude: lng),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = NativeThemeController.instance.isDark;
    final colors = DebugEnvColors.of(isDark);

    return AlertDialog(
      backgroundColor: colors.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        'Site coordinates',
        style: TextStyle(
          color: colors.title,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Paste a teammate’s location to use as the dispatch site.',
              style: TextStyle(color: colors.subtitle, fontSize: 13, height: 1.35),
            ),
            const SizedBox(height: 16),
            _CoordField(
              colors: colors,
              label: 'Latitude',
              controller: _latController,
              hint: 'e.g. 28.47774',
            ),
            const SizedBox(height: 12),
            _CoordField(
              colors: colors,
              label: 'Longitude',
              controller: _lngController,
              hint: 'e.g. 70.40424',
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: colors.error, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel', style: TextStyle(color: colors.subtitle)),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(AppConfig.cPrimary),
            foregroundColor: Colors.white,
          ),
          child: const Text('Open dispatch'),
        ),
      ],
    );
  }
}

class _CoordField extends StatelessWidget {
  const _CoordField({
    required this.colors,
    required this.label,
    required this.controller,
    required this.hint,
  });

  final DebugEnvColors colors;
  final String label;
  final TextEditingController controller;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: colors.label,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9\.\-]')),
          ],
          style: TextStyle(color: colors.title, fontSize: 15),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: colors.subtitle),
            filled: true,
            fillColor: colors.fieldBg,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: colors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: colors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(
                color: Color(AppConfig.cPrimary),
                width: 1.4,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _HubCard extends StatelessWidget {
  const _HubCard({
    required this.colors,
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final DebugEnvColors colors;
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colors.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 18, 16, 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.cardBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(
                    AppConfig.cPrimary,
                  ).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: const Color(AppConfig.cPrimary),
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: colors.title,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: colors.subtitle),
            ],
          ),
        ),
      ),
    );
  }
}
