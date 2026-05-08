//
//  SwapMemory.swift
//  Kit
//
//  Created by eejd on 08/05/2026.
//  Using Swift 5.0.
//  Running on macOS 10.15.
//
//  Copyright © 2026 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa

public class SwapMemoryWidget: WidgetWrapper {
    private var orderReversedState: Bool = false
    private var value: (String, String) = ("0", "0")
    private var percentage: Double = 0
    private var symbolsState: Bool = true
    private var colorState: SColor = .monochrome

    private let width: CGFloat = 50

    public init(title: String, config: NSDictionary?, preview: Bool = false) {
        if let config {
            var configuration = config
            if preview, let previewConfig = config["Preview"] as? NSDictionary {
                configuration = previewConfig
                if let raw = configuration["Value"] as? String {
                    let parts = raw.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
                    if parts.count == 2 {
                        self.value = (parts[0], parts[1])
                    }
                }
            }
        }

        super.init(.swapMemory, title: title, frame: CGRect(
            x: Constants.Widget.margin.x,
            y: Constants.Widget.margin.y,
            width: self.width + (Constants.Widget.margin.x * 2),
            height: Constants.Widget.height - (2 * Constants.Widget.margin.y)
        ))

        self.canDrawConcurrently = true

        if !preview {
            self.orderReversedState = Store.shared.bool(key: "\(self.title)_\(self.type.rawValue)_orderReversed", defaultValue: self.orderReversedState)
            self.symbolsState = Store.shared.bool(key: "\(self.title)_\(self.type.rawValue)_symbols", defaultValue: self.symbolsState)
            self.colorState = SColor.fromString(Store.shared.string(key: "\(self.title)_\(self.type.rawValue)_color", defaultValue: self.colorState.key))
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let letterWidth: CGFloat = 8
        let rowHeight: CGFloat = self.frame.height / 2
        var width: CGFloat = self.width
        var x: CGFloat = 0

        // Top row = used, bottom row = free (reversed by orderReversedState)
        let usedY: CGFloat = self.orderReversedState ? 1 : rowHeight + 1
        let freeY: CGFloat = self.orderReversedState ? rowHeight + 1 : 1

        let style = NSMutableParagraphStyle()
        style.alignment = .right
        var attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .light),
            .foregroundColor: NSColor.textColor,
            .paragraphStyle: style
        ]

        if self.symbolsState {
            var rect = CGRect(x: Constants.Widget.margin.x, y: usedY, width: letterWidth, height: rowHeight)
            NSAttributedString(string: "U:", attributes: attributes).draw(with: rect)

            rect = CGRect(x: Constants.Widget.margin.x, y: freeY, width: letterWidth, height: rowHeight)
            NSAttributedString(string: "F:", attributes: attributes).draw(with: rect)

            x = letterWidth + Constants.Widget.spacing * 2
            width += x
        }

        let usedColor: NSColor
        let freeColor: NSColor
        switch self.colorState {
        case .systemAccent:
            usedColor = .controlAccentColor
            freeColor = .controlAccentColor
        case .utilization:
            usedColor = self.percentage.usageColor()
            freeColor = (1 - self.percentage).usageColor()
        case .monochrome:
            usedColor = isDarkMode ? .white : .black
            freeColor = isDarkMode ? .white : .black
        default:
            let c = self.colorState.additional as? NSColor ?? .controlAccentColor
            usedColor = c
            freeColor = c
        }

        attributes[.foregroundColor] = usedColor
        NSAttributedString(string: self.value.0, attributes: attributes)
            .draw(with: CGRect(x: x, y: usedY, width: width - x, height: rowHeight))

        attributes[.foregroundColor] = freeColor
        NSAttributedString(string: self.value.1, attributes: attributes)
            .draw(with: CGRect(x: x, y: freeY, width: width - x, height: rowHeight))

        self.setWidth(width + (Constants.Widget.margin.x * 2))
    }

    public func setValue(used: String, free: String, usedPercentage: Double) {
        self.value = (used, free)
        self.percentage = usedPercentage
        DispatchQueue.main.async { self.display() }
    }

    public override func settings() -> NSView {
        let view = SettingsContainerView()

        view.addArrangedSubview(PreferencesSection([
            PreferencesRow(localizedString("Color"), component: selectView(
                action: #selector(self.toggleColor),
                items: SColor.allCases.filter({ $0 != .cluster && $0 != .pressure }),
                selected: self.colorState.key
            )),
            PreferencesRow(localizedString("Show symbols"), component: switchView(
                action: #selector(self.toggleSymbols),
                state: self.symbolsState
            )),
            PreferencesRow(localizedString("Reverse order"), component: switchView(
                action: #selector(self.toggleOrder),
                state: self.orderReversedState
            ))
        ]))

        return view
    }

    @objc private func toggleOrder(_ sender: NSControl) {
        self.orderReversedState = controlState(sender)
        Store.shared.set(key: "\(self.title)_\(self.type.rawValue)_orderReversed", value: self.orderReversedState)
        self.display()
    }

    @objc private func toggleSymbols(_ sender: NSControl) {
        self.symbolsState = controlState(sender)
        Store.shared.set(key: "\(self.title)_\(self.type.rawValue)_symbols", value: self.symbolsState)
        self.display()
    }

    @objc private func toggleColor(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        if let newColor = SColor.allCases.first(where: { $0.key == key }) {
            self.colorState = newColor
        }
        Store.shared.set(key: "\(self.title)_\(self.type.rawValue)_color", value: key)
        self.display()
    }
}
