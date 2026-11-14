import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:get/get.dart';
import 'package:smartnps360/src/screens/controllers/connectivitycontroller.dart';
import 'package:smartnps360/src/screens/utilities/const.dart';
import 'package:smartnps360/src/screens/widgets/gradientbutton.dart';

class NoInternetScreen extends StatelessWidget {
  final VoidCallback? onRetry;
  final VoidCallback? onConnected;

  const NoInternetScreen({super.key, this.onRetry, this.onConnected});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final textTheme = Theme.of(context).textTheme;
    final connectivityController = Get.find<ConnectivityController>();

    // Listen for connectivity changes and auto-navigate when connected
    ever(connectivityController.isConnected, (isConnected) {
      if (isConnected && onConnected != null) {
        EasyLoading.dismiss();
        onConnected!();
      }
    });

    return Scaffold(
      backgroundColor: cMainBg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // No Internet Icon/Image
                Container(
                  width: size.width * 0.5,
                  height: size.width * 0.5,
                  decoration: BoxDecoration(
                    color: cPale,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(13),
                        blurRadius: 20,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Icon(
                      Icons.wifi_off_rounded,
                      size: size.width * 0.25,
                      color: cOrange,
                    ),
                  ),
                ),

                const SizedBox(height: 40),

                // Title
                Text(
                  'No Internet Connection',
                  textAlign: TextAlign.center,
                  style: textTheme.headlineSmall?.copyWith(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: cDarkText,
                  ),
                ),

                const SizedBox(height: 16),

                // Description
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Text(
                    'Please check your internet connection. We\'ll automatically reconnect you once your connection is restored.',
                    textAlign: TextAlign.center,
                    style: textTheme.bodyLarge?.copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                      color: cDarkGreyclr,
                      height: 1.5,
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Auto-detection info
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 24.0),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 12.0,
                  ),
                  decoration: BoxDecoration(
                    color: cOrange.withAlpha(26),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cOrange.withAlpha(77), width: 1),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        color: cOrange,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Can\'t wait? Use "Try Again" to check manually',
                          style: textTheme.bodyMedium?.copyWith(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: cDarkText,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 48),

                // Try Again Button
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32.0),
                  child: GradientButton(
                    text: 'Try Again',
                    onPressed: () async {
                      EasyLoading.show();
                      if (onRetry != null) {
                        await Future.delayed(const Duration(milliseconds: 500));
                        onRetry!();
                      } else {
                        await connectivityController.checkConnection();
                      }

                      // Dismiss loading if still not connected
                      await Future.delayed(const Duration(milliseconds: 500));
                      if (!connectivityController.isConnected.value) {
                        EasyLoading.dismiss();
                        EasyLoading.showError('Still no internet connection');
                      }
                    },
                    height: 56,
                    width: double.infinity,
                    borderRadius: const BorderRadius.all(Radius.circular(16)),
                    gradientColors: const [
                      Color(0xFF022A67),
                      Color(0xFF005BFF),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Troubleshooting tips
                Column(
                  children: [
                    Text(
                      'Troubleshooting Tips',
                      style: textTheme.bodyMedium?.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: cDarkText,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '• Check if WiFi/Mobile Data is turned on\n• Verify airplane mode is off\n• Try toggling WiFi on/off',
                      textAlign: TextAlign.center,
                      style: textTheme.bodySmall?.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: cDarkGreyclr.withAlpha(204),
                        height: 1.6,
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
  }
}
