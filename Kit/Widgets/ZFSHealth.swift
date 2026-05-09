//
//  ZFSHealth.swift
//  Kit
//
//  Created by Eric DeWitt on 09/05/2026.
//  Using Swift 5.0.
//  Running on macOS 11.0.
//
//  Copyright © 2026 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa

public class ZFSHealthWidget: WidgetWrapper {
    private var statusText: String = "??"
    private var statusColor: NSColor = .systemGray

    private let dotSize: CGFloat = 6
    private let textWidth: CGFloat = 20

    public init(title: String, config: NSDictionary?, preview: Bool = false) {
        super.init(.zfsHealth, title: title, frame: CGRect(
            x: Constants.Widget.margin.x,
            y: Constants.Widget.margin.y,
            width: 6 + 3 + 20 + (Constants.Widget.margin.x * 2),
            height: Constants.Widget.height - (2 * Constants.Widget.margin.y)
        ))
        self.canDrawConcurrently = true
        if preview {
            self.statusText = "OK"
            self.statusColor = .systemGreen
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let h = self.frame.height
        let dotY = (h - dotSize) / 2

        let dot = NSBezierPath(ovalIn: CGRect(
            x: Constants.Widget.margin.x,
            y: dotY,
            width: dotSize,
            height: dotSize
        ))
        statusColor.setFill()
        dot.fill()

        let style = NSMutableParagraphStyle()
        style.alignment = .left
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .regular),
            .foregroundColor: statusColor,
            .paragraphStyle: style
        ]
        let textX = Constants.Widget.margin.x + dotSize + 3
        NSAttributedString(string: statusText, attributes: attrs)
            .draw(with: CGRect(x: textX, y: 1, width: textWidth, height: h))

        self.setWidth(textX + textWidth + Constants.Widget.margin.x)
    }

    public func setValue(health: String) {
        let (text, color): (String, NSColor) = {
            switch health {
            case "ONLINE":   return ("OK",  .systemGreen)
            case "DEGRADED": return ("DEG", .systemOrange)
            case "FAULTED":  return ("FLT", .systemRed)
            case "OFFLINE":  return ("OFF", .systemGray)
            case "REMOVED":  return ("RMV", .systemOrange)
            case "UNAVAIL":  return ("UNV", .systemRed)
            default:         return ("??",  .systemGray)
            }
        }()
        guard statusText != text else { return }
        statusText = text
        statusColor = color
        DispatchQueue.main.async { self.display() }
    }

    public override func settings() -> NSView {
        return SettingsContainerView()
    }
}
