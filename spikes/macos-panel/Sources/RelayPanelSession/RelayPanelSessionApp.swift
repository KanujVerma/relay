import SwiftUI
import RelaySessionPanel

@main struct RelayPanelSessionApp: App {
    var body: some Scene {
        Window("Relay",id:"relay-session") { Text("Connecting Relay session…").padding(30) }
        .defaultSize(width:560,height:520)
    }
}
