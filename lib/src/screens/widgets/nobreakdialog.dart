import 'package:flutter/material.dart';
import 'package:smartnps360/src/screens/utilities/const.dart';

class NoBreakShiftDialog extends StatefulWidget {
  const NoBreakShiftDialog({super.key});

  @override
  State<NoBreakShiftDialog> createState() => _NoBreakShiftDialogState();
}

class _NoBreakShiftDialogState extends State<NoBreakShiftDialog> {
  bool _isAgreed = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AlertDialog(
      backgroundColor: isDark ? cDarkCardColor : cMainBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        'No-Break Shift',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      content: const Text(
        'This shift does not include a break. '
        'You must agree to proceed without a break to clock in.',
        style: TextStyle(fontSize: 15),
      ),
      actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      actions: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Checkbox(
              value: _isAgreed,
              onChanged: (val) {
                setState(() {
                  _isAgreed = val ?? false;
                });
              },
            ),
            const Expanded(
              child: Text(
                'I agree to work this shift without a break.',
                style: TextStyle(fontSize: 14),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                foregroundColor: isDark ? cDarkTextPrimary : Colors.grey[700],
              ),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _isAgreed
                  ? () {
                      Navigator.pop(context, true);
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _isAgreed
                    ? cPrimary
                    : (isDark ? cDarkBorderColor : Colors.grey[300]),
                foregroundColor: _isAgreed
                    ? Colors.white
                    : (isDark ? cDarkTextSecondary : Colors.grey[600]),
                disabledBackgroundColor: isDark
                    ? cDarkBorderColor
                    : Colors.grey[300],
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('I Agree & Continue'),
            ),
          ],
        ),
      ],
    );
  }
}
