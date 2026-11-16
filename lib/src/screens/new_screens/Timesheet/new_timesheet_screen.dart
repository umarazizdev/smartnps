import 'package:flutter/material.dart';
import 'package:smartnps360/src/screens/main_screens/TimeSheetScreen/timesheetscreen.dart';

class NewTimesheetScreen extends StatelessWidget {
  const NewTimesheetScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(bottom: 96),
      child: TimesheetScreen(),
    );
  }
}
