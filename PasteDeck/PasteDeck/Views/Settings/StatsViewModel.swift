//
//  StatsViewModel.swift
//  PasteDeck
//
//  Created on 2026-07-07.
//

import Foundation
import Combine
import SwiftData

@MainActor
final class StatsViewModel: ObservableObject {

    @Published var overview: OverviewStats?
    @Published var trend: [DailyTrendPoint] = []
    @Published var typeDistribution: [TypeDistributionItem] = []
    @Published var topSourceApps: [SourceAppStat] = []
    @Published var extremes: ExtremeStats?
    @Published var isLoading = false
    @Published var trendDays: Int = 7

    private var hasLoaded = false

    func loadIfNeeded() {
        guard !hasLoaded else { return }
        loadAll()
    }

    func loadAll() {
        isLoading = true
        hasLoaded = true

        let days = trendDays

        Task { [weak self] in
            async let o = Task.detached(priority: .userInitiated) { StatsService.fetchOverview() }.value
            async let t = Task.detached(priority: .userInitiated) { StatsService.fetchTrend(days: days) }.value
            async let d = Task.detached(priority: .userInitiated) { StatsService.fetchTypeDistribution() }.value
            async let s = Task.detached(priority: .userInitiated) { StatsService.fetchTopSourceApps() }.value
            async let e = Task.detached(priority: .userInitiated) { StatsService.fetchExtremes() }.value

            let (overview, trend, distribution, apps, extremes) = await (o, t, d, s, e)

            guard let self else { return }

            self.overview = overview
            self.trend = trend
            self.typeDistribution = distribution
            self.topSourceApps = apps
            self.extremes = extremes
            self.isLoading = false
        }
    }

    func reloadTrend() {
        let days = trendDays
        Task { [weak self] in
            let trend = await Task.detached(priority: .userInitiated) { StatsService.fetchTrend(days: days) }.value
            guard let self else { return }
            self.trend = trend
        }
    }

    func markStale() {
        hasLoaded = false
    }
}
