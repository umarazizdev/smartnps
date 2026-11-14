import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:smartnps360/src/screens/controllers/sitefiltercontroller.dart';

class SiteFilterDropdown extends StatelessWidget {
  final List<Map<String, dynamic>> allItems; // data to filter (e.g., guards)
  final Function(List<Map<String, dynamic>>) onFilterApplied;

  const SiteFilterDropdown({
    super.key,
    required this.allItems,
    required this.onFilterApplied,
  });

  @override
  Widget build(BuildContext context) {
    final SiteFilterController controller = Get.put(SiteFilterController());
    final textTheme = Theme.of(context).textTheme;

    return Obx(() {
      final sites = controller.allSites;
      if (sites.isEmpty) {
        return const Text('No sites available');
      }

      return SizedBox(
        height: 45,
        child: DropdownButtonHideUnderline(
          child: DropdownButton2<String>(
            isExpanded: true,
            hint: Text(
              'Filter by Site',
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: const Color(0xff030B17),
              ),
            ),
            iconStyleData: const IconStyleData(
              icon: Icon(Icons.keyboard_arrow_down_outlined),
            ),
            dropdownStyleData: DropdownStyleData(
              maxHeight: MediaQuery.of(context).size.height * 0.25,
              width: MediaQuery.of(context).size.width * 0.9,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.white,
              ),
              // Removed invalid DropdownDirection.down; use default dropdown direction
              offset: const Offset(0, 4),
            ),
            buttonStyleData: ButtonStyleData(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
                color: Colors.white,
              ),
              height: 45,
            ),
            value:
                controller.selectedSiteId.value ?? sites.first['id'].toString(),
            items: sites.map((site) {
              final id = site['id'].toString();
              final name = site['name'] ?? 'Unnamed Site';
              return DropdownMenuItem<String>(
                value: id,
                child: Text(
                  name,
                  maxLines: 1,
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w400,
                    height: 0.9,
                  ),
                ),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                controller.filterBySite(value, allItems);
                onFilterApplied(controller.filteredItems);
              }
            },
            menuItemStyleData: const MenuItemStyleData(
              overlayColor: WidgetStatePropertyAll(Color(0xffF8F4F1)),
              height: 40,
            ),
          ),
        ),
      );
    });
  }
}
