import CarPlay
import UIKit

final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
  private let rootTemplateProvider = DopiCarPlayRootTemplateProvider()

  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didConnect interfaceController: CPInterfaceController,
    to window: CPWindow
  ) {
    interfaceController.setRootTemplate(rootTemplateProvider.makeTemplate(), animated: false)
  }
}
