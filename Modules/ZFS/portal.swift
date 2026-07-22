//
//  portal.swift
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

public class Portal: PortalWrapper {
    private var circle: PieChartView? = nil
    private var arcSizeField: NSTextField? = nil
    private var arcHitRatioField: NSTextField? = nil
    private var l2Field: NSTextField? = nil
    private var initialized: Bool = false

    public override func load() {
        let view = NSStackView()
        view.orientation = .horizontal
        view.distribution = .fillEqually
        view.spacing = Constants.Popup.spacing * 2
        view.edgeInsets = NSEdgeInsets(
            top: 0,
            left: Constants.Popup.spacing * 2,
            bottom: 0,
            right: Constants.Popup.spacing * 2
        )

        view.addArrangedSubview(self.chartsView())
        view.addArrangedSubview(self.detailsView())
        self.addArrangedSubview(view)
    }

    private func chartsView() -> NSView {
        let view = NSStackView()
        view.orientation = .vertical
        view.distribution = .fillEqually
        view.spacing = Constants.Popup.spacing * 2
        view.edgeInsets = NSEdgeInsets(
            top: Constants.Popup.spacing * 4,
            left: Constants.Popup.spacing * 4,
            bottom: Constants.Popup.spacing * 4,
            right: Constants.Popup.spacing * 4
        )

        let chart = PieChartView(frame: NSRect.zero, segments: [], drawValue: true)
        chart.toolTip = localizedString("ARC utilization")
        view.addArrangedSubview(chart)
        self.circle = chart
        return view
    }

    private func detailsView() -> NSView {
        let view = NSStackView()
        view.orientation = .vertical
        view.distribution = .fillEqually
        view.spacing = Constants.Popup.spacing * 2

        self.arcSizeField     = portalRow(view, title: "\(localizedString("ARC size")):").1
        self.arcHitRatioField = portalRow(view, title: "\(localizedString("Hit ratio")):").1
        self.l2Field          = portalRow(view, title: "\(localizedString("L2ARC")):").1
        return view
    }

    internal func callback(_ value: ZFS_Stats) {
        DispatchQueue.main.async(execute: {
            if (self.window?.isVisible ?? false) || !self.initialized {
                self.arcSizeField?.stringValue     = Units(bytes: value.arcSize).getReadableMemory(style: .memory)
                self.arcHitRatioField?.stringValue = "\(Int(value.arcHitRatio * 100))%"
                self.l2Field?.stringValue          = value.l2Available
                    ? Units(bytes: value.l2Size).getReadableMemory(style: .memory)
                    : localizedString("N/A")

                self.circle?.toolTip = "\(localizedString("ARC utilization")): \(Int(value.arcUtilization * 100))%"
                self.circle?.setValue(value.arcUtilization)
                self.circle?.setSegments([ColorValue(value.arcUtilization)])

                self.initialized = true
            }
        })
    }
}
