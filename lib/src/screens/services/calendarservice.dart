import 'package:smartnps360/src/screens/main_screens/DashboardScreen/CalendarScreen/calendarmodel.dart';
import 'package:smartnps360/src/screens/services/apiservice.dart';
import 'package:smartnps360/src/screens/data/api.url.dart';

class CalendarService {
  final ApiService _apiService = ApiService();

  /// Fetches calendar data for a specific month
  /// [month] should be in format: "YYYY-MM" (e.g., "2025-12")
  Future<CalendarMonthResponse> getMonthlyCalendar(String month) async {
    try {
      final endpoint = '${ApiURL.schedulesMonthly}?month=$month';
      final response = await _apiService.getData(endpoint);

      return CalendarMonthResponse.fromJson(response as Map<String, dynamic>);
    } catch (e) {
      throw Exception('Failed to fetch calendar data: $e');
    }
  }
}
