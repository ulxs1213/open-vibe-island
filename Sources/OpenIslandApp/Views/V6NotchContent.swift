import SwiftUI
import OpenIslandCore

/// Per-cell state for the closed-island agents grid. Drives tile rendering:
/// running = full color, idle = dim, waiting = opacity pulse.
enum AgentGridCellState: Equatable {
    case running
    case idle
    case waiting
}

/// One cell in the closed-island agents grid. `.session` carries the agent
/// tool's brand color and its current state. `.overflow` is a single trailing
/// cell shown when there are more sessions than the grid can display.
enum AgentGridCell: Equatable {
    case session(color: Color, state: AgentGridCellState)
    case overflow(Int)
}

/// Concrete payload for the closed island's right slot. The `AppModel`
/// computes one of these from live session state according to the user's
/// `islandRightSlot` preference; the view side is agnostic to which
/// setting produced it.
enum IslandRightSlotContent: Equatable {
    case count(Int)              // "×N" badge
    case agents([AgentGridCell]) // balanced grid, one tile per session
}

// MARK: - Right-slot renderers

struct V6RightSlotView: View {
    let content: IslandRightSlotContent

    var body: some View {
        switch content {
        case .count(let n):
            Text("×\(n)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(V6Palette.paper.opacity(0.72))
        case .agents(let cells):
            AgentsGridBody(cells: cells)
        }
    }

    /// Intrinsic width used by the fluid-layout math. Values are slightly
    /// padded beyond the raw text measurement so the pill always reserves
    /// enough room for the `.fixedSize()` content to render on one line,
    /// without HStack compression forcing a wrap.
    static func intrinsicWidth(of content: IslandRightSlotContent) -> CGFloat {
        switch content {
        case .count(let n):
            let digits = Double(max(1, String(n).count))
            // "×" + digits at 11pt mono ≈ 7.2pt/char.
            return CGFloat(14.4 + max(0.0, digits - 1.0) * 7.2)
        case .agents(let cells):
            let n = cells.count
            guard n > 0 else { return 0 }
            let rows = balancedRows(n)
            let maxRow = rows.max() ?? 0
            let geom = cellGeometry(rowCount: rows.count)
            return CGFloat(maxRow) * geom.cell + CGFloat(max(0, maxRow - 1)) * geom.gap
        }
    }

    // MARK: Balanced layout algorithm
    //
    // For each n from 1 to 9, we hand-tune the per-row cell counts so the
    // matrix reads as a deliberate shape instead of a wrap-at-4-columns grid.
    // For n >= 10 the AppModel caps the list at 7 sessions + 1 overflow cell,
    // which lays out as [4,4] — so balancedRows(8) is what actually renders
    // for all high-count cases in production.
    static func balancedRows(_ n: Int) -> [Int] {
        switch n {
        case ..<1: return []
        case 1: return [1]
        case 2: return [2]
        case 3: return [3]
        case 4: return [2, 2]
        case 5: return [3, 2]
        case 6: return [3, 3]
        case 7: return [4, 3]
        case 8: return [4, 4]
        case 9: return [3, 3, 3]
        default: return [4, 4]
        }
    }

    /// Cell size shrinks when the matrix has 3 rows so total height still
    /// fits inside the pill's internal vertical budget (~20pt).
    static func cellGeometry(rowCount: Int) -> (cell: CGFloat, gap: CGFloat, radius: CGFloat) {
        if rowCount >= 3 { return (cell: 6, gap: 1.5, radius: 1.0) }
        return (cell: 8, gap: 2, radius: 1.5)
    }

    static func splitIntoRows(_ cells: [AgentGridCell], rowSizes: [Int]) -> [[AgentGridCell]] {
        var out: [[AgentGridCell]] = []
        var idx = 0
        for size in rowSizes {
            let end = min(idx + size, cells.count)
            out.append(Array(cells[idx..<end]))
            idx = end
            if idx >= cells.count { break }
        }
        return out
    }
}

// MARK: - Agents grid body

/// V1a Dense Grid renderer. 2D matrix of 8×8 rounded squares (6×6 when 3 rows),
/// each row horizontally centered around the widest row. Running = full color,
/// idle = 22% alpha, waiting = opacity 0.35 ↔ 1 breathing pulse.
private struct AgentsGridBody: View {
    let cells: [AgentGridCell]

    var body: some View {
        let rowSizes = V6RightSlotView.balancedRows(cells.count)
        let geom = V6RightSlotView.cellGeometry(rowCount: rowSizes.count)
        let rows = V6RightSlotView.splitIntoRows(cells, rowSizes: rowSizes)

        VStack(spacing: geom.gap) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: geom.gap) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        AgentsGridTileView(cell: cell, size: geom.cell, radius: geom.radius)
                    }
                }
            }
        }
        .fixedSize()
    }
}

private struct AgentsGridTileView: View {
    let cell: AgentGridCell
    let size: CGFloat
    let radius: CGFloat

    var body: some View {
        switch cell {
        case .session(let color, let state):
            switch state {
            case .running:
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(color)
                    .frame(width: size, height: size)
            case .idle:
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(color.opacity(0.22))
                    .frame(width: size, height: size)
            case .waiting:
                AgentsGridWaitingTile(color: color, size: size, radius: radius)
            }
        case .overflow(let n):
            ZStack {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(V6Palette.paper.opacity(0.14))
                Text("+\(n)")
                    .font(.system(size: max(5, size * 0.55), weight: .bold, design: .monospaced))
                    .foregroundStyle(V6Palette.paper)
            }
            .frame(width: size, height: size)
        }
    }
}

private struct AgentsGridWaitingTile: View {
    let color: Color
    let size: CGFloat
    let radius: CGFloat
    @State private var pulse = false

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(color)
            .frame(width: size, height: size)
            .opacity(pulse ? 1.0 : 0.35)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}

// MARK: - Center label renderer

struct V6CenterLabelView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(V6Palette.paper)
    }

    static func intrinsicWidth(of text: String) -> CGFloat {
        CGFloat(Double(text.count) * 7.3 + 10)
    }
}

struct V6ClosedLeftStatusView: View {
    let text: String
    let tint: Color

    private static let horizontalPadding: CGFloat = 9
    private static let verticalPadding: CGFloat = 4
    private static let componentSpacing: CGFloat = 5

    var body: some View {
        let parts = Self.statusParts(for: text)

        HStack(spacing: Self.componentSpacing) {
            Text(parts.value)
                .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                .foregroundStyle(tint)

            if let countdown = parts.countdown {
                Text(countdown)
                    .font(.system(size: 10.8, weight: .semibold, design: .monospaced))
                    .foregroundStyle(V6Palette.paper.opacity(0.62))
            }
        }
            .padding(.horizontal, Self.horizontalPadding)
            .padding(.vertical, Self.verticalPadding)
            .background(tint.opacity(0.09), in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(tint.opacity(0.32), lineWidth: 1)
            )
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    static func intrinsicWidth(of text: String) -> CGFloat {
        let parts = statusParts(for: text)
        let valueWidth = visualWidth(of: parts.value, asciiWidth: 6.9)
        let countdownWidth = parts.countdown.map {
            Self.componentSpacing + visualWidth(of: $0, asciiWidth: 6.6)
        } ?? 0

        return (Self.horizontalPadding * 2) + valueWidth + countdownWidth + 2
    }

    private static func statusParts(for text: String) -> (value: String, countdown: String?) {
        let pieces = text.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let value = pieces.first else {
            return (text, nil)
        }

        let countdown = pieces.count > 1 ? String(pieces[1]) : nil
        return (String(value), countdown)
    }

    private static func visualWidth(of text: String, asciiWidth: CGFloat) -> CGFloat {
        text.unicodeScalars.reduce(CGFloat.zero) { width, scalar in
            width + (scalar.value < 128 ? asciiWidth : 12.0)
        }
    }
}

// MARK: - Closed-pill layouts

/// The canonical v6 closed-island pill rendered inside a fixed-height frame.
/// Pure view — takes all parameters explicitly so it can be reused for the
/// live settings preview and the real island.
struct V6ClosedPill: View {
    var mode: UnifiedBars.Mode
    var label: String?          // suppressed automatically in MacBook layout
    var leftStatusText: String? = nil
    var leftStatusTint: Color = .green.opacity(0.95)
    var rightSlot: IslandRightSlotContent?
    var layout: V6ClosedLayout
    var height: CGFloat = 32

    /// MacBook mode only — width of the physical notch cutout to wrap.
    var physicalNotchWidth: CGFloat = 0

    /// External mode only — minimum pill width (locked). Defaults to the
    /// width that fits just the glyph.
    var minWidth: CGFloat = 70

    var body: some View {
        switch layout {
        case .external: externalBody
        case .macbook:  macbookBody
        }
    }

    // Horizontal edge padding is identical left/right — canonical v6 pill
    // has r = h/2 semicircular bottoms, so edge inset = r keeps content
    // clear of the curve.
    private var pad: CGFloat { height / 2 }

    // Minimum breathing room between the center label (or glyph, when no
    // label) and the right-slot content so they never touch at small widths.
    private static let innerGap: CGFloat = 6

    // MARK: External (fluid)

    private var externalBody: some View {
        let glyphW: CGFloat = 24
        let labelW = label.map { V6CenterLabelView.intrinsicWidth(of: $0) } ?? 0
        let rightW = rightSlot.map { V6RightSlotView.intrinsicWidth(of: $0) } ?? 0

        let labelBlock = (label == nil ? 0 : 6 + labelW)
        let rightBlock = (rightSlot == nil ? 0 : Self.innerGap + rightW)
        let intrinsic = pad * 2 + glyphW + labelBlock + rightBlock
        let width = max(minWidth, intrinsic)

        return ZStack {
            V6ClosedPillShape()
                .fill(V6Palette.ink)

            HStack(spacing: 0) {
                UnifiedBars(mode: mode, size: 24)
                    .frame(width: glyphW, height: 24)

                if let label {
                    V6CenterLabelView(text: label)
                        .padding(.leading, 6)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }

                Spacer(minLength: Self.innerGap)

                if let rightSlot {
                    V6RightSlotView(content: rightSlot)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .padding(.horizontal, pad)
        }
        .frame(width: width, height: height)
        .animation(
            .timingCurve(0.4, 0, 0.2, 1, duration: 0.45),
            value: AnyHashable([
                AnyHashable(label ?? ""),
                AnyHashable(rightSlot.map(RightSlotKey.init) ?? .none),
                AnyHashable(mode),
            ])
        )
    }

    // MARK: MacBook (outer width locked)

    private var macbookBody: some View {
        let baseSideReserve: CGFloat = 44
        let leftStatusWidth = leftStatusText.map { V6ClosedLeftStatusView.intrinsicWidth(of: $0) } ?? 0
        let leftStatusGap: CGFloat = leftStatusText == nil ? 0 : 7
        let leftTrailingSpace: CGFloat = leftStatusText == nil ? 0 : 10
        let rightSlotWidth = rightSlot.map { V6RightSlotView.intrinsicWidth(of: $0) } ?? 0
        let leftReserve = max(
            baseSideReserve,
            pad + 24 + leftStatusGap + leftStatusWidth + leftTrailingSpace
        )
        let rightReserve = max(baseSideReserve, pad + rightSlotWidth)
        let outer = leftReserve + physicalNotchWidth + rightReserve

        return ZStack {
            V6ClosedPillShape()
                .fill(V6Palette.ink)

            HStack(spacing: 0) {
                HStack(spacing: leftStatusGap) {
                    UnifiedBars(mode: mode, size: 24)
                        .frame(width: 24, height: 24)

                    if let leftStatusText {
                        V6ClosedLeftStatusView(text: leftStatusText, tint: leftStatusTint)
                            .transition(.opacity.combined(with: .move(edge: .leading)))
                    }
                }
                .padding(.leading, pad)
                .frame(width: leftReserve, alignment: .leading)

                Color.clear
                    .frame(width: physicalNotchWidth)

                if let rightSlot {
                    V6RightSlotView(content: rightSlot)
                        .padding(.trailing, pad)
                        .frame(width: rightReserve, alignment: .trailing)
                } else {
                    Color.clear
                        .frame(width: rightReserve)
                }
            }
        }
        .frame(width: outer, height: height)
        .offset(x: (rightReserve - leftReserve) / 2)
        .animation(
            .timingCurve(0.4, 0, 0.2, 1, duration: 0.42),
            value: AnyHashable([
                AnyHashable(leftStatusText ?? ""),
                AnyHashable(rightSlot.map(RightSlotKey.init) ?? .none),
                AnyHashable(mode),
            ])
        )
    }
}

enum V6ClosedLayout: Equatable {
    case external
    case macbook
}

private enum RightSlotKey: Hashable {
    case count(Int)
    case agents(Int)

    init(_ content: IslandRightSlotContent) {
        switch content {
        case .count(let n):    self = .count(n)
        case .agents(let cs):  self = .agents(cs.count)
        }
    }
}

// MARK: - Settings-tab live preview

/// Fixed-width pill that mimics the real island inside the settings-tab
/// preview stage. Parameters match what the tab exposes.
struct IslandPreviewPill: View {
    let mode: UnifiedBars.Mode
    let label: String?
    let rightSlot: IslandRightSlotContent?
    let layout: V6ClosedLayout
    let physicalNotchWidth: CGFloat
    let now: Date

    var body: some View {
        V6ClosedPill(
            mode: mode,
            label: label,
            rightSlot: rightSlot,
            layout: layout,
            physicalNotchWidth: physicalNotchWidth
        )
        .frame(maxWidth: .infinity, alignment: .center)
    }
}
