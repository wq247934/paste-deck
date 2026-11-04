import Foundation

/// The board events as the styles play them (the prototypes' `overtake`, `render` and `layout` effect calls).
public extension BoardEffects {
    /// A group passed the one above (DESIGN 2c Overtake): streaks along its row in its source color and a burst from
    /// its rank; neon also arcs lightning from the rank to the row it passed (`passedRankY`, board points).
    mutating func overtake(row: CGRect, rank: CGPoint, color: BoardFXColor, passedRankY: Double? = nil) {
        streak(from: row.minX, to: row.maxX, y: row.midY, color: color)
        var spec = preset.overtakeBurst
        if preset.overtakeBurstInSourceColor { spec.colors = BoardFXPalette(color, .fxWhite) }
        burst(x: rank.x, y: rank.y, spec)
        if preset.lightning, let passedRankY {
            lightning(from: SIMD2(rank.x, rank.y), to: SIMD2(rank.x + 8, passedRankY), color: color, branches: 1, life: 0.3)
        }
    }

    /// A group reached first (DESIGN 2c New leader): its row's streaks and the celebration from its rank; neon strikes
    /// lightning from the top edge to the rank and flashes the board. With `Celebrate new peaks` off it is an overtake.
    mutating func newLeader(row: CGRect, rank: CGPoint, color: BoardFXColor, passedRankY: Double? = nil) {
        guard celebrations, intensity != .off else {
            overtake(row: row, rank: rank, color: color, passedRankY: passedRankY)
            return
        }
        streak(from: row.minX, to: row.maxX, y: row.midY, color: color)
        if preset.lightning, !reduceMotion {
            let x = rank.x + 30 + nextRandom() * 120
            lightning(from: SIMD2(x, -6), to: SIMD2(rank.x, rank.y), color: .fxGold, branches: 3, life: 0.45)
            flashBoard()
        }
        celebrate(x: rank.x, y: rank.y)
    }

    /// The hero number rose by more than 8 % + 20 tok/s in one tick (`rise` = the increase over the previous value):
    /// embers from the digits in `number` (board points) — glass rising sparks, timing a horizontal spray, neon rising
    /// sparks and a lightning arc across the digits.
    mutating func punch(number: CGRect, rise: Double) {
        let hot = heatColor(at: min(1, shownHeat + 0.1))
        switch preset.style {
        case .timing:
            burst(x: number.maxX, y: number.midY, BoardBurst(count: 10, speed: 150, angle: 0, spread: 0.7, life: 0.6,
                                                              colors: BoardFXPalette(hot, .fxWhite), size: 1.3, gravity: 0,
                                                              drag: 2.2))
        case .glass, .neon:
            let count = min(22, 6 + Int((max(0, rise) * 40).rounded()))
            burst(x: number.midX, y: number.midY - number.height * 0.3,
                  BoardBurst(count: count, speed: 90, angle: -.pi / 2, spread: 1.6, life: 1.1,
                             colors: BoardFXPalette(hot, .fxWhiteHot), size: 1.6, gravity: -30, drag: 1.2))
            if preset.style == .neon {
                let x0 = number.minX + number.width * (0.1 + nextRandom() * 0.3)
                let x1 = number.minX + number.width * (0.6 + nextRandom() * 0.35)
                lightning(from: SIMD2(x0, number.midY - number.height * 0.15),
                          to: SIMD2(x1, number.midY + number.height * 0.2),
                          color: heatColor(at: min(1, shownHeat + 0.15)), branches: 1, life: 0.28)
            }
        }
    }

    /// A new `peakToday_A`: a gold ring from the number (none with `Celebrate new peaks` off).
    mutating func newPeak(at center: CGPoint) {
        guard celebrations else { return }
        shockwave(x: center.x, y: center.y, color: .fxGold, maxRadius: 160, life: 0.9)
    }
}

extension BoardEffects {
    /// Redline sparks from every visible comet's head, outward (fx.js `emberTick`).
    mutating func emitEmbers() {
        let spec = BoardBurst(count: 3, speed: 70, spread: 0.9, life: 0.6,
                              colors: BoardFXPalette(.fxWhiteHot, heatColor(at: shownHeat)), size: 1.4, gravity: 40)
        for index in comets.indices where comets[index].targetOpacity > 0 {
            let head = outlinePoint(cometHead(index))
            var aimed = spec
            aimed.angle = head.outward
            burst(x: head.x, y: head.y, aimed)
        }
    }
}
