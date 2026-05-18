import SwiftUI

enum Theme {

    // MARK: - Brand

    enum Brand {
        // #3549A8
        static let primary = Color(red: 0.208, green: 0.286, blue: 0.659)
        // #2F3F91
        static let primaryDark = Color(red: 0.184, green: 0.247, blue: 0.569)
        // #6F7FD6
        static let primaryMuted = Color(red: 0.435, green: 0.498, blue: 0.839)
        // #EEF1FF
        static let softTint = Color(red: 0.933, green: 0.945, blue: 1.0)

        static let heroGradient = LinearGradient(
            colors: [primary, primaryDark],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Semantic

    enum Semantic {
        // #22C55E
        static let recovery = Color(red: 0.133, green: 0.773, blue: 0.369)
        static let endurance = Brand.primary
        static let quality = Color(.systemOrange)
        static let caution = Color(.systemOrange)
        // #EF4444
        static let strain = Color(red: 0.937, green: 0.267, blue: 0.267)
    }

    // MARK: - Surfaces

    enum Surface {
        // #F6F7FB light / system dark
        static let background = Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? .systemBackground
                : UIColor(red: 0.965, green: 0.969, blue: 0.984, alpha: 1)
        })
        // White light / elevated dark
        static let card = Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? .secondarySystemGroupedBackground
                : .white
        })
        static let coachCallout = card
        static let selectedControl = Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.208, green: 0.286, blue: 0.659, alpha: 0.25)
                : UIColor(red: 0.933, green: 0.945, blue: 1.0, alpha: 1)
        })
        static let unselectedControl = Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? .tertiarySystemGroupedBackground
                : UIColor(red: 0.965, green: 0.969, blue: 0.984, alpha: 1)
        })
    }

    // MARK: - Text (on-brand surfaces)

    enum TextStyle {
        static let onBrand = Color.white
        static let onBrandSecondary = Color.white.opacity(0.78)
        static let onBrandTertiary = Color.white.opacity(0.45)
    }

    // MARK: - Border

    enum Border {
        // #E2E5EC
        static let subtle = Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 0.25, alpha: 1)
                : UIColor(red: 0.886, green: 0.898, blue: 0.925, alpha: 1)
        })
        static let selected = Brand.primary
        static let width: CGFloat = 1
        static let selectedWidth: CGFloat = 2
    }

    // MARK: - Spacing

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let section: CGFloat = 28
    }

    // MARK: - Corner Radius

    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 14
        static let xl: CGFloat = 20
    }
}
