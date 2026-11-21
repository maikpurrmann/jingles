import AppKit
import QuartzCore
import SwiftUI

struct PlaybackProgressBar: NSViewRepresentable {
    let progress: Double
    let duration: TimeInterval
    let run: UInt64?

    func makeNSView(context: Context) -> PlaybackTrackView {
        PlaybackTrackView(frame: .zero)
    }

    func updateNSView(_ view: PlaybackTrackView, context: Context) {
        view.display(progress: progress, duration: duration, run: run)
    }
}

final class PlaybackTrackView: NSView {
    private let fill = CALayer()
    private var currentRun: UInt64?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        fill.anchorPoint = CGPoint(x: 0, y: 0.5)
        layer?.addSublayer(fill)
        updateColor()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fill.bounds = CGRect(origin: .zero, size: bounds.size)
        fill.position = CGPoint(x: bounds.minX, y: bounds.midY)
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColor()
    }

    func display(progress: Double, duration: TimeInterval, run: UInt64?) {
        // Keep one compositor animation for this run. Countdown and selection updates
        // must leave it in flight.
        if let run, run == currentRun { return }
        currentRun = run

        let timeLeft = duration * (1 - progress)
        let isAdvancing = run != nil && timeLeft.isFinite && timeLeft > 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fill.removeAnimation(forKey: "playback")
        fill.transform = CATransform3DMakeScale(isAdvancing ? 1 : progress, 1, 1)
        if isAdvancing {
            let animation = CABasicAnimation(keyPath: "transform.scale.x")
            animation.fromValue = progress
            animation.toValue = 1.0
            animation.duration = timeLeft
            animation.timingFunction = CAMediaTimingFunction(name: .linear)
            fill.add(animation, forKey: "playback")
        }
        CATransaction.commit()
    }

    private func updateColor() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            fill.backgroundColor = NSColor.controlAccentColor.cgColor
            CATransaction.commit()
        }
    }
}
