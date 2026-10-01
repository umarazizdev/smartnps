import Flutter
import UIKit

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
