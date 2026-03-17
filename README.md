# BFOverlayNavigation

Overlay-based `UINavigationController` helper for iOS 13+.

## What it solves

- Avoids system `UIBarButtonItem` rendering artifacts on newer iOS versions by using overlay buttons.
- Keeps back button/title vertical alignment stable across iPhone and iPad.
- Lets each page define different title/back image/right items.
- Uses `44x44` tap areas with icon rendering that keeps original aspect ratio (no deformation).

## Requirements

- iOS 13.0+
- Swift 5.0+

## Installation

### From CocoaPods Trunk (recommended)

```ruby
pod 'BFOverlayNavigation'
```

### From Git (SSH)

```ruby
pod 'BFOverlayNavigation', :git => 'git@github.com:mirbf/BFOverlayNavigation.git', :tag => '0.1.0'
```

### Local path (development)

```ruby
pod 'BFOverlayNavigation', :path => '/Users/bigger/Desktop/Pod/BFOverlayNavigation'
```

## Quick start

```swift
import BFOverlayNavigation

final class AppNavigationController: BFOverlayNavigationController {
}
```

### Back image (legacy/simple)

```swift
import BFOverlayNavigation

final class DetailViewController: UIViewController, BFOverlayBackButtonProviding {
    var overlayBackButtonImage: UIImage? { UIImage(named: "nav_back_icon") }
}
```

### Full per-page config

```swift
import BFOverlayNavigation

final class ProfileViewController: UIViewController, BFOverlayNavigationConfigurable {
    var overlayNavigationConfig: BFOverlayNavigationConfig {
        var items: [BFOverlayNavigationRightItem] = []
        if let image = UIImage(named: "pet_profile_add_icon") {
            items = [
                BFOverlayNavigationRightItem(
                    identifier: "add",
                    content: .image(image),
                    hitSize: CGSize(width: 44, height: 44)
                )
            ]
        }

        return BFOverlayNavigationConfig(
            title: "宠物档案",
            usesSystemTitle: true,
            showsBackButton: true,
            backButtonImage: UIImage(named: "ba_nav_back"),
            rightItems: items
        )
    }

    func overlayNavigationController(_ navigationController: BFOverlayNavigationController, didTapRightItemWith identifier: String) {
        if identifier == "add" {
            // handle action
        }
    }
}
```

## Notes

- Internal navigation debug line output (`logNavigationLine`) has been removed.
- Overlay tap area is `44x44`.
- Container edge insets are `10pt` from safe-area edges.

## Publish workflow

```bash
export https_proxy=http://127.0.0.1:7890 http_proxy=http://127.0.0.1:7890 all_proxy=socks5://127.0.0.1:7890
pod lib lint BFOverlayNavigation.podspec --allow-warnings
pod trunk push BFOverlayNavigation.podspec --allow-warnings
```
