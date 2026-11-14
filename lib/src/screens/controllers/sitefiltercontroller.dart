import 'package:get/get.dart';

class SiteFilterController extends GetxController {
  // All sites — you will populate this from wherever you fetch data.
  var allSites = <Map<String, dynamic>>[].obs;

  // Selected site ID
  var selectedSiteId = RxnString();

  // Filtered data
  var filteredItems = <Map<String, dynamic>>[].obs;

  // Call this to set the initial sites list
  void setSites(List<Map<String, dynamic>> sites) {
    allSites.value = sites;
    if (sites.isNotEmpty && selectedSiteId.value == null) {
      selectedSiteId.value = sites.first['id'].toString();
    }
  }

  // Filter function — call this when dropdown value changes
  void filterBySite(String siteId, List<Map<String, dynamic>> allItems) {
    selectedSiteId.value = siteId;
    filteredItems.value = allItems
        .where((item) => item['siteId'].toString() == siteId)
        .toList();
  }
}
