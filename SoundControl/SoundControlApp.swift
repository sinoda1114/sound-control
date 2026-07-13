import AppKit
import SwiftUI

@main
struct SoundControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        statusBarController = StatusBarController()
    }
}

@MainActor
final class StatusBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private let viewModel = SoundControlViewModel()

    override init() {
        super.init()

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 260, height: 440)
        popover.contentViewController = NSHostingController(rootView: SoundControlMenu(viewModel: viewModel))

        if let button = statusItem.button {
            button.image = makeMenuBarImage()
            button.image?.isTemplate = true
            button.toolTip = "Sound Control"
            button.setAccessibilityLabel("Sound Control")
            button.target = self
            button.action = #selector(togglePopover)
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else {
            return
        }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            viewModel.refresh()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func makeMenuBarImage() -> NSImage? {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.lockFocus()
        defer {
            image.unlockFocus()
        }

        NSColor.labelColor.setFill()
        let speaker = NSBezierPath()
        speaker.move(to: NSPoint(x: 2.5, y: 7))
        speaker.line(to: NSPoint(x: 6.5, y: 7))
        speaker.line(to: NSPoint(x: 10.5, y: 3.5))
        speaker.line(to: NSPoint(x: 10.5, y: 14.5))
        speaker.line(to: NSPoint(x: 6.5, y: 11))
        speaker.line(to: NSPoint(x: 2.5, y: 11))
        speaker.close()
        speaker.fill()

        NSColor.labelColor.setStroke()
        for (radius, lineWidth) in [(3.0, 1.6), (5.5, 1.4)] {
            let path = NSBezierPath()
            path.appendArc(
                withCenter: NSPoint(x: 11, y: 9),
                radius: radius,
                startAngle: -45,
                endAngle: 45,
                clockwise: false
            )
            path.lineWidth = lineWidth
            path.lineCapStyle = .round
            path.stroke()
        }

        return image
    }
}

struct SoundControlMenu: View {
    @ObservedObject var viewModel: SoundControlViewModel
    private let selectedDeviceColor = Color(red: 0.0, green: 0.42, blue: 1.0)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sound Control")
                .font(.headline)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text(viewModel.volumeText)

                Slider(
                    value: Binding(
                        get: { viewModel.volume },
                        set: { viewModel.setVolume($0) }
                    ),
                    in: 0...1
                )
                .disabled(!viewModel.canSetCurrentVolume)
                .overlay {
                    ScrollWheelCaptureView { deltaY in
                        viewModel.adjustVolumeByScroll(deltaY: deltaY)
                    }
                    .disabled(!viewModel.canSetCurrentVolume)
                }

                if !viewModel.canSetCurrentVolume {
                    Text("この出力デバイスでは音量変更できません")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Toggle(
                "ミュート",
                isOn: Binding(
                    get: { viewModel.isMuted },
                    set: { viewModel.setMuted($0) }
                )
            )
            .disabled(!viewModel.canSetCurrentMute)

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Divider()

            Text("出力デバイス")
                .font(.headline)

            if viewModel.outputDevices.isEmpty {
                Text("出力デバイス一覧を取得できませんでした")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(viewModel.outputDevices) { device in
                        Button {
                            viewModel.selectDevice(device)
                        } label: {
                            HStack {
                                Text(device.isDefaultOutput ? "\(device.name) ✓" : device.name)
                                    .foregroundStyle(device.isDefaultOutput ? selectedDeviceColor : Color.primary)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 3)
                    }
                }
            }

            Divider()

            Button("デバイス一覧を更新") {
                viewModel.refresh()
            }

            Button("サウンド設定を開く") {
                viewModel.openSoundSettings()
            }

            Button("\(viewModel.isLoginItemEnabled ? "✓ " : "")起動時に自動起動") {
                viewModel.toggleLoginItem()
            }

            Button("終了") {
                viewModel.quit()
            }
        }
        .padding(14)
        .frame(width: 260)
    }
}

struct ScrollWheelCaptureView: NSViewRepresentable {
    let onScroll: (CGFloat) -> Void

    func makeNSView(context: Context) -> ScrollWheelCaptureNSView {
        let view = ScrollWheelCaptureNSView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: ScrollWheelCaptureNSView, context: Context) {
        nsView.onScroll = onScroll
    }
}

final class ScrollWheelCaptureNSView: NSView {
    var onScroll: ((CGFloat) -> Void)?
    private var isHovering = false
    private var eventMonitor: Any?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        for trackingArea in trackingAreas {
            removeTrackingArea(trackingArea)
        }

        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited],
                owner: self,
                userInfo: nil
            )
        )
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window == nil {
            if let eventMonitor {
                NSEvent.removeMonitor(eventMonitor)
            }
            eventMonitor = nil
            isHovering = false
            return
        }

        if eventMonitor == nil {
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, self.isHovering else {
                    return event
                }

                self.onScroll?(event.scrollingDeltaY)
                return nil
            }
        }
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
    }

    deinit {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
    }
}
