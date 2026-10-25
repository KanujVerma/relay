import SwiftUI

struct SessionToolbar:View {
    let state:RelaySessionPresentation
    var elapsed:String?
    var expanded=true
    let onExpand:()->Void
    let onAction:(RelayUIAction)->Void
    var body:some View {
        HStack(spacing:6){
            Button(action:onExpand){RelayBrand(compact:true).frame(width:32,height:32)}.buttonStyle(.plain).padding(.leading,7).help(expanded ? "Collapse answer":"Expand answer").accessibilityLabel(expanded ? "Collapse answer":"Expand answer")
            HStack(spacing:5){Circle().fill(state.running ? RelayTheme.live:Color.white.opacity(0.4)).frame(width:5,height:5);Text(elapsed ?? state.status).font(.system(size:11,weight:.medium,design:elapsed==nil ? .default:.monospaced))}.foregroundStyle(RelayTheme.secondary).accessibilityLabel(state.status+(elapsed.map{" "+$0} ?? ""))
            Spacer(minLength:6)
            Button("Help"){onAction(.help)}.font(.system(size:12,weight:.semibold)).frame(width:58,height:32).background(.white.opacity(0.09),in:Capsule()).buttonStyle(.plain).disabled(!state.allows(.help)).help("Get help with the current question")
            if state.paused{RelayIconButton(title:"Resume session",symbol:"play.fill",enabled:state.allows(.resume)){onAction(.resume)}}
            else{RelayIconButton(title:"Pause session",symbol:"pause.fill",enabled:state.allows(.pause)){onAction(.pause)}}
            RelayIconButton(title:"End session",symbol:"stop.fill",enabled:state.allows(.end)){onAction(.end)}
        }.padding(.trailing,7).frame(width:350,height:50).background(RelayTheme.pill,in:Capsule()).overlay{Capsule().strokeBorder(.white.opacity(0.09))}
            .shadow(color:.black.opacity(0.25),radius:12,y:4).preferredColorScheme(.dark)
    }
}
