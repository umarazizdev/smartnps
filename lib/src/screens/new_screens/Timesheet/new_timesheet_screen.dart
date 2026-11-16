import 'package:flutter/material.dart';
import 'package:smartnps360/src/screens/main_screens/TimeSheetScreen/timesheetscreen.dart';

class NewTimesheetScreen extends StatelessWidget {
  const NewTimesheetScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom + 108;
    return TimesheetScreen(sampleData: true, scrollBottomPadding: bottom);
  }
}
