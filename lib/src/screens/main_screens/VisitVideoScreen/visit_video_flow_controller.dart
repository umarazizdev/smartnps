import 'package:get/get.dart';

class VisitVideoFlowController extends GetxController {
  final RxList<String> recordedVideoPaths = <String>[].obs;

  void addVideo(String path) {
    if (path.trim().isEmpty) return;
    recordedVideoPaths.add(path);
  }

  void removeVideoAt(int index) {
    if (index < 0 || index >= recordedVideoPaths.length) return;
    recordedVideoPaths.removeAt(index);
  }

  void clearAll() {
    recordedVideoPaths.clear();
  }
}
