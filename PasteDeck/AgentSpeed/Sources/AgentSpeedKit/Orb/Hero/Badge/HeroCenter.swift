import AgentSpeedHero
import AgentSpeedOrbModel
import SwiftUI

/// Which art the dashboard hero's center shows (DESIGN 4c): the vehicle for the Vehicles title theme (and custom sets
/// based on it), else the title badge; a General theme change crossfades between them in 0.3 s (Reduce Motion: cut).
struct HeroArtState {
    private(set) var showsBadge: Bool?
    private(set) var changedAt: TimeInterval = -.infinity
    private(set) var fadeFrom = 0.0

    static let crossfade: TimeInterval = 0.3

    /// 0 = the vehicle, 1 = the badge.
    func badgeMix(at time: TimeInterval) -> Double {
        let target = showsBadge == true ? 1.0 : 0.0
        let p = ((time - changedAt) / Self.crossfade).clamped(to: 0...1)
        return fadeFrom + (target - fadeFrom) * Easing.smoothstep(0, 1, p)
    }

    /// Notes the art the theme asks for; returns true when it changed.
    mutating func update(showsBadge: Bool, at time: TimeInterval, reduceMotion: Bool) -> Bool {
        guard showsBadge != self.showsBadge else { return false }
        let first = self.showsBadge == nil
        fadeFrom = first || reduceMotion ? (showsBadge ? 1 : 0) : badgeMix(at: time)
        self.showsBadge = showsBadge
        changedAt = first || reduceMotion ? -.infinity : time
        return true
    }

    func isFading(at time: TimeInterval) -> Bool { time - changedAt < Self.crossfade }

    private var labelsKey: (theme: TitleTheme, language: AppLanguage)?
    private var labels: [String] = []

    /// Every title's badge text in `theme` by level, built once per theme and language (no strings per frame).
    @MainActor
    mutating func labels(_ theme: TitleTheme, model: AgentSpeedModel) -> [String] {
        let language = model.l10n.language
        if labelsKey?.theme != theme || labelsKey?.language != language {
            labels = SpeedTitle.allCases.map { model.titles.label($0, in: theme, l10n: model.l10n) }
            labelsKey = (theme, language)
        }
        return labels
    }
}

@MainActor
enum HeroCenter {
    /// Adds the hero's center art (vehicle layer and/or title badge) to the embedded orb's scene.
    static func build(into scene: inout OrbScene, animator: OrbAnimator, model: AgentSpeedModel, content: OrbContent,
                      geometry: OrbGeometry, time: TimeInterval, sweepEpoch: TimeInterval) {
        let titles = model.titles
        let theme = titles.general
        let reduceMotion = animator.hero?.overrides.reduceMotion ?? model.accessibility.reduceMotion
        if animator.heroArt.update(showsBadge: !theme.showsVehicleArt, at: time, reduceMotion: reduceMotion) {
            if theme.showsVehicleArt { animator.hero?.reset() } else { animator.badge?.reset() }
        }
        let mix = animator.heroArt.badgeMix(at: time)
        if mix < 0.999, let hero = animator.hero {
            var layer = hero.layer(model: model, content: content, geometry: geometry, time: time, sweepEpoch: sweepEpoch)
            layer.alpha = Float(1 - mix)
            scene.vehicle = layer
        }
        guard mix > 0.001, let badge = animator.badge else { return }
        let start = DispatchTime.now().uptimeNanoseconds
        defer { badge.recordFrame(DispatchTime.now().uptimeNanoseconds - start) }
        // The Settings preview's hero follows its own scripted gauge.
        let gauge = animator.hero?.gauge ?? model.gauge
        let labels = animator.heroArt.labels(theme, model: model)
        let level = gauge.title.rawValue
        let text = labels[level]
        badge.step(HeroBadgeInput(
            time: time,
            level: level,
            titleChangedAt: gauge.titleChangedAt,
            heat: gauge.heat(at: time),
            overdrive: gauge.overdrive(at: time),
            tier: gauge.tier.rawValue,
            redline: gauge.redline,
            level4c: animator.hero?.overrides.level ?? HeroLevel(model.settings.effects),
            reduceMotion: reduceMotion,
            sweepEpoch: sweepEpoch
        ), text: text)
        let previous = badge.transition.map(\.from) ?? level
        badge.build(into: &scene, HeroBadgeStyle(
            center: geometry.center,
            unit: 0.72 * geometry.diameter / 100,
            dark: content.tokens.isDark,
            increaseContrast: animator.hero?.overrides.increaseContrast ?? content.increaseContrast,
            language: model.l10n.language,
            text: text,
            previousText: labels.indices.contains(previous) ? labels[previous] : text,
            alpha: mix
        ))
    }

    /// The hero's frame demand: the art that is shown, both while they crossfade.
    static func demand(animator: OrbAnimator, model: AgentSpeedModel, at time: TimeInterval) -> HeroFrameDemand? {
        guard let hero = animator.hero else { return nil }
        if animator.heroArt.isFading(at: time) { return .full }
        guard animator.heroArt.showsBadge == true || !model.titles.general.showsVehicleArt, let badge = animator.badge else {
            return hero.demand()
        }
        return badge.demand(at: time)
    }
}
