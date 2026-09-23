import Flutter
import UIKit

/// UIScene lifecycle owner. AppDelegate applicationDidBecomeActive /
/// applicationDidEnterBackground are not called once UIScene is adopted, so
/// kill-cycle opened_at / background_at must be handled here.
class SceneDelegate: FlutterSceneDelegate {
  override func sceneWillEnterForeground(_ scene: UIScene) {
    (UIApplication.shared.delegate as? AppDelegate)?.onUserSceneWillEnterForeground()
    super.sceneWillEnterForeground(scene)
  }

  override func sceneDidBecomeActive(_ scene: UIScene) {
    (UIApplication.shared.delegate as? AppDelegate)?.onUserSceneBecameActive()
    super.sceneDidBecomeActive(scene)
  }

  override func sceneDidEnterBackground(_ scene: UIScene) {
    (UIApplication.shared.delegate as? AppDelegate)?.onUserSceneEnteredBackground()
    super.sceneDidEnterBackground(scene)
  }
}
