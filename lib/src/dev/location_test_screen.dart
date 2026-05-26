import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

class LocationTestScreen extends StatefulWidget {
  const LocationTestScreen({super.key});

  @override
  State<LocationTestScreen> createState() => _LocationTestScreenState();
}

class _LocationTestScreenState extends State<LocationTestScreen> {
  bool _loading = false;
  String? _error;
  Position? _position;

  Future<void> _getLocation() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final servicesEnabled = await Geolocator.isLocationServiceEnabled();
      if (!servicesEnabled) {
        setState(() => _error = 'Location services are disabled.');
        return;
      }

      final ph = await Permission.locationWhenInUse.request();
      if (!ph.isGranted) {
        setState(() => _error = 'Location permission denied.');
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        setState(() => _error = 'Location permission denied (Geolocator).');
        return;
      }
      if (permission == LocationPermission.deniedForever) {
        setState(() => _error = 'Location permission denied forever.');
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
        setState(
          () => _error = 'Unable to obtain a fresh GPS fix (timeout).',
        );
        return;
      }

      setState(() => _position = best);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pos = _position;
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
              onPressed: _loading ? null : _getLocation,
              child: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Get Location'),
            ),
            const SizedBox(height: 12),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 12),
            _InfoRow(label: 'Latitude', value: pos?.latitude.toString()),
            _InfoRow(label: 'Longitude', value: pos?.longitude.toString()),
            _InfoRow(
              label: 'Accuracy (m)',
              value: pos?.accuracy.toStringAsFixed(1),
            ),
            _InfoRow(
              label: 'GPS age (s)',
              value: age?.toStringAsFixed(2),
            ),
            _InfoRow(label: 'Timestamp', value: pos?.timestamp.toIso8601String()),
            _InfoRow(
              label: 'Altitude',
              value: pos?.altitude.toStringAsFixed(1),
            ),
            _InfoRow(
              label: 'Speed',
              value: pos?.speed.toStringAsFixed(2),
            ),
            _InfoRow(
              label: 'Heading',
              value: pos?.heading.toStringAsFixed(1),
            ),
          ],
        ),
      ),
    );
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
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelLarge,
            ),
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
