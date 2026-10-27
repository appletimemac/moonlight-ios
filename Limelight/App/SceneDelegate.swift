import SwiftUI
import UIKit

// Named SceneDelegate for the Objective-C runtime because Info.plist refers to it by that name
@objc(SceneDelegate)
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var library: HostLibrary?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        let library = HostLibrary(presenter: StreamPresenter(window: window))
        window.rootViewController = UIHostingController(rootView: RootView().environment(library))
        self.window = window
        self.library = library

        if let shortcut = connectionOptions.shortcutItem {
            library.handleShortcut(shortcut)
        }
        window.makeKeyAndVisible()
    }

    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem) async -> Bool {
        library?.handleShortcut(shortcutItem) ?? false
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        library?.enterForeground()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        library?.enterBackground()
        (UIApplication.shared.delegate as? AppDelegate)?.saveContext()
    }
}
