import 'package:get/get.dart';
import 'package:intl/intl.dart';
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
  final selectedMonth = DateTime.now().month.obs;
  final selectedYear = DateTime.now().year.obs;
  final selectedDay = DateTime.now().day.obs;
  final shifts = <NewCalendarShift>[].obs;

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

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

  final Map<int, List<int>> warningDaysByMonth = {};

  @override
  void onInit() {
    super.onInit();
    final today = _today;
    shifts.assignAll(_sampleShifts(today));
    warningDaysByMonth
      ..clear()
      ..addAll(_sampleWarnings(today));
  }

  List<NewCalendarShift> _sampleShifts(DateTime today) {
    const sites = ['BayCrest', 'Prism', 'North Gate', 'Riverside'];
    const roles = ['On-Site', 'Patrol'];
    const ranges = [
      '9 PM – 5 AM',
      '7 PM – 3 AM',
      '8 PM – 4 AM',
      '10 PM – 6 AM',
    ];

    NewCalendarShift entry({
      required String id,
      required DateTime date,
      required String site,
      required String timeRange,
      required String role,
      required String status,
      String shiftName = 'Scheduled Shift',
      int breakMinutes = 30,
      bool? breakPaid,
      bool firewatch = false,
      bool paidLunch = false,
    }) {
      final isBreakPaid = breakPaid ?? paidLunch;
      return NewCalendarShift(
        id: id,
        dateText: '${monthShortNames[date.month - 1]} ${date.day}',
        fullDateText: DateFormat('EEE, MM/dd/yyyy').format(date),
        shiftName: shiftName,
        site: site,
        timeRange: timeRange,
        role: role,
        status: status,
        breakMinutes: breakMinutes,
        breakPaid: isBreakPaid,
        firewatch: firewatch,
        paidLunch: isBreakPaid,
      );
    }

    DateTime clamped(int month, int day) {
      final last = DateTime(today.year, month + 1, 0).day;
      final safeDay = day < 1 ? 1 : (day > last ? last : day);
      return DateTime(today.year, month, safeDay);
    }

    final items = <NewCalendarShift>[
      entry(
        id: 'today',
        date: today,
        shiftName: 'Morning Shift',
        site: 'Bilal Dairy Farm',
        timeRange: '09:00 AM – 09:00 PM',
        role: 'On-Site',
        status: 'Upcoming',
        breakMinutes: 30,
        breakPaid: true,
      ),
      entry(
        id: 'tomorrow',
        date: today.add(const Duration(days: 1)),
        site: 'Prism',
        timeRange: '7 PM – 3 AM',
        shiftName: 'Evening Patrol',
        role: 'Patrol',
        status: 'Scheduled',
        breakMinutes: 45,
        breakPaid: false,
        firewatch: true,
      ),
      entry(
        id: 'week-a',
        date: today.add(const Duration(days: 3)),
        site: 'North Gate',
        timeRange: '8 PM – 4 AM',
        shiftName: 'Night Coverage',
        role: 'On-Site',
        status: 'Extra Coverage',
        breakMinutes: 30,
        breakPaid: false,
      ),
      entry(
        id: 'week-b',
        date: today.add(const Duration(days: 5)),
        site: 'Riverside',
        timeRange: '8 PM – 4 AM',
        shiftName: 'Night Shift',
        role: 'Patrol',
        status: 'Permanent Shift',
        breakMinutes: 60,
        breakPaid: true,
      ),
    ];

    final earlier = [
      clamped(today.month, today.day - 8),
      clamped(today.month, today.day - 4),
    ];
    var pastIndex = 0;
    for (final date in earlier) {
      if (!date.isBefore(today)) continue;
      if (items.any(
        (shift) =>
            _shiftMonth(shift.dateText) == date.month &&
            _shiftDay(shift.dateText) == date.day,
      )) {
        continue;
      }
      items.add(
        entry(
          id: 'past-$pastIndex',
          date: date,
          site: pastIndex == 0 ? 'North Gate' : 'BayCrest',
          timeRange: pastIndex == 0 ? '8 PM – 4 AM' : '9 PM – 5 AM',
          role: 'On-Site',
          status: 'Completed',
          firewatch: pastIndex == 0,
        ),
      );
      pastIndex++;
    }

    var index = 0;
    for (var month = 1; month <= 12; month++) {
      if (month == today.month) continue;
      final date = clamped(month, 6 + (month * 2) % 18);
      final completed = date.isBefore(today);
      items.add(
        entry(
          id: 'month-$month',
          date: date,
          site: sites[index % sites.length],
          timeRange: ranges[index % ranges.length],
          role: roles[index % roles.length],
          status: completed ? 'Completed' : 'Scheduled',
          firewatch: month % 4 == 0,
          paidLunch: month % 3 == 0,
        ),
      );
      index++;
    }

    return items;
  }

  Map<int, List<int>> _sampleWarnings(DateTime today) {
    final current = (today.day - 4).clamp(1, 28);
    final april = today.month == 4 ? 6 : 4;
    final september = today.month == 9 ? 8 : 9;
    return {
      today.month: [current],
      april: const [12, 21],
      september: const [17],
    };
  }

  String get monthTitle =>
      '${monthNames[selectedMonth.value - 1]} ${selectedYear.value}';

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
    final today = _today;
    final tomorrow = today.add(const Duration(days: 1));
    switch (selectedView.value) {
      case NewCalendarView.today:
        return shifts
            .where(
              (e) =>
                  _shiftMonth(e.dateText) == today.month &&
                  _shiftDay(e.dateText) == today.day,
            )
            .toList();
      case NewCalendarView.tomorrow:
        return shifts
            .where(
              (e) =>
                  _shiftMonth(e.dateText) == tomorrow.month &&
                  _shiftDay(e.dateText) == tomorrow.day,
            )
            .toList();
      case NewCalendarView.week:
        final end = today.add(const Duration(days: 6));
        return shifts.where((e) {
          final month = _shiftMonth(e.dateText);
          final day = _shiftDay(e.dateText);
          if (month <= 0 || day <= 0) return false;
          final date = DateTime(today.year, month, day);
          return !date.isBefore(today) && !date.isAfter(end);
        }).toList();
      case NewCalendarView.month:
        return shiftsForDay(selectedMonth.value, selectedDay.value);
      case NewCalendarView.year:
        return shifts;
    }
  }

  List<NewCalendarShift> shiftsForDay(int month, int day) {
    return shifts
        .where(
          (shift) =>
              _shiftMonth(shift.dateText) == month &&
              _shiftDay(shift.dateText) == day,
        )
        .toList();
  }

  List<NewCalendarShift> shiftsForMonth(int month) {
    return shifts
        .where((shift) => _shiftMonth(shift.dateText) == month)
        .toList();
  }

  bool hasShiftOnDay(int month, int day) => shiftsForDay(month, day).isNotEmpty;
  bool hasFirewatchOnDay(int month, int day) =>
      shiftsForDay(month, day).any((e) => e.firewatch);
  bool hasPaidLunchOnDay(int month, int day) =>
      shiftsForDay(month, day).any((e) => e.paidLunch);
  bool hasWarningOnDay(int month, int day) =>
      warningDaysByMonth[month]?.contains(day) ?? false;

  List<NewCalendarDay> get monthDays => buildMonthDays(
    selectedYear.value,
    selectedMonth.value,
    includeAdjacentDays: true,
    selectedDay: selectedDay.value,
  );

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
        days: buildMonthDays(
          selectedYear.value,
          month,
          includeAdjacentDays: true,
        ),
      );
    });
  }

  List<NewCalendarDay> buildMonthDays(
    int year,
    int month, {
    required bool includeAdjacentDays,
    int? selectedDay,
  }) {
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final firstWeekday = DateTime(year, month, 1).weekday % 7;
    final prevMonthDays = DateTime(year, month, 0).day;
    final result = <NewCalendarDay>[];

    if (includeAdjacentDays) {
      for (int i = firstWeekday - 1; i >= 0; i--) {
        final prevMonth = month == 1 ? 12 : month - 1;
        final prevYear = month == 1 ? year - 1 : year;
        result.add(
          NewCalendarDay(
            day: prevMonthDays - i,
            month: prevMonth,
            year: prevYear,
            inMonth: false,
          ),
        );
      }
    } else {
      for (int i = 0; i < firstWeekday; i++) {
        result.add(
          NewCalendarDay(day: 0, month: month, year: year, inMonth: false),
        );
      }
    }

    for (int day = 1; day <= daysInMonth; day++) {
      result.add(
        NewCalendarDay(
          day: day,
          month: month,
          year: year,
          inMonth: true,
          isToday:
              year == _today.year && month == _today.month && day == _today.day,
          isSelected: selectedDay != null && day == selectedDay,
          hasShift: hasShiftOnDay(month, day),
          hasFirewatch: hasFirewatchOnDay(month, day),
          hasPaidLunch: hasPaidLunchOnDay(month, day),
          hasWarning: hasWarningOnDay(month, day),
        ),
      );
    }

    int nextDay = 1;
    while (result.length % 7 != 0) {
      final nextMonth = month == 12 ? 1 : month + 1;
      final nextYear = month == 12 ? year + 1 : year;
      result.add(
        NewCalendarDay(
          day: includeAdjacentDays ? nextDay : 0,
          month: nextMonth,
          year: nextYear,
          inMonth: false,
        ),
      );
      nextDay++;
    }

    return result;
  }

  int _shiftMonth(String dateText) {
    if (dateText == 'Today') return _today.month;
    if (dateText == 'Tomorrow') {
      return _today.add(const Duration(days: 1)).month;
    }
    for (int i = 0; i < monthShortNames.length; i++) {
      if (dateText.toLowerCase().startsWith(monthShortNames[i].toLowerCase())) {
        return i + 1;
      }
      if (dateText.toLowerCase().startsWith(monthNames[i].toLowerCase())) {
        return i + 1;
      }
    }
    return selectedMonth.value;
  }

  int _shiftDay(String dateText) {
    if (dateText == 'Today') return _today.day;
    if (dateText == 'Tomorrow') return _today.add(const Duration(days: 1)).day;
    final match = RegExp(r'(\d+)').firstMatch(dateText);
    return int.tryParse(match?.group(1) ?? '') ?? -1;
  }
}
