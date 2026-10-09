// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
// SPDX-License-Identifier: MIT

import AppKit
import ZenTouchCore

final class GestureCard: NSView {
    let feature: GestureFeature
    let preview: GesturePreviewView
    let toggle = NSSwitch()
    var onChange: ((GestureFeature, Bool) -> Void)?

    init(feature: GestureFeature) {
        self.feature = feature
        preview = GesturePreviewView(feature: feature)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.borderWidth = 1
        updateColors()
        let title = NSTextField(labelWithString: feature.title)
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        toggle.target = self
        toggle.action = #selector(changed)
        toggle.setAccessibilityLabel(feature.title)
        let spacer = NSView()
        spacer.heightAnchor.constraint(equalToConstant: 1).isActive = true
        let heading = NSStackView(views: [title, spacer, toggle])
        heading.alignment = .centerY
        heading.distribution = .fill
        let note = NSTextField(wrappingLabelWithString: feature.explanation)
        note.font = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [heading, preview, note])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            heading.widthAnchor.constraint(equalTo: stack.widthAnchor),
            heading.heightAnchor.constraint(equalToConstant: 24),
            preview.widthAnchor.constraint(equalTo: stack.widthAnchor),
            preview.heightAnchor.constraint(equalToConstant: 70),
            note.widthAnchor.constraint(equalTo: stack.widthAnchor),
            note.heightAnchor.constraint(equalToConstant: 28),
            heightAnchor.constraint(equalToConstant: 156),
        ])
    }
    required init?(coder: NSCoder) { nil }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }
    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor
        }
    }
    func update(enabled: Bool, available: Bool) {
        toggle.state = enabled ? .on : .off
        toggle.isEnabled = available
        preview.enabled = enabled && available
    }
    @objc private func changed() { onChange?(feature, toggle.state == .on) }
}
