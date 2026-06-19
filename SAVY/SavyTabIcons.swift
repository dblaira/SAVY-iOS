import SwiftUI

struct SavyTabIcon: View {
    let section: SavyNavigationSection

    var body: some View {
        Group {
            switch section {
            case .now:
                SavyTabActionIcon()
            case .essays:
                SavyTabEssaysIcon()
            case .beliefs:
                SavyTabBeliefsIcon()
            case .news:
                SavyTabNewsIcon()
            }
        }
        .frame(width: RootHomeLayout.bottomNavigationIconSize, height: RootHomeLayout.bottomNavigationIconSize)
        .accessibilityHidden(true)
    }
}

private struct SavyTabActionIcon: View {
    var body: some View {
        Canvas { context, size in
            let stroke = StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let outer: CGFloat = min(size.width, size.height) * 0.38
            let inner: CGFloat = outer * 0.28

            var star = Path()
            for index in 0..<8 {
                let angle = (Double(index) * .pi / 4) - .pi / 2
                let radius = index.isMultiple(of: 2) ? outer : inner
                let point = CGPoint(
                    x: center.x + CGFloat(cos(angle)) * radius,
                    y: center.y + CGFloat(sin(angle)) * radius
                )
                if index == 0 {
                    star.move(to: point)
                } else {
                    star.addLine(to: point)
                }
            }
            star.closeSubpath()
            context.stroke(star, with: .foreground, style: stroke)
        }
    }
}

private struct SavyTabEssaysIcon: View {
    var body: some View {
        Canvas { context, size in
            let stroke = StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round)
            let inset: CGFloat = size.width * 0.18
            let rect = CGRect(
                x: inset,
                y: inset * 0.7,
                width: size.width - inset * 2,
                height: size.height - inset * 1.5
            )

            var doc = Path(roundedRect: rect, cornerRadius: 2.2)
            context.stroke(doc, with: .foreground, style: stroke)

            let lineStart = rect.minX + rect.width * 0.22
            let lineEnd = rect.maxX - rect.width * 0.18
            for offset in [0.34, 0.52, 0.70] {
                var line = Path()
                line.move(to: CGPoint(x: lineStart, y: rect.minY + rect.height * offset))
                line.addLine(to: CGPoint(x: lineEnd, y: rect.minY + rect.height * offset))
                context.stroke(line, with: .foreground, style: stroke)
            }
        }
    }
}

private struct SavyTabBeliefsIcon: View {
    var body: some View {
        Canvas { context, size in
            let stroke = StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round)
            let bubbleRect = CGRect(
                x: size.width * 0.14,
                y: size.height * 0.16,
                width: size.width * 0.72,
                height: size.height * 0.52
            )

            var bubble = Path(roundedRect: bubbleRect, cornerRadius: bubbleRect.height * 0.22)
            context.stroke(bubble, with: .foreground, style: stroke)

            var tail = Path()
            tail.move(to: CGPoint(x: bubbleRect.minX + bubbleRect.width * 0.24, y: bubbleRect.maxY))
            tail.addLine(to: CGPoint(x: bubbleRect.minX + bubbleRect.width * 0.12, y: size.height * 0.86))
            tail.addLine(to: CGPoint(x: bubbleRect.minX + bubbleRect.width * 0.38, y: bubbleRect.maxY))
            context.stroke(tail, with: .foreground, style: stroke)

            for (index, xFactor) in [0.30, 0.50, 0.70].enumerated() {
                let center = CGPoint(
                    x: bubbleRect.minX + bubbleRect.width * xFactor,
                    y: bubbleRect.midY + (index == 1 ? 0.4 : 0)
                )
                let dot = Path(
                    ellipseIn: CGRect(
                        x: center.x - 1.1,
                        y: center.y - 1.1,
                        width: 2.2,
                        height: 2.2
                    )
                )
                context.fill(dot, with: .foreground)
            }
        }
    }
}

private struct SavyTabNewsIcon: View {
    var body: some View {
        Canvas { context, size in
            let stroke = StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round)
            let outer = CGRect(
                x: size.width * 0.14,
                y: size.height * 0.16,
                width: size.width * 0.72,
                height: size.height * 0.68
            )

            context.stroke(Path(roundedRect: outer, cornerRadius: 2), with: .foreground, style: stroke)

            let fold = Path {
                $0.move(to: CGPoint(x: outer.midX, y: outer.minY))
                $0.addLine(to: CGPoint(x: outer.maxX, y: outer.minY + outer.height * 0.18))
                $0.addLine(to: CGPoint(x: outer.midX, y: outer.minY + outer.height * 0.18))
                $0.closeSubpath()
            }
            context.stroke(fold, with: .foreground, style: stroke)

            let columnX = outer.minX + outer.width * 0.56
            var divider = Path()
            divider.move(to: CGPoint(x: columnX, y: outer.minY + outer.height * 0.18))
            divider.addLine(to: CGPoint(x: columnX, y: outer.maxY - outer.height * 0.14))
            context.stroke(divider, with: .foreground, style: stroke)

            let leftStart = outer.minX + outer.width * 0.16
            let leftEnd = columnX - outer.width * 0.08
            for offset in [0.40, 0.56, 0.72, 0.88] {
                var line = Path()
                line.move(to: CGPoint(x: leftStart, y: outer.minY + outer.height * offset))
                line.addLine(to: CGPoint(x: leftEnd, y: outer.minY + outer.height * offset))
                context.stroke(line, with: .foreground, style: stroke)
            }

            let imageRect = CGRect(
                x: columnX + outer.width * 0.08,
                y: outer.minY + outer.height * 0.30,
                width: outer.width * 0.28,
                height: outer.height * 0.22
            )
            context.stroke(Path(roundedRect: imageRect, cornerRadius: 1.2), with: .foreground, style: stroke)

            var caption = Path()
            caption.move(to: CGPoint(x: imageRect.minX, y: imageRect.maxY + outer.height * 0.08))
            caption.addLine(to: CGPoint(x: outer.maxX - outer.width * 0.12, y: imageRect.maxY + outer.height * 0.08))
            context.stroke(caption, with: .foreground, style: stroke)
        }
    }
}
