//
//  notifications.swift
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

class Notifications: NotificationsWrapper {
    private let healthID: String = "poolHealth"

    private var healthState: Bool = false
    private var prevHealth: [String: String] = [:]

    public init(_ module: ModuleType) {
        super.init(module, [self.healthID])

        self.healthState = Store.shared.bool(
            key: "\(self.module)_notifications_health_state",
            defaultValue: self.healthState
        )

        self.addArrangedSubview(PreferencesSection([
            PreferencesRow(localizedString("Pool health error"), component: switchView(
                action: #selector(self.toggleHealth),
                state: self.healthState
            ))
        ]))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func loadCallback(_ value: ZFS_Stats) {
        guard self.healthState else { return }

        for pool in value.pools {
            let prev = prevHealth[pool.name]
            if prev != nil && prev == "ONLINE" && pool.health != "ONLINE" {
                let title = localizedString("ZFS pool health alert")
                let subtitle = "\(pool.name): \(pool.health)"
                // Map to 0.0 (degraded) vs threshold 0.5 so checkDouble fires once
                self.checkDouble(
                    id: "\(self.healthID)_\(pool.name)",
                    value: 0.0,
                    threshold: 0.5,
                    title: title,
                    subtitle: subtitle,
                    less: true
                )
            } else if pool.health == "ONLINE", let prev = prevHealth[pool.name], prev != "ONLINE" {
                // Pool recovered — reset the debounce by registering a healthy value
                self.checkDouble(
                    id: "\(self.healthID)_\(pool.name)",
                    value: 1.0,
                    threshold: 0.5,
                    title: "",
                    subtitle: "",
                    less: true
                )
            }
            prevHealth[pool.name] = pool.health
        }
    }

    @objc func toggleHealth(_ sender: NSControl) {
        self.healthState = controlState(sender)
        Store.shared.set(key: "\(self.module)_notifications_health_state", value: self.healthState)
    }
}
