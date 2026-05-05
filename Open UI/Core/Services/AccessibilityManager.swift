import SwiftUI

/// Manages user accessibility preferences for font scaling and UI sizing.
///
/// Three independent scaling axes let users fine-tune their experience:
/// - **Content text**: Chat messages, markdown content, notes
/// - **List text**: Conversation titles, folder names, settings items
/// - **UI scale**: Buttons, icons, spacing, touch targets
///
/// All scales default to 1.0 and persist via UserDefaults.
@Observable
final class AccessibilityManager {

    // MARK: - Presets

    /// Quick presets that configure all three axes at once.
    enum Preset: String, CaseIterable, Identifiable {
        case compact = "compact"
        case standard = "standard"
        case comfortable = "comfortable"
        case large = "large"
        case extraLarge = "extraLarge"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .compact:     return "Compact"
            case .standard:    return "Standard"
            case .comfortable: return "Comfortable"
            case .large:       return "Large"
            case .extraLarge:  return "Extra Large"
            }
        }

        var icon: String {
            switch self {
            case .compact:     return "textformat.size.smaller"
            case .standard:    return "textformat.size"
            case .comfortable: return "textformat.size.larger"
            case .large:       return "textformat.size.larger"
            case .extraLarge:  return "accessibility"
            }
        }

        var contentScale: CGFloat {
            switch self {
            case .compact:     return 0.9
            case .standard:    return 1.0
            case .comfortable: return 1.1
            case .large:       return 1.25
            case .extraLarge:  return 1.4
            }
        }

        var listScale: CGFloat {
            switch self {
            case .compact:     return 0.9
            case .standard:    return 1.0
            case .comfortable: return 1.1
            case .large:       return 1.2
            case .extraLarge:  return 1.3
            }
        }

        var uiScale: CGFloat {
            switch self {
            case .compact:     return 0.9
            case .standard:    return 1.0
            case .comfortable: return 1.05
            case .large:       return 1.15
            case .extraLarge:  return 1.25
            }
        }

        var inputScale: CGFloat {
            switch self {
            case .compact:     return 0.9
            case .standard:    return 1.0
            case .comfortable: return 1.1
            case .large:       return 1.2
            case .extraLarge:  return 1.35
            }
        }
    }

    // MARK: - Font Context

    /// Semantic context for font scaling — determines which multiplier applies.
    enum FontContext {
        /// Chat messages, markdown content, notes body
        case content
        /// Conversation titles, folder names, list items
        case list
        /// Buttons, labels, badges, captions, system chrome
        case ui
        /// Input box composer text (chat and channel)
        case input
    }

    // MARK: - State

    /// Scale for chat message content and markdown (0.8–1.5).
    var contentTextScale: CGFloat {
        didSet { save() }
    }

    /// Scale for conversation titles, folder names, list items (0.8–1.5).
    var listTextScale: CGFloat {
        didSet { save() }
    }

    /// Scale for buttons, icons, spacing, touch targets (0.85–1.3).
    var uiScale: CGFloat {
        didSet { save() }
    }

    /// Scale for the message input composer box (0.8–1.5).
    var inputTextScale: CGFloat {
        didSet { save() }
    }

    // MARK: - Computed Helpers

    /// Returns the scale factor for the given font context.
    func scale(for context: FontContext) -> CGFloat {
        switch context {
        case .content: return contentTextScale
        case .list:    return listTextScale
        case .ui:      return uiScale
        case .input:   return inputTextScale
        }
    }

    /// Whether any scale has been changed from the default.
    var isCustomized: Bool {
        abs(contentTextScale - 1.0) > 0.01
            || abs(listTextScale - 1.0) > 0.01
            || abs(uiScale - 1.0) > 0.01
            || abs(inputTextScale - 1.0) > 0.01
    }

    /// The current preset that matches the scales, or nil if custom.
    var matchingPreset: Preset? {
        Preset.allCases.first { preset in
            abs(contentTextScale - preset.contentScale) < 0.01
                && abs(listTextScale - preset.listScale) < 0.01
                && abs(uiScale - preset.uiScale) < 0.01
                && abs(inputTextScale - preset.inputScale) < 0.01
        }
    }

    // MARK: - Actions

    /// Applies a preset, setting all scales at once.
    func apply(preset: Preset) {
        contentTextScale = preset.contentScale
        listTextScale = preset.listScale
        uiScale = preset.uiScale
        inputTextScale = preset.inputScale
    }

    /// Resets all scales to defaults (1.0).
    func resetToDefaults() {
        contentTextScale = 1.0
        listTextScale = 1.0
        uiScale = 1.0
        inputTextScale = 1.0
    }

    // MARK: - Persistence

    private static let contentScaleKey = "openui.accessibility.contentTextScale"
    private static let listScaleKey = "openui.accessibility.listTextScale"
    private static let uiScaleKey = "openui.accessibility.uiScale"
    private static let inputScaleKey = "openui.accessibility.inputTextScale"

    init() {
        let storedContent = UserDefaults.standard.double(forKey: Self.contentScaleKey)
        self.contentTextScale = storedContent > 0 ? CGFloat(storedContent) : 1.0

        let storedList = UserDefaults.standard.double(forKey: Self.listScaleKey)
        self.listTextScale = storedList > 0 ? CGFloat(storedList) : 1.0

        let storedUI = UserDefaults.standard.double(forKey: Self.uiScaleKey)
        self.uiScale = storedUI > 0 ? CGFloat(storedUI) : 1.0

        let storedInput = UserDefaults.standard.double(forKey: Self.inputScaleKey)
        self.inputTextScale = storedInput > 0 ? CGFloat(storedInput) : 1.0
    }

    private func save() {
        UserDefaults.standard.set(Double(contentTextScale), forKey: Self.contentScaleKey)
        UserDefaults.standard.set(Double(listTextScale), forKey: Self.listScaleKey)
        UserDefaults.standard.set(Double(uiScale), forKey: Self.uiScaleKey)
        UserDefaults.standard.set(Double(inputTextScale), forKey: Self.inputScaleKey)
    }
}

// MARK: - Clamping Ranges

extension AccessibilityManager {
    /// Clamps content text scale to valid range.
    static let contentScaleRange: ClosedRange<CGFloat> = 0.8...1.5
    /// Clamps list text scale to valid range.
    static let listScaleRange: ClosedRange<CGFloat> = 0.8...1.5
    /// Clamps UI scale to valid range.
    static let uiScaleRange: ClosedRange<CGFloat> = 0.85...1.3
    /// Clamps input composer text scale to valid range.
    static let inputScaleRange: ClosedRange<CGFloat> = 0.8...1.5
}
