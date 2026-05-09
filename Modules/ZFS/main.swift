//
//  main.swift
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

public struct ZFS_Pool: Codable {
    var name: String = ""
    var health: String = "UNKNOWN"
    var size: Int64 = 0
    var allocated: Int64 = 0
    var free: Int64 = 0
    var capacity: Double = 0         // 0–1
    var compressRatio: Double = 1.0
    var readBandwidth: Int64 = 0     // bytes/sec
    var writeBandwidth: Int64 = 0    // bytes/sec

    public var isHealthy: Bool { health == "ONLINE" }
}

public struct ZFS_Stats: Codable {
    var arcSize: Int64 = 0
    var arcMax: Int64 = 0
    var arcMetaUsed: Int64 = 0
    var arcHits: Int64 = 0
    var arcMisses: Int64 = 0
    var l2Size: Int64 = 0
    var l2Hits: Int64 = 0
    var l2Misses: Int64 = 0
    var arcHitRatio: Double = 0
    var l2HitRatio: Double = 0

    var pools: [ZFS_Pool] = []

    public var arcUtilization: Double {
        guard arcMax > 0 else { return 0 }
        return min(1.0, Double(arcSize) / Double(arcMax))
    }
    public var l2Available: Bool { l2Size > 0 }

    public var poolsAllOnline: Bool { pools.isEmpty || pools.allSatisfy { $0.isHealthy } }
    public var worstHealth: String {
        guard !pools.isEmpty else { return "UNKNOWN" }
        return pools.first(where: { !$0.isHealthy })?.health ?? "ONLINE"
    }
    public var totalSize: Int64  { pools.reduce(0) { $0 + $1.size } }
    public var totalFree: Int64  { pools.reduce(0) { $0 + $1.free } }
    public var freeRatio: Double {
        let s = totalSize; return s > 0 ? Double(totalFree) / Double(s) : 0
    }
    public var totalReadBW:  Int64 { pools.reduce(0) { $0 + $1.readBandwidth } }
    public var totalWriteBW: Int64 { pools.reduce(0) { $0 + $1.writeBandwidth } }
}

public class ZFS: Module {
    private let popupView: Popup
    private let settingsView: Settings
    private let portalView: Portal
    private let notificationsView: Notifications
    private let previewView: Preview

    private var usageReader: UsageReader? = nil

    public init() {
        self.settingsView = Settings(.ZFS)
        self.popupView = Popup(.ZFS)
        self.portalView = Portal(.ZFS)
        self.notificationsView = Notifications(.ZFS)
        self.previewView = Preview(.ZFS)

        super.init(
            moduleType: .ZFS,
            popup: self.popupView,
            settings: self.settingsView,
            portal: self.portalView,
            notifications: self.notificationsView,
            preview: self.previewView
        )
        guard self.available else { return }

        self.settingsView.setInterval = { [weak self] value in
            self?.usageReader?.setInterval(value)
        }

        self.usageReader = UsageReader(.ZFS) { [weak self] value in
            self?.loadCallback(value)
        }

        self.setReaders([self.usageReader])
    }

    public override func isAvailable() -> Bool {
        var size: size_t = MemoryLayout<UInt64>.size
        var value: UInt64 = 0
        return sysctlbyname("kstat.zfs.misc.arcstats.size", &value, &size, nil, 0) == 0
    }

    private func loadCallback(_ raw: ZFS_Stats?) {
        guard let value = raw, self.enabled else { return }

        self.popupView.loadCallback(value)
        self.portalView.callback(value)
        self.previewView.loadCallback(value)
        self.notificationsView.loadCallback(value)

        self.menuBar.widgets.filter{ $0.isActive }.forEach { (w: SWidget) in
            switch w.item {
            case let widget as Mini:
                switch w.type {
                case .zfsL2ARC:
                    widget.setValue(value.l2HitRatio)
                case .zfsFree:
                    widget.setValue(value.freeRatio)
                default:
                    widget.setValue(value.arcHitRatio)
                }
            case let widget as LineChart:
                widget.setValue(value.arcHitRatio)
            case let widget as BarChart:
                switch w.type {
                case .zfsFreeBar:
                    widget.setValue([[ColorValue(1.0 - value.freeRatio)]])
                    widget.setColorZones((0.8, 0.95))
                default:
                    widget.setValue([[ColorValue(value.arcUtilization)]])
                    widget.setColorZones((0.8, 0.95))
                }
            case let widget as ZFSHealthWidget:
                widget.setValue(health: value.worstHealth)
            case let widget as SpeedWidget:
                widget.setValue(input: value.totalReadBW, output: value.totalWriteBW)
            default: break
            }
        }
    }
}
