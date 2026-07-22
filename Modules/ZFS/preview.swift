//
//  preview.swift
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

internal class Preview: PreviewWrapper {
    private var arcChart: LineChartView? = nil
    private var arcSizeField: NSTextField? = nil
    private var arcHitRatioField: NSTextField? = nil
    private var l2SizeField: NSTextField? = nil
    private var l2HitRatioField: NSTextField? = nil
    private var initialized: Bool = false

    public init(_ module: ModuleType) {
        super.init(type: module)

        let arcSection = NSStackView()
        arcSection.orientation = .horizontal
        arcSection.distribution = .fillEqually

        let leftView = NSStackView()
        leftView.orientation = .vertical
        leftView.addArrangedSubview(self.arcView())

        let rightView = NSStackView()
        rightView.orientation = .vertical
        rightView.addArrangedSubview(self.l2View())

        arcSection.addArrangedSubview(leftView)
        arcSection.addArrangedSubview(rightView)

        self.addArrangedSubview(PreferencesSection([self.historyView()]))
        self.addArrangedSubview(arcSection)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func historyView() -> NSView {
        let chart = LineChartView(frame: NSRect(x: 0, y: 0, width: 264, height: 60), num: 60)
        self.arcChart = chart
        chart.heightAnchor.constraint(equalToConstant: 60).isActive = true
        return chart
    }

    private func arcView() -> NSView {
        let view = NSStackView()
        view.orientation = .vertical
        view.spacing = 2
        view.edgeInsets = NSEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)

        let titleLabel = NSTextField(labelWithString: localizedString("ARC"))
        titleLabel.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        view.addArrangedSubview(titleLabel)

        let sizeRow = NSStackView()
        sizeRow.orientation = .horizontal
        let sizeLabel = NSTextField(labelWithString: "\(localizedString("Size")):")
        sizeLabel.font = NSFont.systemFont(ofSize: 10)
        self.arcSizeField = NSTextField(labelWithString: "–")
        self.arcSizeField!.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        self.arcSizeField!.alignment = .right
        sizeRow.addArrangedSubview(sizeLabel)
        sizeRow.addArrangedSubview(self.arcSizeField!)
        view.addArrangedSubview(sizeRow)

        let ratioRow = NSStackView()
        ratioRow.orientation = .horizontal
        let ratioLabel = NSTextField(labelWithString: "\(localizedString("Hit ratio")):")
        ratioLabel.font = NSFont.systemFont(ofSize: 10)
        self.arcHitRatioField = NSTextField(labelWithString: "–")
        self.arcHitRatioField!.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        self.arcHitRatioField!.alignment = .right
        ratioRow.addArrangedSubview(ratioLabel)
        ratioRow.addArrangedSubview(self.arcHitRatioField!)
        view.addArrangedSubview(ratioRow)

        return view
    }

    private func l2View() -> NSView {
        let view = NSStackView()
        view.orientation = .vertical
        view.spacing = 2
        view.edgeInsets = NSEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)

        let titleLabel = NSTextField(labelWithString: localizedString("L2ARC"))
        titleLabel.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        view.addArrangedSubview(titleLabel)

        let sizeRow = NSStackView()
        sizeRow.orientation = .horizontal
        let sizeLabel = NSTextField(labelWithString: "\(localizedString("Size")):")
        sizeLabel.font = NSFont.systemFont(ofSize: 10)
        self.l2SizeField = NSTextField(labelWithString: "–")
        self.l2SizeField!.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        self.l2SizeField!.alignment = .right
        sizeRow.addArrangedSubview(sizeLabel)
        sizeRow.addArrangedSubview(self.l2SizeField!)
        view.addArrangedSubview(sizeRow)

        let ratioRow = NSStackView()
        ratioRow.orientation = .horizontal
        let ratioLabel = NSTextField(labelWithString: "\(localizedString("Hit ratio")):")
        ratioLabel.font = NSFont.systemFont(ofSize: 10)
        self.l2HitRatioField = NSTextField(labelWithString: "–")
        self.l2HitRatioField!.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        self.l2HitRatioField!.alignment = .right
        ratioRow.addArrangedSubview(ratioLabel)
        ratioRow.addArrangedSubview(self.l2HitRatioField!)
        view.addArrangedSubview(ratioRow)

        return view
    }

    public func loadCallback(_ value: ZFS_Stats) {
        DispatchQueue.main.async(execute: {
            if (self.window?.isVisible ?? false) || !self.initialized {
                self.arcSizeField?.stringValue     = Units(bytes: value.arcSize).getReadableMemory(style: .memory)
                self.arcHitRatioField?.stringValue = "\(Int(value.arcHitRatio * 100))%"
                self.l2SizeField?.stringValue      = value.l2Available
                    ? Units(bytes: value.l2Size).getReadableMemory(style: .memory)
                    : localizedString("N/A")
                self.l2HitRatioField?.stringValue  = value.l2Available
                    ? "\(Int(value.l2HitRatio * 100))%"
                    : localizedString("N/A")
                self.initialized = true
            }
            self.arcChart?.addValue(value.arcHitRatio)
        })
    }
}
