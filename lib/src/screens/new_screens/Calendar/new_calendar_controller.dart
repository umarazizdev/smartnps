import 'package:get/get.dart';
import '../new_models.dart';

class NewCalendarDay {
  const NewCalendarDay({
    required this.day,
    required this.month,
    required this.year,
    required this.inMonth,
    this.isToday = false,
    this.isSelected = false,
    this.hasShift = false,
    this.hasFirewatch = false,
    this.hasPaidLunch = false,
    this.hasWarning = false,
  });

  final int day;
  final int month;
  final int year;
  final bool inMonth;
  final bool isToday;
  final bool isSelected;
  final bool hasShift;
  final bool hasFirewatch;
  final bool hasPaidLunch;
  final bool hasWarning;
}

class NewCalendarMonth {
  const NewCalendarMonth({
    required this.name,
    required this.fullName,
    required this.month,
    required this.shiftCount,
    required this.warningCount,
    required this.days,
  });

  final String name;
  final String fullName;
  final int month;
  final int shiftCount;
  final int warningCount;
  final List<NewCalendarDay> days;
}

class NewCalendarController extends GetxController {
  final selectedView = NewCalendarView.today.obs;
  final selectedMonth = 5.obs;
  final selectedYear = 2026.obs;
  final selectedDay = 19.obs;
  final shifts = <NewCalendarShift>[].obs;

  static const monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  static const monthShortNames = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  final Map<int, List<int>> warningDaysByMonth = const {
    4: [21],
    5: [2, 3],
    9: [17],
  };

  @override
  void onInit() {
    super.onInit();
    shifts.assignAll(const [
      NewCalendarShift(id: 's1', dateText: 'May 19', site: 'BayCrest', timeRange: '9 PM – 5 AM', role: 'On-Site', status: 'Upcoming'),
      NewCalendarShift(id: 's2', dateText: 'May 20', site: 'Prism', timeRange: '7 PM – 3 AM', role: 'Patrol', status: 'Scheduled', firewatch: true),
      NewCalendarShift(id: 's3', dateText: 'May 8', site: 'North Gate', timeRange: '8 PM – 4 AM', role: 'On-Site', status: 'Extra Coverage', paidLunch: true),
      NewCalendarShift(id: 's4', dateText: 'May 11', site: 'BayCrest', timeRange: '9 PM – 5 AM', role: 'On-Site', status: 'Permanent Shift'),
      NewCalendarShift(id: 's5', dateText: 'May 22', site: 'Riverside', timeRange: '8 PM – 4 AM', role: 'Patrol', status: 'Scheduled'),
      NewCalendarShift(id: 's6', dateText: 'May 29', site: 'BayCrest', timeRange: '9 PM – 5 AM', role: 'On-Site', status: 'Scheduled', paidLunch: true),
      NewCalendarShift(id: 's7', dateText: 'Jan 14', site: 'Prism', timeRange: '7 PM – 3 AM', role: 'Patrol', status: 'Completed'),
      NewCalendarShift(id: 's8', dateText: 'Feb 18', site: 'BayCrest', timeRange: '9 PM – 5 AM', role: 'On-Site', status: 'Completed'),
      NewCalendarShift(id: 's9', dateText: 'Mar 7', site: 'North Gate', timeRange: '8 PM – 4 AM', role: 'On-Site', status: 'Completed', firewatch: true),
      NewCalendarShift(id: 's10', dateText: 'Apr 21', site: 'Riverside', timeRange: '8 PM – 4 AM', role: 'Patrol', status: 'Completed'),
      NewCalendarShift(id: 's11', dateText: 'Jun 6', site: 'BayCrest', timeRange: '9 PM – 5 AM', role: 'On-Site', status: 'Scheduled'),
      NewCalendarShift(id: 's12', dateText: 'Jun 19', site: 'Prism', timeRange: '7 PM – 3 AM', role: 'Patrol', status: 'Scheduled', paidLunch: true),
      NewCalendarShift(id: 's13', dateText: 'Jul 12', site: 'North Gate', timeRange: '8 PM – 4 AM', role: 'On-Site', status: 'Scheduled'),
      NewCalendarShift(id: 's14', dateText: 'Aug 3', site: 'Riverside', timeRange: '8 PM – 4 AM', role: 'Patrol', status: 'Scheduled'),
      NewCalendarShift(id: 's15', dateText: 'Sep 17', site: 'BayCrest', timeRange: '9 PM – 5 AM', role: 'On-Site', status: 'Scheduled', firewatch: true),
      NewCalendarShift(id: 's16', dateText: 'Oct 9', site: 'Prism', timeRange: '7 PM – 3 AM', role: 'Patrol', status: 'Scheduled'),
      NewCalendarShift(id: 's17', dateText: 'Nov 23', site: 'North Gate', timeRange: '8 PM – 4 AM', role: 'On-Site', status: 'Scheduled'),
      NewCalendarShift(id: 's18', dateText: 'Dec 4', site: 'BayCrest', timeRange: '9 PM – 5 AM', role: 'On-Site', status: 'Scheduled', paidLunch: true),
    ]);
  }

  String get monthTitle => '${monthNames[selectedMonth.value - 1]} ${selectedYear.value}';

  void changeView(NewCalendarView view) {
    selectedView.value = view;
  }

  void previousMonth() {
    if (selectedMonth.value == 1) {
      selectedMonth.value = 12;
      selectedYear.value--;
      return;
    }
    selectedMonth.value--;
  }

  void nextMonth() {
    if (selectedMonth.value == 12) {
      selectedMonth.value = 1;
      selectedYear.value++;
      return;
    }
    selectedMonth.value++;
  }

  void selectDay(int day) {
    selectedDay.value = day;
  }

  void selectMonth(int month) {
    selectedMonth.value = month;
    selectedDay.value = 1;
    selectedView.value = NewCalendarView.month;
  }

  List<NewCalendarShift> get filteredShifts {
    switch (selectedView.value) {
      case NewCalendarView.today:
        return shifts.where((e) => _shiftMonth(e.dateText) == 5 && _shiftDay(e.dateText) == 19).toList();
      case NewCalendarView.tomorrow:
        return shifts.where((e) => _shiftMonth(e.dateText) == 5 && _shiftDay(e.dateText) == 20).toList();
      case NewCalendarView.week:
        return shifts.where((e) => _shiftMonth(e.dateText) == 5 && [19, 20, 22].contains(_shiftDay(e.dateText))).toList();
      case NewCalendarView.month:
        return shiftsForDay(selectedMonth.value, selectedDay.value);
      case NewCalendarView.year:
        return shifts;
    }
  }

  List<NewCalendarShift> shiftsForDay(int month, int day) {
    return shifts.where((shift) => _shiftMonth(shift.dateText) == month && _shiftDay(shift.dateText) == day).toList();
  }

  List<NewCalendarShift> shiftsForMonth(int month) {
    return shifts.where((shift) => _shiftMonth(shift.dateText) == month).toList();
  }

  bool hasShiftOnDay(int month, int day) => shiftsForDay(month, day).isNotEmpty;
  bool hasFirewatchOnDay(int month, int day) => shiftsForDay(month, day).any((e) => e.firewatch);
  bool hasPaidLunchOnDay(int month, int day) => shiftsForDay(month, day).any((e) => e.paidLunch);
  bool hasWarningOnDay(int month, int day) => warningDaysByMonth[month]?.contains(day) ?? false;

  List<NewCalendarDay> get monthDays => buildMonthDays(selectedYear.value, selectedMonth.value, includeAdjacentDays: true, selectedDay: selectedDay.value);

  List<NewCalendarMonth> get yearMonths {
    return List.generate(12, (index) {
      final month = index + 1;
      final monthShifts = shiftsForMonth(month);
      final warningDays = warningDaysByMonth[month] ?? const <int>[];
      return NewCalendarMonth(
        name: monthShortNames[index],
        fullName: monthNames[index],
        month: month,
        shiftCount: monthShifts.length,
        warningCount: warningDays.length,
        days: buildMonthDays(selectedYear.value, month, includeAdjacentDays: true),
      );
    });
  }

  List<NewCalendarDay> buildMonthDays(int year, int month, {required bool includeAdjacentDays, int? selectedDay}) {
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final firstWeekday = DateTime(year, month, 1).weekday % 7;
    final prevMonthDays = DateTime(year, month, 0).day;
    final result = <NewCalendarDay>[];

    if (includeAdjacentDays) {
      for (int i = firstWeekday - 1; i >= 0; i--) {
        final prevMonth = month == 1 ? 12 : month - 1;
        final prevYear = month == 1 ? year - 1 : year;
        result.add(NewCalendarDay(day: prevMonthDays - i, month: prevMonth, year: prevYear, inMonth: false));
      }
    } else {
      for (int i = 0; i < firstWeekday; i++) {
        result.add(NewCalendarDay(day: 0, month: month, year: year, inMonth: false));
      }
    }

    for (int day = 1; day <= daysInMonth; day++) {
      result.add(NewCalendarDay(
        day: day,
        month: month,
        year: year,
        inMonth: true,
        isToday: month == 5 && year == 2026 && day == 19,
        isSelected: selectedDay != null && day == selectedDay,
        hasShift: hasShiftOnDay(month, day),
        hasFirewatch: hasFirewatchOnDay(month, day),
        hasPaidLunch: hasPaidLunchOnDay(month, day),
        hasWarning: hasWarningOnDay(month, day),
      ));
    }

    int nextDay = 1;
    while (result.length % 7 != 0 || result.length < 42) {
      final nextMonth = month == 12 ? 1 : month + 1;
      final nextYear = month == 12 ? year + 1 : year;
      result.add(NewCalendarDay(day: includeAdjacentDays ? nextDay : 0, month: nextMonth, year: nextYear, inMonth: false));
      nextDay++;
    }

    return result;
  }

  int _shiftMonth(String dateText) {
    if (dateText == 'Today' || dateText == 'Tomorrow') return 5;
    for (int i = 0; i < monthShortNames.length; i++) {
      if (dateText.toLowerCase().startsWith(monthShortNames[i].toLowerCase())) return i + 1;
      if (dateText.toLowerCase().startsWith(monthNames[i].toLowerCase())) return i + 1;
    }
    return selectedMonth.value;
  }

  int _shiftDay(String dateText) {
    if (dateText == 'Today') return 19;
    if (dateText == 'Tomorrow') return 20;
    final match = RegExp(r'(\d+)').firstMatch(dateText);
    return int.tryParse(match?.group(1) ?? '') ?? -1;
  }
}
