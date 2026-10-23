import SwiftUI
import CoreGraphics

struct ContextStatusView:View {
    let label:String
    var detail:String?
    var preview:CGImage?
    let onSettings:()->Void
    @State private var open=false
    var body:some View {
        Button{open.toggle()}label:{Label(label,systemImage:"rectangle.dashed").font(.system(size:12,weight:.medium)).lineLimit(1)}.buttonStyle(.plain).foregroundStyle(RelayTheme.muted)
            .popover(isPresented:$open){
                VStack(alignment:.leading,spacing:12){
                    Text("Conversation context").font(.system(size:13,weight:.semibold))
                    Text(detail ?? "Choose a window in Settings to add its visible text. Selected text is used only for explicit Help.").font(.system(size:12)).foregroundStyle(.secondary)
                    if let preview{Image(decorative:preview,scale:1).resizable().scaledToFit().frame(maxHeight:180).accessibilityLabel("Selected-window context preview")}
                    Button("Context settings",action:onSettings).buttonStyle(.bordered)
                }.padding(18).frame(width:320).preferredColorScheme(.dark)
            }
    }
}
