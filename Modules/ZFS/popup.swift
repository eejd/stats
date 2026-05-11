//
//  popup.swift
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

internal class Popup: PopupWrapper {
    private var grid: NSGridView? = nil

    // Section heights
    private let dashboardH: CGFloat = 90
    private let chartH: CGFloat = 90 + Constants.Popup.separatorHeight
    private let arcH: CGFloat = (22 * 4) + Constants.Popup.separatorHeight
    private let l2H: CGFloat  = (22 * 3) + Constants.Popup.separatorHeight
    private let ioH: CGFloat  = (22 * 2) + Constants.Popup.separatorHeight

    // ARC widgets
    private var arcSizeField: NSTextField? = nil
    private var arcMaxField: NSTextField? = nil
    private var arcMetaField: NSTextField? = nil
    private var arcHitField: NSTextField? = nil

    // L2ARC widgets
    private var l2SizeField: NSTextField? = nil
    private var l2HitField: NSTextField? = nil

    // IO widgets
    private var ioReadField: NSTextField? = nil
    private var ioWriteField: NSTextField? = nil

    // Pool rows: name → value field (shows "HEALTH  XX% used")
    private var poolRows: [String: ValueField] = [:]
    private var poolSectionView: NSView? = nil

    // Charts
    private var circle: PieChartView? = nil
    private var chart: LineChartView? = nil

    private var showL2: Bool = false
    private var showIO: Bool = false
    private var knownPools: Set<String> = []
    private var initialized: Bool = false

    private var lineChartHistory: Int = 180

    public init(_ module: ModuleType) {
        super.init(module, frame: NSRect(
            x: 0, y: 0,
            width: Constants.Popup.width,
            height: dashboardH + chartH + arcH
        ))
        self.lineChartHistory = Store.shared.int(key: "\(self.title)_lineChartHistory", defaultValue: self.lineChartHistory)

        let g = NSGridView(frame: NSRect(x: 0, y: 0, width: self.frame.width, height: self.frame.height))
        g.rowSpacing = 0
        g.yPlacement = .fill

        g.addRow(with: [self.makeDashboard()])
        g.addRow(with: [self.makeChart()])
        g.addRow(with: [self.makeARCSection()])

        g.row(at: 0).height = dashboardH
        g.row(at: 1).height = chartH
        g.row(at: 2).height = arcH

        self.addSubview(g)
        self.grid = g
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func updateLayer() {
        self.chart?.display()
    }

    // MARK: - Section builders

    private func makeDashboard() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: self.frame.width, height: dashboardH))
        let inner = NSView(frame: NSRect(x: 0, y: 10, width: view.frame.width, height: dashboardH - 20))
        self.circle = PieChartView(
            frame: NSRect(x: (inner.frame.width - inner.frame.height) / 2, y: 0, width: inner.frame.height, height: inner.frame.height),
            segments: [], drawValue: true
        )
        self.circle!.toolTip = localizedString("ARC utilization")
        inner.addSubview(self.circle!)
        view.addSubview(inner)
        return view
    }

    private func makeChart() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: self.frame.width, height: chartH))
        let sep = separatorView(localizedString("ARC hit ratio history"),
                                origin: NSPoint(x: 0, y: chartH - Constants.Popup.separatorHeight),
                                width: self.frame.width)
        let container = NSView(frame: NSRect(x: 0, y: 0, width: self.frame.width, height: sep.frame.origin.y))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.lightGray.withAlphaComponent(0.1).cgColor
        container.layer?.cornerRadius = 3
        self.chart = LineChartView(frame: NSRect(x: 1, y: 0, width: self.frame.width - 2, height: container.frame.height), num: self.lineChartHistory)
        container.addSubview(self.chart!)
        view.addSubview(sep)
        view.addSubview(container)
        return view
    }

    private func makeARCSection() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: self.frame.width, height: arcH))
        let sep = separatorView(localizedString("ARC"),
                                origin: NSPoint(x: 0, y: arcH - Constants.Popup.separatorHeight),
                                width: self.frame.width)
        let stack = NSStackView(frame: NSRect(x: 0, y: 0, width: self.frame.width, height: sep.frame.origin.y))
        stack.orientation = .vertical; stack.spacing = 0
        self.arcSizeField = popupRow(stack, title: "\(localizedString("Size")):", value: "").1 as NSTextField
        self.arcMaxField  = popupRow(stack, title: "\(localizedString("Max")):", value: "").1 as NSTextField
        self.arcMetaField = popupRow(stack, title: "\(localizedString("Metadata")):", value: "").1 as NSTextField
        self.arcHitField  = popupRow(stack, title: "\(localizedString("Hit ratio")):", value: "").1 as NSTextField
        view.addSubview(sep); view.addSubview(stack)
        return view
    }

    private func makeL2Section() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: self.frame.width, height: l2H))
        let sep = separatorView(localizedString("L2ARC"),
                                origin: NSPoint(x: 0, y: l2H - Constants.Popup.separatorHeight),
                                width: self.frame.width)
        let stack = NSStackView(frame: NSRect(x: 0, y: 0, width: self.frame.width, height: sep.frame.origin.y))
        stack.orientation = .vertical; stack.spacing = 0
        self.l2SizeField = popupRow(stack, title: "\(localizedString("Size")):", value: "").1
        self.l2HitField  = popupRow(stack, title: "\(localizedString("Hit ratio")):", value: "").1
        view.addSubview(sep); view.addSubview(stack)
        return view
    }

    private func makeIOSection() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: self.frame.width, height: ioH))
        let sep = separatorView(localizedString("IO"),
                                origin: NSPoint(x: 0, y: ioH - Constants.Popup.separatorHeight),
                                width: self.frame.width)
        let stack = NSStackView(frame: NSRect(x: 0, y: 0, width: self.frame.width, height: sep.frame.origin.y))
        stack.orientation = .vertical; stack.spacing = 0
        self.ioReadField  = popupRow(stack, title: "\(localizedString("Read")):", value: "").1
        self.ioWriteField = popupRow(stack, title: "\(localizedString("Write")):", value: "").1
        view.addSubview(sep); view.addSubview(stack)
        return view
    }

    private func makePoolsSection(pools: [ZFS_Pool]) -> NSView {
        let rowH: CGFloat = 22
        let h: CGFloat = CGFloat(pools.count) * rowH + Constants.Popup.separatorHeight
        let view = NSView(frame: NSRect(x: 0, y: 0, width: self.frame.width, height: h))
        let sep = separatorView(localizedString("Pools"),
                                origin: NSPoint(x: 0, y: h - Constants.Popup.separatorHeight),
                                width: self.frame.width)
        let stack = NSStackView(frame: NSRect(x: 0, y: 0, width: self.frame.width, height: sep.frame.origin.y))
        stack.orientation = .vertical; stack.spacing = 0

        for pool in pools {
            let valueField = popupRow(stack, title: "\(pool.name):", value: "").1
            poolRows[pool.name] = valueField
        }
        view.addSubview(sep); view.addSubview(stack)
        self.poolSectionView = view
        return view
    }

    // MARK: - Data

    public func loadCallback(_ value: ZFS_Stats) {
        DispatchQueue.main.async {
            // Lazily add L2ARC section
            if value.l2Available && !self.showL2 {
                self.showL2 = true
                self.appendSection(self.makeL2Section(), height: self.l2H)
            }

            // Lazily add IO section when pools are available
            if !value.pools.isEmpty && !self.showIO {
                self.showIO = true
                self.appendSection(self.makeIOSection(), height: self.ioH)
            }

            // Lazily add/update pool rows
            let newPools = Set(value.pools.map { $0.name })
            if newPools != self.knownPools && !value.pools.isEmpty {
                self.knownPools = newPools
                self.poolRows = [:]
                let poolsView = self.makePoolsSection(pools: value.pools)
                let h: CGFloat = CGFloat(value.pools.count) * 22 + Constants.Popup.separatorHeight
                self.appendSection(poolsView, height: h)
            }

            guard (self.window?.isVisible ?? false) || !self.initialized else {
                self.chart?.addValue(value.arcHitRatio)
                return
            }

            // ARC
            self.arcSizeField?.stringValue = Units(bytes: value.arcSize).getReadableMemory(style: .memory)
            self.arcMaxField?.stringValue  = Units(bytes: value.arcMax).getReadableMemory(style: .memory)
            self.arcMetaField?.stringValue = Units(bytes: value.arcMetaUsed).getReadableMemory(style: .memory)
            self.arcHitField?.stringValue  = "\(Int(value.arcHitRatio * 100))%"
            self.circle?.toolTip = "\(localizedString("ARC utilization")): \(Int(value.arcUtilization * 100))%"
            self.circle?.setValue(value.arcUtilization)
            self.circle?.setSegments([ColorValue(value.arcUtilization)])

            // L2ARC
            if value.l2Available {
                self.l2SizeField?.stringValue = Units(bytes: value.l2Size).getReadableMemory(style: .memory)
                self.l2HitField?.stringValue  = "\(Int(value.l2HitRatio * 100))%"
            }

            // IO
            if !value.pools.isEmpty {
                self.ioReadField?.stringValue  = Units(bytes: value.totalReadBW).getReadableSpeed()
                self.ioWriteField?.stringValue = Units(bytes: value.totalWriteBW).getReadableSpeed()
            }

            // Per-pool rows
            for pool in value.pools {
                if let field = self.poolRows[pool.name] {
                    let freeStr = Units(bytes: pool.free).getReadableMemory(style: .memory)
                    field.stringValue = "\(pool.health)  \(freeStr) free  (\(Int(pool.capacity * 100))% used)"
                    field.textColor = pool.isHealthy ? .secondaryLabelColor : .systemRed
                }
            }

            self.chart?.addValue(value.arcHitRatio)
            self.initialized = true
        }
    }

    // MARK: - Layout helpers

    private func appendSection(_ view: NSView, height: CGFloat) {
        let newH = self.frame.height + height
        self.setFrameSize(NSSize(width: self.frame.width, height: newH))
        self.grid?.setFrameSize(NSSize(width: self.frame.width, height: newH))
        self.grid?.addRow(with: [view])
        self.grid?.row(at: (self.grid?.numberOfRows ?? 1) - 1).height = height
        self.sizeCallback?(self.frame.size)
    }

    public override func settings() -> NSView? {
        let view = SettingsContainerView()
        view.addArrangedSubview(PreferencesSection([
            PreferencesRow(localizedString("Keyboard shortcut"), component: KeyboardShartcutView(
                callback: self.setKeyboardShortcut, value: self.keyboardShortcut
            ))
        ]))
        view.addArrangedSubview(PreferencesSection([
            PreferencesRow(localizedString("Chart history"), component: selectView(
                action: #selector(self.toggleLineChartHistory),
                items: LineChartHistory,
                selected: "\(self.lineChartHistory)"
            ))
        ]))
        return view
    }

    @objc private func toggleLineChartHistory(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String, let value = Int(key) else { return }
        self.lineChartHistory = value
        Store.shared.set(key: "\(self.title)_lineChartHistory", value: value)
        self.chart?.reinit(self.lineChartHistory)
    }
}
