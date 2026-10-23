import SwiftUI

enum RelayTheme {
    static let base=Color(red:9/255,green:12/255,blue:13/255)
    static let raised=Color(red:18/255,green:21/255,blue:23/255)
    static let pill=Color(red:28/255,green:27/255,blue:31/255).opacity(0.96)
    static let line=Color.white.opacity(0.08)
    static let muted=Color.white.opacity(0.48)
    static let secondary=Color.white.opacity(0.72)
    static let live=Color(red:0.49,green:0.85,blue:0.66)
    static let chatWidth:CGFloat=690
    static let settingsWidth:CGFloat=920
}
struct RelayPrimaryButtonStyle:ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration:Configuration)->some View {
        configuration.label.font(.system(size:13,weight:.semibold)).padding(.horizontal,18).frame(height:36)
            .foregroundStyle(enabled ? Color.black:Color.white.opacity(0.35))
            .background(enabled ? Color.white.opacity(configuration.isPressed ? 0.75:0.94):Color.white.opacity(0.07),in:Capsule())
    }
}
struct RelayQuietButtonStyle:ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration:Configuration)->some View {
        configuration.label.font(.system(size:12,weight:.medium)).padding(.horizontal,12).frame(height:32)
            .foregroundStyle(Color.white.opacity(enabled ? 0.72:0.25))
            .background(Color.white.opacity(configuration.isPressed ? 0.14:0.06),in:RoundedRectangle(cornerRadius:10))
    }
}
struct RelayIconButton:View {
    let title:String,symbol:String
    var enabled=true
    let action:()->Void
    var body:some View {
        Button(action:action){Image(systemName:symbol).font(.system(size:14,weight:.medium)).frame(width:32,height:32).contentShape(Circle())}
            .buttonStyle(.plain).foregroundStyle(Color.white.opacity(enabled ? 0.72:0.24)).disabled(!enabled)
            .help(title).accessibilityLabel(title)
    }
}
struct RelayBrand:View {
    var compact=false
    var body:some View {
        HStack(spacing:8){Image(systemName:"waveform").font(.system(size:15,weight:.semibold)).frame(width:26,height:26).background(.white.opacity(0.09),in:RoundedRectangle(cornerRadius:8));if !compact{Text("Relay").font(.system(size:17,weight:.semibold))}}
            .foregroundStyle(.white)
    }
}
