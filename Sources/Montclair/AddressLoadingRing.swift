import AppKit
import QuartzCore

/// A non-interactive border overlay; the address field keeps its entire hit area.
@MainActor
final class AddressLoadingRing: NSView {
    private let gradient = CAGradientLayer()
    private let border = CAShapeLayer()
    private var loading = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        gradient.colors = [0xC69A4F, 0xF5D998, 0xE3EDFF, 0x719CEF, 0xB3C9F5, 0xF5D998, 0xC69A4F].map {
            NSColor(hex: $0).cgColor
        }
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        border.fillColor = NSColor.clear.cgColor
        border.strokeColor = NSColor.white.cgColor
        border.lineWidth = 3.5
        gradient.opacity = 1
        gradient.mask = border
        layer?.addSublayer(gradient)
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        border.frame = bounds
        border.path = CGPath(roundedRect: bounds.insetBy(dx: 2, dy: 2),
                             cornerWidth: max(0, bounds.height / 2 - 2),
                             cornerHeight: max(0, bounds.height / 2 - 2), transform: nil)
        CATransaction.commit()
    }

    func setLoading(_ active: Bool) {
        guard active != loading else { return }
        loading = active
        isHidden = !active
        gradient.removeAllAnimations()
        guard active, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        // Shift the palette along the border without rotating its rounded mask.
        let colors = gradient.colors ?? []
        let animation = CAKeyframeAnimation(keyPath: "colors")
        animation.values = (0...colors.count).map { offset in
            Array(colors.dropFirst(offset % colors.count)) + Array(colors.prefix(offset % colors.count))
        }
        animation.duration = 7
        animation.calculationMode = .linear
        animation.repeatCount = .infinity
        gradient.add(animation, forKey: "pearlShimmer")
    }
}
