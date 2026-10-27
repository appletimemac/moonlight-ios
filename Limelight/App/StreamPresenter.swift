import UIKit

@MainActor
final class StreamPresenter {
    weak var window: UIWindow?
    private(set) var isStreaming = false

    init(window: UIWindow? = nil) {
        self.window = window
    }

    func present(_ configuration: StreamConfiguration, onExit: @escaping @MainActor () -> Void) {
        guard var top = window?.rootViewController else { return }
        while let presented = top.presentedViewController {
            top = presented
        }
        let stream = StreamPresentation.streamViewController(with: configuration) { [weak self] in
            self?.isStreaming = false
            onExit()
        }
        isStreaming = true
        top.present(stream, animated: true)
    }
}
