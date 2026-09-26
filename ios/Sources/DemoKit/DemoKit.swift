#if os(iOS)
import AVFoundation
import Combine
import Foundation
import SwiftUI
import UIKit

public protocol DemoTargetResolving: AnyObject {
    func frame(forRef ref: String) -> CGRect?
    func frame(forLabel label: String) -> CGRect?
}

public struct DemoEvent: Codable, Sendable {
    public let timestamp: TimeInterval
    public let type: String
    public let text: String?
    public let target: String?
    public let duration: TimeInterval?

    public init(timestamp: TimeInterval, type: String, text: String? = nil, target: String? = nil, duration: TimeInterval? = nil) {
        self.timestamp = timestamp
        self.type = type
        self.text = text
        self.target = target
        self.duration = duration
    }
}

public struct DemoCommand: Sendable {
    public let command: String
    public let title: String?
    public let ref: String?
    public let label: String?
    public let text: String?
    public let ms: Int?

    public init(command: String, title: String? = nil, ref: String? = nil, label: String? = nil, text: String? = nil, ms: Int? = nil) {
        self.command = command
        self.title = title
        self.ref = ref
        self.label = label
        self.text = text
        self.ms = ms
    }
}

@MainActor
public final class DemoRuntime: ObservableObject {
    @Published public var isActive = false
    @Published public var isPaused = false
    @Published public var spotlightFrame: CGRect?
    @Published public var tooltipText: String?
    @Published public var tooltipPosition: CGPoint?
    @Published public var captionText: String?
    @Published public var stepNumber = 0
    @Published public var stepTitle: String?
    @Published public var cursorPosition: CGPoint?
    @Published public var cursorVisible = false

    public private(set) var events: [DemoEvent] = []
    public weak var resolver: DemoTargetResolving?

    private var recordingStart: Date?
    private let synthesizer = AVSpeechSynthesizer()

    public init(resolver: DemoTargetResolving? = nil) {
        self.resolver = resolver
    }

    public func execute(_ command: DemoCommand) async -> [DemoEvent]? {
        switch command.command {
        case "step":
            if let title = command.title { step(title) }
        case "spotlight":
            spotlight(ref: command.ref, label: command.label, text: command.text)
        case "annotate":
            if let text = command.text { annotate(ref: command.ref, label: command.label, text: text) }
        case "caption":
            if let text = command.text { caption(text) }
        case "say":
            if let text = command.text { await say(text) }
        case "cursor":
            await cursorTo(ref: command.ref, label: command.label)
        case "highlight":
            highlight(ref: command.ref, label: command.label)
        case "clear": clear()
        case "pause": pause()
        case "resume": resume()
        case "wait":
            let ms = command.ms ?? 1000
            try? await Task.sleep(for: .milliseconds(ms))
        case "start_recording": startRecording()
        case "stop_recording": return stopRecording()
        default: break
        }
        return nil
    }

    public func step(_ title: String) {
        guard !isPaused else { return }
        stepNumber += 1
        stepTitle = title
        isActive = true
        record(type: "step", text: title)
    }

    public func spotlight(ref: String?, label: String?, text: String?) {
        guard !isPaused, let frame = resolveFrame(ref: ref, label: label) else { return }
        spotlightFrame = frame
        if let text {
            tooltipText = text
            tooltipPosition = CGPoint(x: frame.midX, y: frame.maxY + 8)
        }
        isActive = true
        record(type: "spotlight", text: text, target: ref ?? label)
    }

    public func annotate(ref: String?, label: String?, text: String) {
        guard !isPaused, let frame = resolveFrame(ref: ref, label: label) else { return }
        tooltipText = text
        tooltipPosition = CGPoint(x: frame.midX, y: frame.maxY + 8)
        isActive = true
        record(type: "annotate", text: text, target: ref ?? label)
    }

    public func caption(_ text: String) {
        guard !isPaused else { return }
        captionText = text
        isActive = true
        record(type: "caption", text: text)
    }

    public func say(_ text: String) async {
        guard !isPaused else { return }
        captionText = text
        isActive = true
        record(type: "say", text: text)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.speak(utterance)
        let estimate = max(600, text.count * 45)
        try? await Task.sleep(for: .milliseconds(estimate))
        captionText = nil
    }

    public func cursorTo(ref: String?, label: String?) async {
        guard !isPaused, let frame = resolveFrame(ref: ref, label: label) else { return }
        cursorVisible = true
        cursorPosition = CGPoint(x: frame.midX, y: frame.midY)
        isActive = true
        record(type: "cursor", target: ref ?? label)
        try? await Task.sleep(for: .milliseconds(400))
    }

    public func highlight(ref: String?, label: String?) {
        guard !isPaused, let frame = resolveFrame(ref: ref, label: label) else { return }
        spotlightFrame = frame
        isActive = true
        record(type: "highlight", target: ref ?? label)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            if self.spotlightFrame == frame { self.spotlightFrame = nil }
        }
    }

    public func clear() {
        spotlightFrame = nil
        tooltipText = nil
        tooltipPosition = nil
        captionText = nil
        stepTitle = nil
        stepNumber = 0
        cursorVisible = false
        cursorPosition = nil
        isActive = false
        record(type: "clear")
    }

    public func pause() { isPaused = true; record(type: "pause") }
    public func resume() { isPaused = false; record(type: "resume") }

    public func startRecording() {
        events.removeAll()
        recordingStart = Date()
        record(type: "recording_start")
    }

    public func stopRecording() -> [DemoEvent] {
        record(type: "recording_stop")
        recordingStart = nil
        return events
    }

    private func resolveFrame(ref: String?, label: String?) -> CGRect? {
        if let ref, let frame = resolver?.frame(forRef: ref) { return frame }
        if let label, let frame = resolver?.frame(forLabel: label) { return frame }
        return nil
    }

    private func record(type: String, text: String? = nil, target: String? = nil, duration: TimeInterval? = nil) {
        guard let recordingStart else { return }
        events.append(DemoEvent(timestamp: Date().timeIntervalSince(recordingStart) * 1000, type: type, text: text, target: target, duration: duration))
    }
}

public struct DemoOverlayView: View {
    @ObservedObject private var demo: DemoRuntime

    public init(runtime: DemoRuntime) {
        self.demo = runtime
    }

    public var body: some View {
        ZStack {
            if let frame = demo.spotlightFrame { SpotlightMask(cutout: frame) }
            if let text = demo.tooltipText, let pos = demo.tooltipPosition {
                Text(text)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.85)))
                    .position(pos)
            }
            if let caption = demo.captionText {
                VStack {
                    Spacer()
                    Text(caption)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20).padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(.ultraThinMaterial)
                        .padding(.horizontal, 16).padding(.bottom, 40)
                }
            }
            if let title = demo.stepTitle {
                VStack {
                    HStack(spacing: 8) {
                        Text("\(demo.stepNumber)").font(.caption.bold())
                        Text(title).font(.subheadline.bold())
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(.black.opacity(0.75)))
                    .padding(.top, 60)
                    Spacer()
                }
            }
            if demo.cursorVisible, let pos = demo.cursorPosition {
                Circle().fill(.blue).frame(width: 16, height: 16).position(pos)
            }
        }
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.3), value: demo.spotlightFrame)
        .animation(.easeInOut(duration: 0.3), value: demo.captionText)
    }
}

private struct SpotlightMask: View {
    let cutout: CGRect

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(0.5)))
            context.blendMode = .destinationOut
            context.fill(Path(roundedRect: cutout.insetBy(dx: -4, dy: -4), cornerRadius: 8), with: .color(.white))
        }
        .compositingGroup()
        .ignoresSafeArea()
    }
}
#endif
