import UIKit
import QuartzCore

private final class BFOverlayPassthroughView: UIView {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        for subview in subviews where !subview.isHidden && subview.alpha > 0.01 && subview.isUserInteractionEnabled {
            let pointInSubview = convert(point, to: subview)
            if subview.point(inside: pointInSubview, with: event) {
                return true
            }
        }
        return false
    }
}

open class BFOverlayNavigationController: UINavigationController {
    public var onDidShowViewController: ((UIViewController) -> Void)?
    public var onRootLevelChanged: ((Bool) -> Void)?
    public var navigationDebugLoggingEnabled: Bool = false
    public var navigationPerformanceLoggingEnabled: Bool = false

    private let overlayHostView = BFOverlayPassthroughView()
    private let overlayBackContainer = UIView()
    private let overlayBackButton = UIButton(type: .custom)
    private var overlayBackTopConstraint: NSLayoutConstraint?

    private let overlayRightContainer = UIView()
    private let overlayRightStackView = UIStackView()
    private var overlayRightTopConstraint: NSLayoutConstraint?
    private var overlayContentYOffset: CGFloat = 0
    private var rightItemIdentifiers: [String] = []
    private var lastLayoutLogSignature: String?
    private let overlayImageViewTag = 990_001
    private var pushBeginUptime: TimeInterval?
    private var willShowBeginUptime: TimeInterval?
    private var didShowBeginUptime: TimeInterval?
    private var isPushInFlight = false
    private var isTransitionInputBlocked = false
    private var transitionInputTimeoutWorkItem: DispatchWorkItem?
    private var transitionInputUnlockWorkItem: DispatchWorkItem?
    private let transitionInputTimeout: TimeInterval = 2.0
    private let didShowInputUnlockDelay: TimeInterval = 0.08

    open override func viewDidLoad() {
        super.viewDidLoad()

        delegate = self
        setupDefaultAppearance()
        installOverlayBackButton()
        installOverlayRightContainer()
        UIView.performWithoutAnimation {
            applyNavigationBarAlpha(for: topViewController)
            view.layoutIfNeeded()
        }
    }

    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applyNavigationBarHiddenPreferenceIfNeeded(for: topViewController)
        UIView.performWithoutAnimation {
            applyNavigationBarAlpha(for: topViewController)
            view.layoutIfNeeded()
        }
    }

    open override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        applyNavigationBarHiddenPreferenceIfNeeded(for: topViewController)
        enforceNavigationBarOriginYToStatusBarBottomIfNeeded()
        applyNavigationBarAlpha(for: topViewController)
        performOverlayAlignmentPass(for: topViewController)
        logNavigationLayoutIfNeeded(context: "layout", viewController: topViewController)
    }

    open override func pushViewController(_ viewController: UIViewController, animated: Bool) {
        if isPushInFlight {
            return
        }
        if let coordinator = transitionCoordinator, coordinator.isAnimated {
            return
        }

        isPushInFlight = true
        beginTransitionInputBlock(reason: "push开始 to=\(controllerName(viewController))")

        let pushStart = ProcessInfo.processInfo.systemUptime
        pushBeginUptime = pushStart
        logPerf(
            "动作=性能 来源=导航容器 事件=push入口 主线程=\(Thread.isMainThread) " +
            "系统启动毫秒=\(uptimeMilliseconds()) 动画=\(animated) " +
            "from=\(controllerName(topViewController)) to=\(controllerName(viewController)) 栈深=\(viewControllers.count)"
        )
        if isNavigationBarHidden, !prefersNavigationBarHidden(for: viewController) {
            setNavigationBarHidden(false, animated: false)
            view.layoutIfNeeded()
        }

        if viewControllers.count <= 1, viewIfLoaded?.window != nil {
            onRootLevelChanged?(false)
        }

        if let currentTop = topViewController {
            if #available(iOS 14.0, *) {
                currentTop.navigationItem.backButtonDisplayMode = .minimal
            }
            currentTop.navigationItem.backButtonTitle = ""
        }

        prepareOverlayIfNeeded(for: viewController, shouldShowBack: viewControllers.count >= 1)
        super.pushViewController(viewController, animated: animated)
        logPerf(
            "动作=性能 来源=导航容器 事件=push调用返回 主线程=\(Thread.isMainThread) " +
            "耗时毫秒=\(elapsedMilliseconds(since: pushStart)) 动画=\(animated) to=\(controllerName(viewController))"
        )
    }

    open override func popViewController(animated: Bool) -> UIViewController? {
        if viewControllers.count > 1 {
            beginTransitionInputBlock(reason: "pop开始")
        }
        if viewControllers.count == 2, viewIfLoaded?.window != nil {
            onRootLevelChanged?(true)
        }
        return super.popViewController(animated: animated)
    }

    open override func popToRootViewController(animated: Bool) -> [UIViewController]? {
        if viewControllers.count > 1 {
            beginTransitionInputBlock(reason: "popToRoot开始")
        }
        if viewControllers.count > 1, viewIfLoaded?.window != nil {
            onRootLevelChanged?(true)
        }
        return super.popToRootViewController(animated: animated)
    }

    public func overlayBackButtonDebugMetrics() -> (
        containerInNavBar: CGRect,
        buttonInNavBar: CGRect,
        containerInWindow: CGRect?,
        buttonInWindow: CGRect?
    ) {
        let containerInNavBar = overlayBackContainer.convert(overlayBackContainer.bounds, to: navigationBar)
        let buttonInNavBar = overlayBackButton.convert(overlayBackButton.bounds, to: navigationBar)
        let containerInWindow = overlayBackContainer.window.map { overlayBackContainer.convert(overlayBackContainer.bounds, to: $0) }
        let buttonInWindow = overlayBackButton.window.map { overlayBackButton.convert(overlayBackButton.bounds, to: $0) }
        return (containerInNavBar, buttonInNavBar, containerInWindow, buttonInWindow)
    }

    private func setupDefaultAppearance() {
        navigationBar.tintColor = .black
        navigationBar.isTranslucent = false

        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .white
        appearance.titleTextAttributes = [.foregroundColor: UIColor.black]

        navigationBar.standardAppearance = appearance
        navigationBar.compactAppearance = appearance
        if #available(iOS 15.0, *) {
            navigationBar.scrollEdgeAppearance = appearance
        }
    }

    private func installOverlayBackButton() {
        guard overlayBackContainer.superview == nil else { return }
        installOverlayHostIfNeeded()

        overlayBackContainer.translatesAutoresizingMaskIntoConstraints = false
        overlayBackContainer.backgroundColor = .clear
        overlayBackContainer.isHidden = true
        overlayHostView.addSubview(overlayBackContainer)

        overlayBackButton.translatesAutoresizingMaskIntoConstraints = false
        overlayBackButton.contentHorizontalAlignment = .center
        overlayBackButton.contentVerticalAlignment = .center
        overlayBackButton.clipsToBounds = false
        overlayBackButton.addTarget(self, action: #selector(handleOverlayBackTapped), for: .touchUpInside)
        overlayBackContainer.addSubview(overlayBackButton)

        overlayBackTopConstraint = overlayBackContainer.topAnchor.constraint(equalTo: overlayHostView.topAnchor)

        NSLayoutConstraint.activate([
            overlayBackContainer.leadingAnchor.constraint(equalTo: overlayHostView.leadingAnchor, constant: 10),
            overlayBackTopConstraint!,
            overlayBackContainer.widthAnchor.constraint(equalToConstant: 44),
            overlayBackContainer.heightAnchor.constraint(equalToConstant: 44),

            overlayBackButton.leadingAnchor.constraint(equalTo: overlayBackContainer.leadingAnchor),
            overlayBackButton.trailingAnchor.constraint(equalTo: overlayBackContainer.trailingAnchor),
            overlayBackButton.topAnchor.constraint(equalTo: overlayBackContainer.topAnchor),
            overlayBackButton.bottomAnchor.constraint(equalTo: overlayBackContainer.bottomAnchor)
        ])
    }

    private func installOverlayRightContainer() {
        guard overlayRightContainer.superview == nil else { return }
        installOverlayHostIfNeeded()

        overlayRightContainer.translatesAutoresizingMaskIntoConstraints = false
        overlayRightContainer.backgroundColor = .clear
        overlayRightContainer.isHidden = true
        overlayHostView.addSubview(overlayRightContainer)

        overlayRightStackView.translatesAutoresizingMaskIntoConstraints = false
        overlayRightStackView.axis = .horizontal
        overlayRightStackView.alignment = .center
        overlayRightStackView.distribution = .fill
        overlayRightStackView.spacing = 2
        overlayRightContainer.addSubview(overlayRightStackView)

        overlayRightTopConstraint = overlayRightContainer.topAnchor.constraint(equalTo: overlayHostView.topAnchor)

        NSLayoutConstraint.activate([
            overlayRightContainer.trailingAnchor.constraint(equalTo: overlayHostView.trailingAnchor, constant: -10),
            overlayRightTopConstraint!,
            overlayRightContainer.heightAnchor.constraint(equalToConstant: 44),

            overlayRightStackView.leadingAnchor.constraint(equalTo: overlayRightContainer.leadingAnchor),
            overlayRightStackView.trailingAnchor.constraint(equalTo: overlayRightContainer.trailingAnchor),
            overlayRightStackView.topAnchor.constraint(equalTo: overlayRightContainer.topAnchor),
            overlayRightStackView.bottomAnchor.constraint(equalTo: overlayRightContainer.bottomAnchor)
        ])
    }

    private func installOverlayHostIfNeeded() {
        guard overlayHostView.superview == nil else { return }

        overlayHostView.frame = view.convert(navigationBar.bounds, from: navigationBar)
        overlayHostView.backgroundColor = .clear
        overlayHostView.autoresizingMask = [.flexibleWidth, .flexibleBottomMargin]
        view.addSubview(overlayHostView)
        view.bringSubviewToFront(overlayHostView)
    }

    private func updateOverlayHostFrame() {
        guard overlayHostView.superview != nil else { return }
        let targetFrame = view.convert(navigationBar.bounds, from: navigationBar)
        if overlayHostView.frame.integral != targetFrame.integral {
            overlayHostView.frame = targetFrame
        }
    }

    private func prepareOverlayIfNeeded(for viewController: UIViewController, shouldShowBack: Bool) {
        if let configurable = viewController as? BFOverlayNavigationConfigurable {
            applyConfigurableOverlay(for: configurable, viewController: viewController, shouldShowBack: shouldShowBack)
            bringOverlayViewsToFrontIfNeeded()
            navigationBar.layoutIfNeeded()
            return
        }

        if let provider = viewController as? BFOverlayBackButtonProviding {
            viewController.navigationItem.hidesBackButton = true
            viewController.navigationItem.leftBarButtonItem = nil
            viewController.navigationItem.leftBarButtonItems = nil

            configureImageDisplay(
                for: overlayBackButton,
                image: provider.overlayBackButtonImage,
                preservesOriginalSize: true,
                contentInsets: .zero,
                debugKey: "back"
            )
            overlayBackContainer.isHidden = !shouldShowBack

            overlayRightContainer.isHidden = true
            clearRightOverlayButtons()

            bringOverlayViewsToFrontIfNeeded()
            navigationBar.layoutIfNeeded()
            return
        }

        hideAllOverlays()
    }

    private func applyConfigurableOverlay(
        for configurable: BFOverlayNavigationConfigurable,
        viewController: UIViewController,
        shouldShowBack: Bool
    ) {
        let config = configurable.overlayNavigationConfig

        if let title = config.title {
            viewController.navigationItem.title = title
            if config.usesSystemTitle {
                viewController.navigationItem.titleView = nil
            }
        }

        if config.clearsSystemBarButtonItems {
            viewController.navigationItem.hidesBackButton = true
            viewController.navigationItem.leftBarButtonItem = nil
            viewController.navigationItem.leftBarButtonItems = nil
            viewController.navigationItem.rightBarButtonItem = nil
            viewController.navigationItem.rightBarButtonItems = nil
        }

        let shouldShowOverlayBack = config.showsBackButton ?? shouldShowBack
        overlayBackContainer.isHidden = !shouldShowOverlayBack
        configureImageDisplay(
            for: overlayBackButton,
            image: config.backButtonImage,
            preservesOriginalSize: config.preservesBackImageOriginalSize,
            contentInsets: .zero,
            debugKey: "back"
        )

        renderRightItems(config.rightItems)
    }

    private func renderRightItems(_ items: [BFOverlayNavigationRightItem]) {
        clearRightOverlayButtons()
        rightItemIdentifiers = items.map(\.identifier)

        guard !items.isEmpty else {
            overlayRightContainer.isHidden = true
            return
        }

        overlayRightContainer.isHidden = false

        for (index, item) in items.enumerated() {
            let button = UIButton(type: .custom)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.tag = index
            button.contentHorizontalAlignment = .center
            button.contentVerticalAlignment = .center
            button.clipsToBounds = false
            button.contentEdgeInsets = item.contentInsets
            button.addTarget(self, action: #selector(handleOverlayRightTapped(_:)), for: .touchUpInside)

            switch item.content {
            case let .image(image):
                configureImageDisplay(
                    for: button,
                    image: image,
                    preservesOriginalSize: item.preservesImageOriginalSize,
                    contentInsets: item.contentInsets,
                    debugKey: "right[\(item.identifier)]"
                )
            case let .text(title):
                configureImageDisplay(
                    for: button,
                    image: nil,
                    preservesOriginalSize: true,
                    contentInsets: .zero,
                    debugKey: "right[\(item.identifier)]"
                )
                button.setTitle(title, for: .normal)
                button.setTitleColor(item.textColor, for: .normal)
                button.titleLabel?.font = item.font
            }

            let wrapper = UIView()
            wrapper.translatesAutoresizingMaskIntoConstraints = false
            wrapper.backgroundColor = .clear
            wrapper.addSubview(button)

            NSLayoutConstraint.activate([
                wrapper.widthAnchor.constraint(equalToConstant: max(44, item.hitSize.width)),
                wrapper.heightAnchor.constraint(equalToConstant: max(44, item.hitSize.height)),

                button.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
                button.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
                button.topAnchor.constraint(equalTo: wrapper.topAnchor),
                button.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor)
            ])

            overlayRightStackView.addArrangedSubview(wrapper)
        }
    }

    private func clearRightOverlayButtons() {
        rightItemIdentifiers.removeAll()
        overlayRightStackView.arrangedSubviews.forEach { arranged in
            overlayRightStackView.removeArrangedSubview(arranged)
            arranged.removeFromSuperview()
        }
    }

    private func configureImageDisplay(
        for button: UIButton,
        image: UIImage?,
        preservesOriginalSize: Bool,
        contentInsets: UIEdgeInsets,
        debugKey: String
    ) {
        clearImageDisplay(for: button)
        button.setImage(nil, for: .normal)
        button.contentEdgeInsets = .zero

        guard let image else { return }
        let rendered = image.withRenderingMode(.alwaysOriginal)

        if preservesOriginalSize {
            let imageView = UIImageView(image: rendered)
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.contentMode = .center
            imageView.tag = overlayImageViewTag
            button.addSubview(imageView)

            NSLayoutConstraint.activate([
                imageView.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                imageView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: rendered.size.width),
                imageView.heightAnchor.constraint(equalToConstant: rendered.size.height)
            ])
        } else {
            button.setImage(rendered, for: .normal)
            button.imageView?.contentMode = .scaleAspectFit
            button.contentEdgeInsets = contentInsets
        }
    }

    private func clearImageDisplay(for button: UIButton) {
        button.subviews
            .filter { $0.tag == overlayImageViewTag }
            .forEach { $0.removeFromSuperview() }
        button.setTitle(nil, for: .normal)
    }

    private func updateOverlayVerticalAlignment(for viewController: UIViewController?) {
        let safeFrame = navigationBar.safeAreaLayoutGuide.layoutFrame
        let targetCenterY = resolvedOverlayContentCenterY(for: viewController)

        let contentTop = targetCenterY - 22
        overlayBackTopConstraint?.constant = contentTop
        overlayRightTopConstraint?.constant = contentTop
        overlayContentYOffset = targetCenterY - safeFrame.midY
    }

    private func performOverlayAlignmentPass(for viewController: UIViewController?) {
        if isNavigationBarHidden {
            hideAllOverlays()
            overlayHostView.isHidden = true
            return
        }
        overlayHostView.isHidden = false
        enforceNavigationBarOriginYToStatusBarBottomIfNeeded()
        applyNavigationBarAlpha(for: viewController)
        installOverlayHostIfNeeded()
        navigationBar.layoutIfNeeded()
        updateOverlayHostFrame()
        updateOverlayVerticalAlignment(for: viewController)
        overlayHostView.layoutIfNeeded()
        alignCustomTitleViewToOverlayCenterIfNeeded(for: viewController)
        bringOverlayViewsToFrontIfNeeded()
    }

    // Keep system nav bar height untouched; only correct vertical origin to status bar bottom.
    private func enforceNavigationBarOriginYToStatusBarBottomIfNeeded() {
        guard !isNavigationBarHidden else { return }
        guard let window = viewIfLoaded?.window,
              let container = navigationBar.superview else { return }

        let statusBottomInWindow = currentStatusBarBottom(statusBarHidden: currentStatusBarHidden())
        let targetOriginInContainer = container.convert(CGPoint(x: 0, y: statusBottomInWindow), from: window)
        let targetY = targetOriginInContainer.y

        var frame = navigationBar.frame
        guard abs(frame.minY - targetY) > 0.5 else { return }
        frame.origin.y = targetY
        navigationBar.frame = frame
    }

    private func applyNavigationBarAlpha(for viewController: UIViewController?) {
        let targetAlpha: CGFloat
        if let provider = viewController as? BFOverlayNavigationBarAlphaProviding {
            targetAlpha = max(0, min(provider.overlayNavigationBarAlpha, 1))
        } else {
            targetAlpha = 1
        }
        if abs(navigationBar.alpha - targetAlpha) > 0.001 {
            UIView.performWithoutAnimation {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                navigationBar.layer.removeAllAnimations()
                navigationBar.alpha = targetAlpha
                navigationBar.layoutIfNeeded()
                CATransaction.commit()
            }
        }
    }

    private func resolvedOverlayContentCenterY(for _: UIViewController?) -> CGFloat {
        let safeFrame = navigationBar.safeAreaLayoutGuide.layoutFrame
        if let window = viewIfLoaded?.window {
            let navBarFrameInWindow = navigationBar.convert(navigationBar.bounds, to: window)
            if !isNavigationBarOnScreen(navBarFrameInWindow, in: window) {
                return safeFrame.midY
            }
        }
        return safeFrame.midY
    }

    private func resolvedOverlayContentLaneRectInNavigationBar(for viewController: UIViewController?) -> CGRect {
        let safeFrame = navigationBar.safeAreaLayoutGuide.layoutFrame
        if safeFrame.height > 0.01 { return safeFrame }
        let navBounds = navigationBar.bounds
        if let viewController, let titleFrame = resolveTitleFrameInNavigationBar(for: viewController) {
            return CGRect(x: navBounds.minX, y: titleFrame.minY, width: navBounds.width, height: titleFrame.height)
        }
        return navBounds
    }

    private func alignCustomTitleViewToOverlayCenterIfNeeded(for viewController: UIViewController?) {
        guard let window = viewIfLoaded?.window else { return }
        let navBarFrameInWindow = navigationBar.convert(navigationBar.bounds, to: window)
        guard isNavigationBarOnScreen(navBarFrameInWindow, in: window) else { return }

        let targetCenterY: CGFloat
        if !overlayBackContainer.isHidden {
            targetCenterY = overlayBackContainer.convert(overlayBackContainer.bounds, to: navigationBar).midY
        } else if !overlayRightContainer.isHidden {
            targetCenterY = overlayRightContainer.convert(overlayRightContainer.bounds, to: navigationBar).midY
        } else {
            targetCenterY = resolvedOverlayContentCenterY(for: viewController)
        }

        guard let titleView = viewController?.navigationItem.titleView else { return }
        if titleView.superview == nil {
            navigationBar.layoutIfNeeded()
        }
        guard let titleSuperview = titleView.superview else { return }
        titleView.layoutIfNeeded()
        titleView.transform = .identity
        let baseFrameInNav = titleView.convert(titleView.bounds, to: navigationBar)
        let deltaY = targetCenterY - baseFrameInNav.midY
        guard abs(deltaY) >= 0.5 else { return }

        let targetCenterInNav = CGPoint(x: baseFrameInNav.midX, y: targetCenterY)
        let targetCenterInSuperview = titleSuperview.convert(targetCenterInNav, from: navigationBar)
        titleView.center = CGPoint(x: titleView.center.x, y: targetCenterInSuperview.y)
    }

    private func isNavigationBarOnScreen(_ navBarFrameInWindow: CGRect, in window: UIWindow) -> Bool {
        let visibleWindowBounds = window.bounds
        guard navBarFrameInWindow.maxY > visibleWindowBounds.minY + 0.5 else { return false }
        guard navBarFrameInWindow.minY < visibleWindowBounds.maxY - 0.5 else { return false }
        return true
    }

    private func hideAllOverlays() {
        overlayBackContainer.isHidden = true
        overlayRightContainer.isHidden = true
        clearRightOverlayButtons()
    }

    private func prefersNavigationBarHidden(for viewController: UIViewController?) -> Bool {
        (viewController as? BFOverlayNavigationBarVisibilityProviding)?.overlayPrefersNavigationBarHidden ?? false
    }

    private func applyNavigationBarHiddenPreferenceIfNeeded(for viewController: UIViewController?) {
        let shouldHide = prefersNavigationBarHidden(for: viewController)
        guard isNavigationBarHidden != shouldHide else { return }
        setNavigationBarHidden(shouldHide, animated: false)
        view.layoutIfNeeded()
    }

    private func bringOverlayViewsToFrontIfNeeded() {
        guard overlayHostView.superview != nil else { return }
        view.bringSubviewToFront(overlayHostView)
        if !overlayBackContainer.isHidden {
            overlayHostView.bringSubviewToFront(overlayBackContainer)
        }
        if !overlayRightContainer.isHidden {
            overlayHostView.bringSubviewToFront(overlayRightContainer)
        }
    }

    @objc private func handleOverlayBackTapped() {
        if let configurable = topViewController as? BFOverlayNavigationConfigurable,
           configurable.overlayNavigationControllerDidTapBack(self) {
            return
        }
        _ = popViewController(animated: true)
    }

    @objc private func handleOverlayRightTapped(_ sender: UIButton) {
        guard rightItemIdentifiers.indices.contains(sender.tag) else { return }
        let identifier = rightItemIdentifiers[sender.tag]
        guard let configurable = topViewController as? BFOverlayNavigationConfigurable else { return }
        configurable.overlayNavigationController(self, didTapRightItemWith: identifier)
    }

    private func notifyRootLevel() {
        onRootLevelChanged?(viewControllers.count <= 1)
    }

    private func performOverlayUpdatesWithoutAnimation(_ updates: () -> Void) {
        UIView.performWithoutAnimation {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            navigationBar.layer.removeAllAnimations()
            overlayHostView.layer.removeAllAnimations()
            overlayBackContainer.layer.removeAllAnimations()
            overlayRightContainer.layer.removeAllAnimations()
            overlayRightStackView.layer.removeAllAnimations()
            updates()
            navigationBar.layoutIfNeeded()
            overlayHostView.layoutIfNeeded()
            CATransaction.commit()
        }
    }

    private func logNavigationLayoutIfNeeded(context: String, viewController: UIViewController?) {
        #if DEBUG
        guard navigationDebugLoggingEnabled else { return }
        guard let viewController else { return }

        let navBar = navigationBar
        let safeFrame = navBar.safeAreaLayoutGuide.layoutFrame
        let safeMidX = safeFrame.midX
        let safeMidY = safeFrame.midY
        let resolvedCenterY = resolvedOverlayContentCenterY(for: viewController)

        let backContainerInNav = overlayBackContainer.convert(overlayBackContainer.bounds, to: navBar)
        let backButtonInNav = overlayBackButton.convert(overlayBackButton.bounds, to: navBar)
        let rightContainerInNav = overlayRightContainer.convert(overlayRightContainer.bounds, to: navBar)
        let rightFirstItemInNav = overlayRightStackView.arrangedSubviews.first?.convert(
            overlayRightStackView.arrangedSubviews.first?.bounds ?? .zero,
            to: navBar
        )
        let backContainerInHost = overlayBackContainer.convert(overlayBackContainer.bounds, to: overlayHostView)
        let rightContainerInHost = overlayRightContainer.convert(overlayRightContainer.bounds, to: overlayHostView)
        let backContainerInWindow = overlayBackContainer.window.map { overlayBackContainer.convert(overlayBackContainer.bounds, to: $0) }
        let rightContainerInWindow = overlayRightContainer.window.map { overlayRightContainer.convert(overlayRightContainer.bounds, to: $0) }
        let overlayHostInWindow = overlayHostView.window.map { overlayHostView.convert(overlayHostView.bounds, to: $0) }

        let titleFrameInNav = resolveTitleFrameInNavigationBar(for: viewController)
        let titleFrameInWindow = viewController.navigationItem.titleView?.window.map {
            viewController.navigationItem.titleView?.convert(viewController.navigationItem.titleView?.bounds ?? .zero, to: $0) ?? .zero
        }
        let statusBarHidden = currentStatusBarHidden()
        let statusBarBottom = currentStatusBarBottom(statusBarHidden: statusBarHidden)
        let rawStatusBarBottom = currentRawStatusBarBottom()
        let contentLane = resolvedOverlayContentLaneRectInNavigationBar(for: viewController)
        let windowSafeTop = viewIfLoaded?.window?.safeAreaInsets.top ?? 0
        let navBarInWindow = viewIfLoaded?.window.map { navBar.convert(navBar.bounds, to: $0) }
        let navBarOnScreen: Bool = {
            guard let window = viewIfLoaded?.window, let navBarInWindow else { return false }
            return isNavigationBarOnScreen(navBarInWindow, in: window)
        }()

        let backCenterDeltaY = overlayBackContainer.isHidden ? nil : backContainerInNav.midY - safeMidY
        let titleCenterDeltaY = titleFrameInNav.map { $0.midY - safeMidY }
        let rightCenterDeltaY = overlayRightContainer.isHidden ? nil : rightContainerInNav.midY - safeMidY
        let backTitleCenterDeltaY: CGFloat? = {
            guard !overlayBackContainer.isHidden, let titleFrameInNav else { return nil }
            return backContainerInNav.midY - titleFrameInNav.midY
        }()
        let titleCenterDeltaX = titleFrameInNav.map { $0.midX - safeMidX }
        let backGapToStatusBottom = navBarOnScreen ? backContainerInWindow.map { $0.minY - statusBarBottom } : nil
        let titleGapToStatusBottom = navBarOnScreen ? titleFrameInWindow.map { $0.minY - statusBarBottom } : nil
        let rightGapToStatusBottom = navBarOnScreen ? rightContainerInWindow.map { $0.minY - statusBarBottom } : nil
        let backGapToWindowSafeTop = navBarOnScreen ? backContainerInWindow.map { $0.minY - windowSafeTop } : nil
        let titleGapToWindowSafeTop = navBarOnScreen ? titleFrameInWindow.map { $0.minY - windowSafeTop } : nil
        let rightGapToWindowSafeTop = navBarOnScreen ? rightContainerInWindow.map { $0.minY - windowSafeTop } : nil

        let signature = [
            formatRect(navBar.bounds),
            formatRect(safeFrame),
            formatRect(backContainerInNav),
            formatRect(backButtonInNav),
            formatRect(rightContainerInNav),
            formatRect(titleFrameInNav ?? .zero),
            "\(overlayBackContainer.isHidden)",
            "\(overlayRightContainer.isHidden)",
            "\(overlayRightStackView.arrangedSubviews.count)",
            viewController.navigationItem.title ?? "",
            String(describing: type(of: viewController))
        ].joined(separator: "|")
        if context == "layout", signature == lastLayoutLogSignature { return }
        lastLayoutLogSignature = signature
        #endif
    }

    private func resolveTitleFrameInNavigationBar(for viewController: UIViewController) -> CGRect? {
        if let titleView = viewController.navigationItem.titleView {
            return titleView.convert(titleView.bounds, to: navigationBar)
        }
        guard let title = viewController.navigationItem.title, !title.isEmpty else { return nil }
        if let label = findVisibleTitleLabel(in: navigationBar, expectedText: title) {
            return label.convert(label.bounds, to: navigationBar)
        }
        return nil
    }

    private func findVisibleTitleLabel(in rootView: UIView, expectedText: String) -> UILabel? {
        for subview in rootView.subviews {
            if let label = subview as? UILabel,
               label.text == expectedText,
               !label.isHidden,
               label.alpha > 0.01,
               label.bounds.width > 0.5,
               label.bounds.height > 0.5 {
                return label
            }
            if let nested = findVisibleTitleLabel(in: subview, expectedText: expectedText) {
                return nested
            }
        }
        return nil
    }

    private func currentStatusBarBottom() -> CGFloat {
        let hidden = currentStatusBarHidden()
        return currentStatusBarBottom(statusBarHidden: hidden)
    }

    private func currentStatusBarBottom(statusBarHidden: Bool) -> CGFloat {
        guard let window = viewIfLoaded?.window else { return 0 }
        let raw = currentRawStatusBarBottom(in: window)
        if statusBarHidden { return 0 }
        if raw > 0.01 { return raw }
        return 0
    }

    private func currentStatusBarHidden() -> Bool {
        guard let window = viewIfLoaded?.window else { return false }
        return window.windowScene?.statusBarManager?.isStatusBarHidden ?? false
    }

    private func currentRawStatusBarBottom() -> CGFloat {
        guard let window = viewIfLoaded?.window else { return 0 }
        return currentRawStatusBarBottom(in: window)
    }

    private func currentRawStatusBarBottom(in window: UIWindow) -> CGFloat {
        guard let frame = window.windowScene?.statusBarManager?.statusBarFrame else { return 0 }
        let coordinateSpace = window.windowScene?.coordinateSpace ?? window.screen.coordinateSpace
        let frameInWindow = window.convert(frame, from: coordinateSpace)
        return frameInWindow.maxY
    }

    private func formatRect(_ rect: CGRect?) -> String {
        guard let rect else { return "nil" }
        return String(format: "(x:%.1f,y:%.1f,w:%.1f,h:%.1f)", rect.origin.x, rect.origin.y, rect.size.width, rect.size.height)
    }

    private func formatNumber(_ value: CGFloat?) -> String {
        guard let value else { return "nil" }
        return String(format: "%.2f", value)
    }

    private func formatSize(_ size: CGSize) -> String {
        String(format: "%.1fx%.1f", size.width, size.height)
    }

    private func elapsedMilliseconds(since start: TimeInterval) -> Int {
        Int((ProcessInfo.processInfo.systemUptime - start) * 1000)
    }

    private func elapsedMillisecondsSincePushBegin() -> Int {
        guard let pushBeginUptime else { return -1 }
        return elapsedMilliseconds(since: pushBeginUptime)
    }

    private func elapsedMillisecondsSinceWillShowBegin() -> Int {
        guard let willShowBeginUptime else { return -1 }
        return elapsedMilliseconds(since: willShowBeginUptime)
    }

    private func elapsedMillisecondsSinceDidShowBegin() -> Int {
        guard let didShowBeginUptime else { return -1 }
        return elapsedMilliseconds(since: didShowBeginUptime)
    }

    private func beginTransitionInputBlock(reason _: String) {
        transitionInputTimeoutWorkItem?.cancel()
        transitionInputUnlockWorkItem?.cancel()
        transitionInputUnlockWorkItem = nil

        if !isTransitionInputBlocked {
            isTransitionInputBlocked = true
            view.isUserInteractionEnabled = false
        }

        let timeoutWorkItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.isTransitionInputBlocked else { return }
            self.isPushInFlight = false
            self.isTransitionInputBlocked = false
            self.view.isUserInteractionEnabled = true
            self.transitionInputTimeoutWorkItem = nil
            self.transitionInputUnlockWorkItem = nil
        }
        transitionInputTimeoutWorkItem = timeoutWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + transitionInputTimeout, execute: timeoutWorkItem)
    }

    private func finishTransitionInputBlock(reason _: String, delay: TimeInterval = 0) {
        transitionInputTimeoutWorkItem?.cancel()
        transitionInputTimeoutWorkItem = nil
        transitionInputUnlockWorkItem?.cancel()

        let unlockWorkItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.isTransitionInputBlocked else { return }
            self.isTransitionInputBlocked = false
            self.view.isUserInteractionEnabled = true
            self.transitionInputUnlockWorkItem = nil
        }
        transitionInputUnlockWorkItem = unlockWorkItem

        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: unlockWorkItem)
        } else {
            DispatchQueue.main.async(execute: unlockWorkItem)
        }
    }

    private func controllerName(_ viewController: UIViewController?) -> String {
        guard let viewController else { return "nil" }
        return String(describing: type(of: viewController))
    }

    private func uptimeMilliseconds() -> Int {
        Int(ProcessInfo.processInfo.systemUptime * 1000)
    }

    private func logPerf(_ message: String) {
        #if DEBUG
        guard navigationPerformanceLoggingEnabled else { return }
        print("[图片工具] \(message)")
        #endif
    }
}

extension BFOverlayNavigationController: UINavigationControllerDelegate {
    public func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
        let willShowStart = ProcessInfo.processInfo.systemUptime
        willShowBeginUptime = willShowStart
        beginTransitionInputBlock(reason: "willShow vc=\(controllerName(viewController))")
        logPerf(
            "动作=性能 来源=导航容器 事件=willShow入口 主线程=\(Thread.isMainThread) " +
            "系统启动毫秒=\(uptimeMilliseconds()) 动画=\(animated) vc=\(controllerName(viewController)) " +
            "距push毫秒=\(elapsedMillisecondsSincePushBegin())"
        )
        let shouldShowBack: Bool = {
            guard let index = navigationController.viewControllers.firstIndex(of: viewController) else {
                return navigationController.viewControllers.count > 1
            }
            return index > 0
        }()
        let overlayStart = ProcessInfo.processInfo.systemUptime
        performOverlayUpdatesWithoutAnimation {
            applyNavigationBarHiddenPreferenceIfNeeded(for: viewController)
            prepareOverlayIfNeeded(for: viewController, shouldShowBack: shouldShowBack)
            applyNavigationBarAlpha(for: viewController)
            navigationController.view.layoutIfNeeded()
            performOverlayAlignmentPass(for: viewController)
        }
        logPerf(
            "动作=性能 来源=导航容器 事件=willShow覆盖层更新完成 主线程=\(Thread.isMainThread) " +
            "耗时毫秒=\(elapsedMilliseconds(since: overlayStart)) vc=\(controllerName(viewController))"
        )
        logNavigationLayoutIfNeeded(context: "willShow", viewController: viewController)
        logPerf(
            "动作=性能 来源=导航容器 事件=willShow完成 主线程=\(Thread.isMainThread) " +
            "总耗时毫秒=\(elapsedMilliseconds(since: willShowStart)) vc=\(controllerName(viewController))"
        )
    }

    public func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool) {
        let didShowStart = ProcessInfo.processInfo.systemUptime
        didShowBeginUptime = didShowStart
        isPushInFlight = false
        logPerf(
            "动作=性能 来源=导航容器 事件=didShow入口 主线程=\(Thread.isMainThread) " +
            "系统启动毫秒=\(uptimeMilliseconds()) 动画=\(animated) vc=\(controllerName(viewController)) " +
            "距push毫秒=\(elapsedMillisecondsSincePushBegin()) 距willShow毫秒=\(elapsedMillisecondsSinceWillShowBegin())"
        )
        let overlayStart = ProcessInfo.processInfo.systemUptime
        performOverlayUpdatesWithoutAnimation {
            applyNavigationBarHiddenPreferenceIfNeeded(for: viewController)
            prepareOverlayIfNeeded(for: viewController, shouldShowBack: viewControllers.count > 1)
            applyNavigationBarAlpha(for: viewController)
            navigationController.view.layoutIfNeeded()
            performOverlayAlignmentPass(for: viewController)
        }
        logPerf(
            "动作=性能 来源=导航容器 事件=didShow覆盖层更新完成 主线程=\(Thread.isMainThread) " +
            "耗时毫秒=\(elapsedMilliseconds(since: overlayStart)) vc=\(controllerName(viewController))"
        )
        logNavigationLayoutIfNeeded(context: "didShow", viewController: viewController)
        notifyRootLevel()
        onDidShowViewController?(viewController)
        logPerf(
            "动作=性能 来源=导航容器 事件=didShow完成 主线程=\(Thread.isMainThread) " +
            "总耗时毫秒=\(elapsedMilliseconds(since: didShowStart)) vc=\(controllerName(viewController)) " +
            "距push毫秒=\(elapsedMillisecondsSincePushBegin())"
        )
        finishTransitionInputBlock(reason: "didShow vc=\(controllerName(viewController))", delay: didShowInputUnlockDelay)

        DispatchQueue.main.async { [weak self, weak viewController] in
            guard let self, let viewController else { return }
            guard self.topViewController === viewController else { return }
            let deferredStart = ProcessInfo.processInfo.systemUptime
            self.performOverlayUpdatesWithoutAnimation {
                self.view.layoutIfNeeded()
                self.performOverlayAlignmentPass(for: viewController)
            }
            self.logNavigationLayoutIfNeeded(context: "didShowDeferred", viewController: viewController)
            self.logPerf(
                "动作=性能 来源=导航容器 事件=didShow延迟对齐完成 主线程=\(Thread.isMainThread) " +
                "耗时毫秒=\(self.elapsedMilliseconds(since: deferredStart)) vc=\(self.controllerName(viewController)) " +
                "距didShow毫秒=\(self.elapsedMillisecondsSinceDidShowBegin()) 距push毫秒=\(self.elapsedMillisecondsSincePushBegin())"
            )
        }
    }
}
