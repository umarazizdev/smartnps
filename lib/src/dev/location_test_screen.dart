import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';

class LocationTestScreen extends StatelessWidget {
  const LocationTestScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<_LocationTestController>(
      init: _LocationTestController(),
      builder: (controller) {
        final pos = controller.position;
        final now = DateTime.now();
        final age = pos?.timestamp == null
            ? null
            : now.difference(pos!.timestamp).inMilliseconds / 1000.0;

        return Scaffold(
          appBar: AppBar(title: const Text('Location Test')),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                FilledButton(
                  onPressed: controller.loading ? null : controller.getLocation,
                  child: controller.loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Get Location'),
                ),
                const SizedBox(height: 12),
                if (controller.error != null)
                  Text(
                    controller.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                const SizedBox(height: 12),
                _InfoRow(label: 'Latitude', value: pos?.latitude.toString()),
                _InfoRow(label: 'Longitude', value: pos?.longitude.toString()),
                _InfoRow(
                  label: 'Accuracy (m)',
                  value: pos?.accuracy.toStringAsFixed(1),
                ),
                _InfoRow(label: 'GPS age (s)', value: age?.toStringAsFixed(2)),
                _InfoRow(
                  label: 'Timestamp',
                  value: pos?.timestamp.toIso8601String(),
                ),
                _InfoRow(
                  label: 'Altitude',
                  value: pos?.altitude.toStringAsFixed(1),
                ),
                _InfoRow(label: 'Speed', value: pos?.speed.toStringAsFixed(2)),
                _InfoRow(
                  label: 'Heading',
                  value: pos?.heading.toStringAsFixed(1),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LocationTestController extends GetxController {
  bool loading = false;
  String? error;
  Position? position;

  void _setLoading(bool value) {
    loading = value;
    update();
  }

  void _setError(String value) {
    error = value;
    update();
  }

  Future<void> getLocation() async {
    loading = true;
    error = null;
    update();

    try {
      final servicesEnabled = await Geolocator.isLocationServiceEnabled();
      if (!servicesEnabled) {
        _setError('Location services are disabled.');
        return;
      }

      final ph = await Permission.locationWhenInUse.request();
      if (!ph.isGranted) {
        _setError('Location permission denied.');
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        _setError('Location permission denied (Geolocator).');
        return;
      }
      if (permission == LocationPermission.deniedForever) {
        _setError('Location permission denied forever.');
        return;
      }

      final settings = Platform.isAndroid
          ? AndroidSettings(
              accuracy: LocationAccuracy.bestForNavigation,
              distanceFilter: 0,
              intervalDuration: const Duration(seconds: 1),
              timeLimit: const Duration(seconds: 25),
            )
          : AppleSettings(
              accuracy: LocationAccuracy.bestForNavigation,
              distanceFilter: 0,
              timeLimit: const Duration(seconds: 25),
              pauseLocationUpdatesAutomatically: false,
            );

      // A single high-quality fresh fix (no cached fallback).
      Position? best;
      try {
        final stream = Geolocator.getPositionStream(locationSettings: settings);
        await for (final pos in stream.timeout(const Duration(seconds: 25))) {
          best = pos;
          if (pos.accuracy <= 5) break;
        }
      } on TimeoutException {
        // handled below
      }

      if (best == null) {
        _setError('Unable to obtain a fresh GPS fix (timeout).');
        return;
      }

      position = best;
      update();
    } catch (e) {
      _setError(e.toString());
    } finally {
      _setLoading(false);
    }
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: Theme.of(context).textTheme.labelLarge),
          ),
          Expanded(
            child: Text(
              value ?? '-',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
