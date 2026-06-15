import UIKit
import WebKit

// Generic native haptic executor, fully driven from the browser. The web layer
// (lib/haptics.ts) owns the entire feel — it posts a structured spec to the
// `haptic` WKScriptMessage handler describing exactly what to play, and this
// runs it. Nothing here is hardcoded to a named "kind": add or retune haptics
// from JS without touching native, as long as the generator type already
// exists below.
//
// Spec shape (JSON object posted from JS):
//   single event:
//     { "type": "selection" }
//     { "type": "impact", "style": "light|medium|heavy|soft|rigid", "intensity": 0.0–1.0 }
//     { "type": "notification", "notification": "success|warning|error" }
//   sequence (events interleaved with millisecond delays):
//     { "sequence": [ {event}, { "delay": 120 }, {event}, … ] }
//
// Mirrors the existing JS→native bridges (print / push / iap): the handler is
// registered in WebView.swift and dispatched from the userContentController
// switch in ViewController.swift.

final class HapticManager {
    static let shared = HapticManager()

    // Generators are kept alive and re-`prepare()`d after each fire so the
    // Taptic Engine stays warm and the tap lands with the gesture — important
    // for the progress-bar scrubber, which fires on every segment crossed.
    private let selection = UISelectionFeedbackGenerator()
    private let notification = UINotificationFeedbackGenerator()
    // One impact generator per style, created on demand and cached.
    private var impactGenerators: [String: UIImpactFeedbackGenerator] = [:]

    private init() {}

    // MARK: - Mapping helpers

    private static func impactStyle(
        _ name: String
    ) -> UIImpactFeedbackGenerator.FeedbackStyle {
        switch name {
        case "light": return .light
        case "heavy": return .heavy
        case "soft": return .soft
        case "rigid": return .rigid
        default: return .medium
        }
    }

    private static func notificationType(
        _ name: String
    ) -> UINotificationFeedbackGenerator.FeedbackType {
        switch name {
        case "warning": return .warning
        case "error": return .error
        default: return .success
        }
    }

    private func impactGenerator(for style: String) -> UIImpactFeedbackGenerator {
        if let existing = impactGenerators[style] {
            return existing
        }
        let generator = UIImpactFeedbackGenerator(style: Self.impactStyle(style))
        impactGenerators[style] = generator
        return generator
    }

    // MARK: - Execution

    /// Play one event dictionary, e.g. {type:"impact", style:"light", intensity:0.8}.
    private func playEvent(_ event: [String: Any]) {
        switch event["type"] as? String ?? "selection" {
        case "impact":
            let style = event["style"] as? String ?? "medium"
            let generator = impactGenerator(for: style)
            if let intensity = (event["intensity"] as? NSNumber)?.doubleValue {
                let clamped = max(0.0, min(1.0, intensity))
                generator.impactOccurred(intensity: CGFloat(clamped))
            } else {
                generator.impactOccurred()
            }
            generator.prepare()
        case "notification":
            let type = event["notification"] as? String ?? "success"
            notification.notificationOccurred(Self.notificationType(type))
            notification.prepare()
        case "selection":
            selection.selectionChanged()
            selection.prepare()
        default:
            break
        }
    }

    /// Play a full spec: a single event, or {sequence: [event | {delay: ms} …]}.
    /// Must be called on the main thread (feedback generators require it).
    func play(_ spec: [String: Any]) {
        if let sequence = spec["sequence"] as? [[String: Any]] {
            playSequence(sequence, index: 0)
        } else {
            playEvent(spec)
        }
    }

    private func playSequence(_ steps: [[String: Any]], index: Int) {
        guard index < steps.count else { return }
        let step = steps[index]
        if let delay = (step["delay"] as? NSNumber)?.doubleValue {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay / 1000.0) {
                [weak self] in
                self?.playSequence(steps, index: index + 1)
            }
        } else {
            playEvent(step)
            playSequence(steps, index: index + 1)
        }
    }
}

func handleHapticFeedback(message: WKScriptMessage) {
    // The body is the spec posted from lib/haptics.ts. WKWebView bridges a JS
    // object to an NSDictionary; also accept a JSON string for resilience.
    var spec: [String: Any]?
    if let dict = message.body as? [String: Any] {
        spec = dict
    } else if let string = message.body as? String,
              let data = string.data(using: .utf8) {
        spec = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
    guard let spec else { return }
    DispatchQueue.main.async {
        HapticManager.shared.play(spec)
    }
}
