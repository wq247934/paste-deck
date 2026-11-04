import AgentSpeedCore

extension AgentSpeedModel {
    /// The live traffic as every surface shows it: sources turned off in Settings → Data Sources left out (METRICS 10.5,
    /// DESIGN 10). Reading it observes both the snapshot and the enabled sources.
    var visibleTraffic: TrafficSnapshot {
        TrafficVisibility.snapshot(traffic.snapshot, enabled: SourceSet(settings.enabledSources))
    }
}
