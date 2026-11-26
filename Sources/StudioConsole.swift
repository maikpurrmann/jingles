import AppKit
import SwiftUI

enum StudioPalette {
    static let amber = Color(nsColor: amberInk)
    static let amberInk = NSColor(srgbRed: 1, green: 0.73, blue: 0.35, alpha: 1)
    static let cream = Color(red: 0.95, green: 0.90, blue: 0.80)
    static let muted = Color(red: 0.76, green: 0.72, blue: 0.65)
    static let panel = Color(red: 0.15, green: 0.14, blue: 0.13)
}

private enum StudioMaterial {
    case wood, vinyl

    private static let woodImage = load("StudioWood")
    private static let vinylImage = load("StudioVinyl")

    private static func load(_ name: String) -> NSImage? {
        Bundle.main.url(forResource: name, withExtension: "jpg").flatMap { NSImage(contentsOf: $0) }
    }

    func surface(horizontalGrain: Bool = false) -> some View {
        let image = self == .wood ? Self.woodImage : Self.vinylImage
        let base = self == .wood ? Color(red: 0.49, green: 0.25, blue: 0.12) : StudioPalette.panel
        return base.overlay {
            if let image {
                GeometryReader { geometry in
                    let size = geometry.size
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: horizontalGrain ? size.height : size.width,
                               height: horizontalGrain ? size.width : size.height)
                        .clipped()
                        .rotationEffect(horizontalGrain ? .degrees(90) : .zero)
                        .frame(width: size.width, height: size.height)
                }
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }
}

struct StudioCase: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                woodRail(left: true)
                StudioMaterial.vinyl.surface()
                    .overlay {
                        LinearGradient(colors: [.black.opacity(0.06), .black.opacity(0.33)],
                                       startPoint: .top, endPoint: .bottom)
                    }
                woodRail(left: false)
            }
            StudioMaterial.wood.surface(horizontalGrain: true)
                .frame(height: 12)
                .overlay {
                    LinearGradient(colors: [.black.opacity(0.58), .clear, .black.opacity(0.36)],
                                   startPoint: .top, endPoint: .bottom)
                }
        }
        .accessibilityHidden(true)
    }

    private func woodRail(left: Bool) -> some View {
        StudioMaterial.wood.surface()
            .overlay {
                LinearGradient(colors: [.black.opacity(0.55), .clear, .black.opacity(0.28)],
                               startPoint: left ? .leading : .trailing,
                               endPoint: left ? .trailing : .leading)
            }
            .overlay(alignment: left ? .trailing : .leading) {
                Rectangle().fill(.black.opacity(0.62)).frame(width: 1)
            }
            .frame(width: 22)
    }
}

private struct StudioScrew: View {
    var body: some View {
        Circle()
            .fill(LinearGradient(colors: [.init(white: 0.34), .init(white: 0.10)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay { Circle().strokeBorder(.black.opacity(0.7), lineWidth: 0.7) }
            .overlay {
                Capsule()
                    .fill(.black.opacity(0.75))
                    .frame(width: 5, height: 1)
                    .rotationEffect(.degrees(-32))
            }
            .frame(width: 8, height: 8)
            .shadow(color: .black.opacity(0.55), radius: 1, y: 1)
            .accessibilityHidden(true)
    }
}

struct StudioNameplate: View {
    let folder: URL?

    var body: some View {
        let plate = RoundedRectangle(cornerRadius: 5)
        HStack(spacing: 9) {
            StudioScrew()
            VStack(spacing: 1) {
                Text("jingles")
                    .font(.system(size: 29, weight: .heavy, design: .rounded))
                    .tracking(-1.5)
                    .foregroundStyle(LinearGradient(colors: [StudioPalette.cream, StudioPalette.muted],
                                                    startPoint: .top, endPoint: .bottom))
                    .shadow(color: .black, radius: 0.6, y: 1)
                    .accessibilityLabel("Jingles")
                    .accessibilityAddTraits(.isHeader)
                Text(folder?.lastPathComponent ?? "Kein Ordner ausgewählt")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.1)
                    .textCase(.uppercase)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(StudioPalette.muted)
                    .frame(maxWidth: 146)
                    .help(folder?.path ?? "")
            }
            .fixedSize(horizontal: true, vertical: false)
            StudioScrew()
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background {
            plate.fill(LinearGradient(colors: [Color(white: 0.16), Color(white: 0.055)],
                                      startPoint: .top, endPoint: .bottom))
                .overlay { plate.strokeBorder(.black.opacity(0.9)) }
                .overlay { plate.strokeBorder(StudioPalette.cream.opacity(0.23), lineWidth: 0.5).padding(1) }
                .shadow(color: .black.opacity(0.65), radius: 2, y: 1)
        }
    }
}

struct StudioConsole: View {
    @ObservedObject var player: JinglePlayer

    private var targetLevel: Binding<Double> {
        Binding(get: { Double(player.loweredPercent) },
                set: { player.loweredPercent = Int($0) })
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                clock
                transport
            }
            .frame(maxWidth: .infinity)
            .padding(15)

            Rectangle()
                .fill(StudioPalette.cream.opacity(0.37))
                .frame(width: 1)
                .shadow(color: .black.opacity(0.8), radius: 0, x: 1)
                .padding(.vertical, 9)

            VStack(spacing: 9) {
                fadeSwitch
                HStack(spacing: 9) {
                    StudioDial("Zielpegel", value: targetLevel, range: 0...100, step: 1, unit: "%")
                    StudioDial("Fade runter", value: $player.fadeDownSeconds, range: 0...30, step: 0.1, unit: "s")
                    StudioDial("Fade hoch", value: $player.fadeUpSeconds, range: 0...30, step: 0.1, unit: "s")
                }
            }
            .padding(15)
        }
        .fixedSize(horizontal: false, vertical: true)
        .background {
            let frame = RoundedRectangle(cornerRadius: 5)
            StudioMaterial.vinyl.surface()
                .overlay {
                    LinearGradient(colors: [.white.opacity(0.04), .black.opacity(0.30)],
                                   startPoint: .top, endPoint: .bottom)
                }
                .clipShape(frame)
                .overlay { frame.strokeBorder(StudioPalette.cream.opacity(0.32)) }
                .overlay(alignment: .bottomLeading) { StudioScrew().padding(5) }
                .overlay(alignment: .bottomTrailing) { StudioScrew().padding(5) }
                .shadow(color: .black.opacity(0.62), radius: 4, y: 3)
        }
    }

    private var clock: some View {
        let seconds = player.remainingSeconds ?? 0
        let paused = player.canStop && !player.canPause
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(paused ? "Pausiert" : "Restzeit")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(1.3)
                    .textCase(.uppercase)
                    .foregroundStyle(StudioPalette.muted)
                Spacer(minLength: 8)
                Text("\(seconds / 60):\(String(format: "%02d", seconds % 60))")
                    .font(.system(size: 31, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .foregroundStyle(StudioPalette.amber.opacity(player.canStop ? 1 : 0.65))
                    .shadow(color: StudioPalette.amber.opacity(player.canStop ? 0.4 : 0), radius: 5)
            }
            PlaybackProgressBar(progress: player.playbackProgress, duration: player.playbackDuration,
                                run: player.canPause ? player.playbackRun : nil, tint: StudioPalette.amberInk)
                .frame(height: 3)
                .background(StudioPalette.amber.opacity(0.14), in: Capsule())
                .clipShape(Capsule())
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: 4)
                .fill(LinearGradient(colors: [Color(red: 0.16, green: 0.12, blue: 0.065),
                                              Color(red: 0.062, green: 0.043, blue: 0.021)],
                                     startPoint: .top, endPoint: .bottom))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 4).strokeBorder(StudioPalette.amber.opacity(0.23))
        }
        .accessibilityElement(children: .combine)
    }

    private var transport: some View {
        HStack(spacing: 7) {
            Button {
                player.play()
            } label: {
                Label("Abspielen", systemImage: "play.fill")
            }
            .buttonStyle(StudioKeyStyle(highlight: StudioPalette.cream))
            .help("Abspielen")
            .disabled(!player.canPlay)

            Button(action: player.pause) {
                Label("Pause", systemImage: "pause.fill")
            }
            .buttonStyle(StudioKeyStyle())
            .help("Pause")
            .disabled(!player.canPause)

            Button(action: player.stop) {
                Label("Stopp", systemImage: "stop.fill")
            }
            .buttonStyle(StudioKeyStyle())
            .help("Stopp")
            .disabled(!player.canStop)
        }
        .labelStyle(.iconOnly)
    }

    private var fadeSwitch: some View {
        let level = player.isLowered ? player.loweredPercent : 100
        let action = player.isLowered ? "Auf 100 % anheben" : "Auf \(player.loweredPercent) % absenken"
        return Button {
            player.toggleFade()
        } label: {
            HStack(spacing: 8) {
                rocker
                Text("FADE").tracking(1.2)
                Spacer(minLength: 6)
                Text("\(level) %").monospacedDigit()
            }
        }
        .buttonStyle(StudioKeyStyle())
        .help(action)
        .accessibilityLabel("Fade")
        .accessibilityValue("\(player.isLowered ? "Abgesenkt" : "Normal"), \(level) Prozent")
    }

    private var rocker: some View {
        let on = player.isLowered
        let amber = Color(red: 0.98, green: 0.58, blue: 0.26)
        let copper = Color(red: 0.79, green: 0.36, blue: 0.12)
        let base = RoundedRectangle(cornerRadius: 2)
        let cap = RoundedRectangle(cornerRadius: 0.8)
        return base.fill(Color(white: 0.045))
            .overlay { base.strokeBorder(.white.opacity(0.21), lineWidth: 0.6) }
            .overlay {
                cap.fill(LinearGradient(stops: [
                    .init(color: on ? copper : amber, location: 0),
                    .init(color: on ? copper : amber, location: 0.46),
                    .init(color: on ? amber : copper, location: 0.48),
                    .init(color: on ? amber : copper, location: 1)
                ], startPoint: .leading, endPoint: .trailing))
                .overlay {
                    cap.fill(LinearGradient(colors: [.white.opacity(0.25), .clear, .black.opacity(0.22)],
                                            startPoint: .top, endPoint: .bottom))
                }
                .overlay { cap.strokeBorder(.black.opacity(0.45), lineWidth: 0.6) }
                .padding(.horizontal, 3)
                .padding(.vertical, 2.5)
                .offset(x: on ? 1 : -1)
            }
            .frame(width: 32, height: 16)
            .accessibilityHidden(true)
    }

}

private struct StudioKeyStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var highlight: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        let lit = isEnabled ? highlight : nil
        let top = lit ?? Color(white: 0.30)
        let bottom = lit == nil ? Color(white: 0.18) : Color(red: 0.74, green: 0.69, blue: 0.57)
        let ink = lit == nil ? StudioPalette.cream : Color(white: 0.13)
        let key = RoundedRectangle(cornerRadius: 4)

        return configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(ink.opacity(isEnabled ? 1 : 0.38))
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .background {
                key.fill(LinearGradient(stops: [.init(color: top, location: 0),
                                                .init(color: top, location: 0.15),
                                                .init(color: bottom, location: 1)],
                                        startPoint: .top, endPoint: .bottom))
                    .overlay { key.strokeBorder(.white.opacity(0.20)) }
                    .shadow(color: .black.opacity(0.9), radius: 0.8, y: configuration.isPressed ? 0 : 2)
            }
            .contentShape(key)
            .offset(y: configuration.isPressed ? 1 : 0)
    }
}

private struct StudioDial: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String
    private var dragStart = State<Double?>(initialValue: nil)
    @GestureState private var isDragging = false

    init(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, unit: String) {
        self.title = title
        _value = value
        self.range = range
        self.step = step
        self.unit = unit
    }

    private var valueLabel: String {
        let format = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(step == 1 ? 0 : 1))
        return "\(value.formatted(format)) \(unit)"
    }

    var body: some View {
        VStack(spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(StudioPalette.cream)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            knob
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .updating($isDragging) { _, active, _ in active = true }
                        .onChanged { drag in
                            let start = dragStart.wrappedValue ?? value
                            dragStart.wrappedValue = start
                            setValue(start - Double(drag.translation.height) * step)
                        }
                )
                .onChange(of: isDragging) { active in
                    if !active {
                        dragStart.wrappedValue = nil
                    }
                }
            Text(valueLabel)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(StudioPalette.cream)
                .monospacedDigit()
        }
        .frame(width: 70)
        .help("\(title) · Zum Einstellen nach oben oder unten ziehen")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(valueLabel)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: setValue(value + step)
            case .decrement: setValue(value - step)
            @unknown default: break
            }
        }
    }

    private var knob: some View {
        let fraction = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        return ZStack {
            ForEach(0...10, id: \.self) { tick in
                Capsule()
                    .fill(StudioPalette.cream.opacity(tick.isMultiple(of: 5) ? 0.95 : 0.67))
                    .frame(width: 1.2, height: tick.isMultiple(of: 5) ? 5 : 3)
                    .offset(y: -26)
                    .rotationEffect(.degrees(-135 + Double(tick) * 27))
            }
            Circle()
                .fill(LinearGradient(colors: [Color(white: 0.38), Color(white: 0.055)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay { Circle().strokeBorder(.black.opacity(0.9)) }
                .frame(width: 44, height: 44)
                .shadow(color: .black.opacity(0.9), radius: 2, x: 1, y: 3)
            knurledEdge.rotationEffect(.degrees(fraction * 270))
            metalCap
            Capsule()
                .fill(StudioPalette.cream)
                .frame(width: 2, height: 7.5)
                .offset(y: -17.5)
                .rotationEffect(.degrees(-135 + fraction * 270))
        }
        .frame(width: 58, height: 58)
        .accessibilityHidden(true)
    }

    private var knurledEdge: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = size.width / 2
            for groove in 0..<32 {
                let angle = Double(groove) * 2 * .pi / 32
                let x = cos(angle)
                let y = sin(angle)
                var cut = Path()
                cut.move(to: CGPoint(x: center.x + x * (radius - 1), y: center.y + y * (radius - 1)))
                cut.addLine(to: CGPoint(x: center.x + x * (radius - 5), y: center.y + y * (radius - 5)))
                context.stroke(cut, with: .color(.black.opacity(0.55)), lineWidth: 1.2)
                context.stroke(cut.offsetBy(dx: 0.7, dy: 0.45),
                               with: .color(.white.opacity(0.15)), lineWidth: 0.7)
            }
        }
        .frame(width: 43, height: 43)
    }

    private var metalCap: some View {
        Circle()
            .fill(AngularGradient(colors: [Color(white: 0.38), StudioPalette.cream, Color(white: 0.56),
                                           Color(white: 0.36), StudioPalette.cream, Color(white: 0.38)],
                                  center: .center, angle: .degrees(-35)))
            .overlay {
                Canvas { context, size in
                    for offset in stride(from: 1.0, to: size.width / 2, by: 0.9) {
                        let ring = CGRect(x: offset, y: offset, width: size.width - 2 * offset,
                                          height: size.height - 2 * offset)
                        context.stroke(Path(ellipseIn: ring), with: .color(.black.opacity(0.14)), lineWidth: 0.45)
                    }
                }
                .clipShape(Circle())
            }
            .overlay { Circle().strokeBorder(.black.opacity(0.7), lineWidth: 0.6) }
            .frame(width: 26, height: 26)
            .shadow(color: .black.opacity(0.7), radius: 1, y: 1)
    }

    private func setValue(_ candidate: Double) {
        let rounded = (candidate / step).rounded() * step
        let next = min(max(rounded, range.lowerBound), range.upperBound)
        if next != value { value = next }
    }
}
