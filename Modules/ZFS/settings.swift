//
//  settings.swift
//  ZFS
//
//  Created by Eric DeWitt on 09/05/2026.
//  Using Swift 5.0.
//  Running on macOS 11.0.
//
//  Copyright © 2026 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa
import Kit

internal class Settings: NSStackView, Settings_v {
    private var updateIntervalValue: Int = 5
    private let title: String

    public var callback: (() -> Void) = {}
    public var setInterval: ((_ value: Int) -> Void) = { _ in }

    public init(_ module: ModuleType) {
        self.title = module.stringValue
        self.updateIntervalValue = Store.shared.int(key: "\(self.title)_updateInterval", defaultValue: self.updateIntervalValue)

        super.init(frame: NSRect.zero)
        self.orientation = .vertical
        self.distribution = .gravityAreas
        self.spacing = Constants.Settings.margin
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func load(widgets: [widget_t]) {
        self.subviews.forEach { $0.removeFromSuperview() }

        self.addArrangedSubview(PreferencesSection([
            PreferencesRow(localizedString("Update interval"), component: selectView(
                action: #selector(self.changeUpdateInterval),
                items: ReaderUpdateIntervals,
                selected: "\(self.updateIntervalValue)"
            ))
        ]))
    }

    @objc private func changeUpdateInterval(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String, let value = Int(key) else { return }
        self.updateIntervalValue = value
        Store.shared.set(key: "\(self.title)_updateInterval", value: value)
        self.setInterval(value)
    }
}
