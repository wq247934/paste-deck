import Foundation

/// The start-up choreography of each vehicle (DESIGN 4c, Start-up), as modifiers over the seconds `tau` since it began.
public enum HeroStartup {
    public static func effects(kind: HeroVehicleKind, tau: Double) -> HeroStartupEffects {
        var fx = HeroStartupEffects()
        guard tau >= 0 else {
            fx.flame = 0
            fx.contrail = 0
            fx.shock = 0
            fx.hover = 0
            return fx
        }
        func bump(_ start: Double, _ peak: Double, _ end: Double) -> Double { HeroMath.bump(tau, start, peak, end) }
        switch kind {
        case .walk:
            break
        case .bicycle, .ebike:
            fx.hipLift = 1.3 * bump(0, 0.18, 0.6)
            fx.lurch = 1.6 * bump(0, 0.22, 0.9)
            if kind == .ebike { fx.lights = bump(0, 0.08, 0.5) }
        case .motorcycle:
            fx.pitch = -3 * bump(0.12, 0.34, 0.8)
            fx.shake = 0.35 * (1 - HeroMath.smooth(tau / 0.3))
            fx.lurch = 1.4 * bump(0.1, 0.35, 0.9)
        case .car, .sportsCar:
            fx.lights = max(bump(0, 0.04, 0.12), bump(0.16, 0.2, 0.3))
            fx.pitch = -1.3 * bump(0.05, 0.25, 0.7)
            fx.lurch = 1.2 * bump(0.08, 0.3, 0.9)
        case .raceCar:
            fx.pitch = -1.1 * bump(0, 0.2, 0.6)
            fx.lurch = 2.0 * bump(0.05, 0.28, 0.9)
        case .bulletTrain:
            fx.lights = bump(0, 0.15, 0.7)
            fx.lurch = 1.0 * bump(0.1, 0.45, 1.1)
        case .maglev:
            fx.hover = HeroMath.smooth((tau - 0.2) / 0.5)
            fx.lights = bump(0, 0.15, 0.7)
            fx.glow = bump(0, 0.3, 0.8)
        case .jetliner:
            fx.contrail = HeroMath.smooth(tau / 1.2)
            fx.lift = -2 * bump(0.1, 0.5, 1.2)
            fx.lights = bump(0, 0.2, 0.8)
        case .fighterJet, .hypersonic:
            fx.flame = tau < 0.35 ? HeroMath.spring(at: tau, from: 0, to: 1, velocity: 9, response: 0.32, damping: 0.55) : 1
            fx.glow = bump(0, 0.06, 0.35)
            fx.shock = HeroMath.smooth((tau - 0.1) / 0.4)
            fx.lurch = 1.4 * bump(0, 0.2, 0.8)
        case .rocket:
            fx.flame = tau < 0.4 ? HeroMath.spring(at: tau, from: 0, to: 1, velocity: 8, response: 0.36, damping: 0.5) : 1
            fx.glow = bump(0, 0.06, 0.4)
            fx.shake = 0.8 * (1 - HeroMath.smooth(tau / 0.6))
            fx.lift = 6 * (1 - HeroMath.easeInCubic(tau / 0.9))
        }
        return fx
    }
}
