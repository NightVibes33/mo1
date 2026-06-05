import CarPlay
import Foundation
import UIKit

final class MO1CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
  private var interfaceController: CPInterfaceController?

  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didConnect interfaceController: CPInterfaceController
  ) {
    self.interfaceController = interfaceController
    interfaceController.setRootTemplate(makeRootTemplate(), animated: false)
  }

  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didDisconnect interfaceController: CPInterfaceController
  ) {
    if self.interfaceController === interfaceController {
      self.interfaceController = nil
    }
  }

  private func makeRootTemplate() -> CPListTemplate {
    let nowPlayingItem = CPListItem(
      text: "Now Playing",
      detailText: "Use the steering wheel and CarPlay playback controls."
    )
    nowPlayingItem.handler = { [weak self] _, completion in
      self?.interfaceController?.pushTemplate(
        CPNowPlayingTemplate.shared,
        animated: true
      )
      completion()
    }

    let libraryItem = CPListItem(
      text: "mo1 Library",
      detailText: "Import and organize local MP3s on iPhone."
    )

    let entitlementItem = CPListItem(
      text: "CarPlay Entitlement",
      detailText: "Enable Apple's audio entitlement for App Store CarPlay."
    )

    let section = CPListSection(items: [nowPlayingItem, libraryItem, entitlementItem])
    let template = CPListTemplate(title: "mo1", sections: [section])
    return template
  }
}
