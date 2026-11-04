import SwiftUI

enum Motion {
    /// Layout spring from DESIGN section 6 (response 0.45 s, damping 0.82).
    static let layout = Animation.spring(response: 0.45, dampingFraction: 0.82)
    /// Color and opacity changes.
    static let fade = Animation.easeOut(duration: 0.2)
    static let hover = Animation.spring(response: 0.32, dampingFraction: 0.72)
    static let digits = Animation.spring(response: 0.38, dampingFraction: 0.86)
}

enum Spacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let s: CGFloat = 12
    static let m: CGFloat = 16
    static let l: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}
