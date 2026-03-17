import UIKit

public struct BFOverlayNavigationRightItem {
    public enum Content {
        case image(UIImage)
        case text(String)
    }

    public var identifier: String
    public var content: Content
    public var hitSize: CGSize
    public var contentInsets: UIEdgeInsets
    public var preservesImageOriginalSize: Bool
    public var textColor: UIColor
    public var font: UIFont

    public init(
        identifier: String,
        content: Content,
        hitSize: CGSize = CGSize(width: 44, height: 44),
        contentInsets: UIEdgeInsets = .zero,
        preservesImageOriginalSize: Bool = true,
        textColor: UIColor = .black,
        font: UIFont = .systemFont(ofSize: 16, weight: .medium)
    ) {
        self.identifier = identifier
        self.content = content
        self.hitSize = hitSize
        self.contentInsets = contentInsets
        self.preservesImageOriginalSize = preservesImageOriginalSize
        self.textColor = textColor
        self.font = font
    }
}

public struct BFOverlayNavigationConfig {
    public var title: String?
    public var usesSystemTitle: Bool
    public var showsBackButton: Bool?
    public var backButtonImage: UIImage?
    public var preservesBackImageOriginalSize: Bool
    public var clearsSystemBarButtonItems: Bool
    public var rightItems: [BFOverlayNavigationRightItem]

    public init(
        title: String? = nil,
        usesSystemTitle: Bool = true,
        showsBackButton: Bool? = nil,
        backButtonImage: UIImage? = nil,
        preservesBackImageOriginalSize: Bool = true,
        clearsSystemBarButtonItems: Bool = true,
        rightItems: [BFOverlayNavigationRightItem] = []
    ) {
        self.title = title
        self.usesSystemTitle = usesSystemTitle
        self.showsBackButton = showsBackButton
        self.backButtonImage = backButtonImage
        self.preservesBackImageOriginalSize = preservesBackImageOriginalSize
        self.clearsSystemBarButtonItems = clearsSystemBarButtonItems
        self.rightItems = rightItems
    }
}

public protocol BFOverlayNavigationConfigurable: AnyObject {
    var overlayNavigationConfig: BFOverlayNavigationConfig { get }
    func overlayNavigationController(_ navigationController: BFOverlayNavigationController, didTapRightItemWith identifier: String)
    func overlayNavigationControllerDidTapBack(_ navigationController: BFOverlayNavigationController) -> Bool
}

public extension BFOverlayNavigationConfigurable where Self: UIViewController {
    func overlayNavigationController(_ navigationController: BFOverlayNavigationController, didTapRightItemWith identifier: String) {
        _ = identifier
    }

    func overlayNavigationControllerDidTapBack(_ navigationController: BFOverlayNavigationController) -> Bool {
        _ = navigationController.popViewController(animated: true)
        return true
    }
}

public protocol BFOverlayBackButtonProviding: AnyObject {
    var overlayBackButtonImage: UIImage? { get }
}

public protocol BFOverlayNavigationBarAlphaProviding: AnyObject {
    var overlayNavigationBarAlpha: CGFloat { get }
}

public protocol BFOverlayNavigationBarVisibilityProviding: AnyObject {
    var overlayPrefersNavigationBarHidden: Bool { get }
}
