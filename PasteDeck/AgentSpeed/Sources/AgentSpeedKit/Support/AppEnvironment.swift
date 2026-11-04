import SwiftUI

/// Applies the app language to a SwiftUI subtree and keeps it live.
struct AppEnvironment<Content: View>: View {
    let model: AgentSpeedModel
    @ViewBuilder var content: Content

    var body: some View {
        content
            .environment(\.locale, model.l10n.locale)
    }
}

extension View {
    func appEnvironment(_ model: AgentSpeedModel) -> some View {
        AppEnvironment(model: model) { self }
    }
}
