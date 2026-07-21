//
//  InspectorCharts.swift
//  Pantrix
//
//  Hand-drawn charts on SwiftUI `Canvas` — no third-party dependency. The scale/tick/angle math is in the
//  Kit (`ChartScale` / `GaugeMath`), tested; these views only draw. iOS 15-gated (§4c).
//

import SwiftUI
import PantrixInspectorKit

/// A single line with a soft area fill, evenly spaced along x. Points are normalized through the Kit scale.
@available(iOS 15.0, *)
struct LineChart: View {
    let values: [Double]
    let scale: ChartScale
    var color: Color = .accentColor

    var body: some View {
        Canvas { context, size in
            guard values.count > 1 else { return }
            let stepX = size.width / CGFloat(values.count - 1)
            func point(_ i: Int) -> CGPoint {
                let y = 1 - CGFloat(scale.normalized(values[i]))
                return CGPoint(x: CGFloat(i) * stepX, y: y * size.height)
            }
            var line = Path()
            line.move(to: point(0))
            for i in 1..<values.count { line.addLine(to: point(i)) }

            var area = line
            area.addLine(to: CGPoint(x: size.width, y: size.height))
            area.addLine(to: CGPoint(x: 0, y: size.height))
            area.closeSubpath()
            context.fill(area, with: .color(color.opacity(0.15)))
            context.stroke(line, with: .color(color), lineWidth: 2)

            // Emphasise the newest (rightmost) sample.
            let last = point(values.count - 1)
            context.fill(Path(ellipseIn: CGRect(x: last.x - 3, y: last.y - 3, width: 6, height: 6)), with: .color(color))
        }
        .frame(height: 120)
    }
}

/// Several lines sharing one scale, with a legend.
@available(iOS 15.0, *)
struct MultiLineChart: View {
    struct Series: Identifiable { let id = UUID(); let values: [Double]; let color: Color; let label: String }
    let series: [Series]
    let scale: ChartScale

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Canvas { context, size in
                for s in series where s.values.count > 1 {
                    let stepX = size.width / CGFloat(s.values.count - 1)
                    var path = Path()
                    for (i, value) in s.values.enumerated() {
                        let p = CGPoint(x: CGFloat(i) * stepX, y: (1 - CGFloat(scale.normalized(value))) * size.height)
                        if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
                    }
                    context.stroke(path, with: .color(s.color), lineWidth: 2)
                }
            }
            .frame(height: 120)
            HStack(spacing: 12) {
                ForEach(series) { s in
                    HStack(spacing: 4) {
                        Circle().fill(s.color).frame(width: 8, height: 8)
                        Text(s.label).font(.caption2).foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}

/// An open-bottom gauge: an arc from 135° sweeping 270°, with the value fraction filled. Round caps.
@available(iOS 15.0, *)
struct ArcGauge: View {
    let fraction: Double
    var color: Color = .accentColor
    let centerText: String

    var body: some View {
        Canvas { context, size in
            let radius = Swift.min(size.width, size.height) / 2 - 8
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let start = Angle(degrees: GaugeMath.startDegrees)
            let full = Angle(degrees: GaugeMath.endDegrees(fraction: 1))
            let value = Angle(degrees: GaugeMath.endDegrees(fraction: fraction))

            var track = Path()
            track.addArc(center: center, radius: radius, startAngle: start, endAngle: full, clockwise: false)
            context.stroke(track, with: .color(color.opacity(0.2)), style: StrokeStyle(lineWidth: 10, lineCap: .round))

            var fill = Path()
            fill.addArc(center: center, radius: radius, startAngle: start, endAngle: value, clockwise: false)
            context.stroke(fill, with: .color(color), style: StrokeStyle(lineWidth: 10, lineCap: .round))
        }
        .overlay(Text(centerText).font(.title3.weight(.semibold)).monospacedDigit())
        .frame(width: 140, height: 140)
    }
}
