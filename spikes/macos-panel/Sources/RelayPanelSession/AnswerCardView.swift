import SwiftUI

struct RelayAnswerPresentation {
    var lead:String
    var points:[String]
    var detail:String?
    var language:String?
    var isCode=false
}
struct AnswerCardView:View {
    let answer:RelayAnswerPresentation
    @Binding var expanded:Bool
    var surfaceIdentity:LearningAnswerSurfaceIdentity?
    var attachSurface:(@MainActor (LearningAnswerSurfaceView)->Void)?
    var body:some View {
        VStack(alignment:.leading,spacing:16){
            VStack(alignment:.leading,spacing:16){
                Text(answer.lead).font(.system(size:14,weight:.medium)).lineSpacing(7).fixedSize(horizontal:false,vertical:true)
                ForEach(Array(answer.points.prefix(2).enumerated()),id:\.offset){_,point in HStack(alignment:.top,spacing:10){Text("•").foregroundStyle(RelayTheme.muted);Text(point).lineSpacing(5)}.font(.system(size:14)).foregroundStyle(RelayTheme.secondary)}
            }.frame(maxWidth:.infinity,alignment:.leading).background{
                if let surfaceIdentity,let attachSurface{LearningAnswerSurfaceAttachment(identity:surfaceIdentity,changed:attachSurface).accessibilityHidden(true)}
            }
            if let detail=answer.detail {
                if expanded {
                    VStack(alignment:.leading,spacing:10){
                        HStack{Text(answer.language?.uppercased() ?? "DETAIL").font(.system(size:10,weight:.semibold)).tracking(1).foregroundStyle(RelayTheme.muted);Spacer();Button("Hide detail"){expanded=false}.buttonStyle(.plain).font(.system(size:11)).foregroundStyle(RelayTheme.muted)}
                        ScrollView(.horizontal){Text(detail).font(.system(size:13,design:answer.isCode ? .monospaced:.default)).lineSpacing(4).fixedSize(horizontal:false,vertical:true).frame(maxWidth:.infinity,alignment:.leading)}
                    }.padding(14).background(.black.opacity(0.18),in:RoundedRectangle(cornerRadius:10))
                }else{Button{expanded=true}label:{Label(answer.isCode ? "Code and detail":"More detail",systemImage:"chevron.down")}.buttonStyle(RelayQuietButtonStyle())}
            }
        }.frame(maxWidth:.infinity,alignment:.leading).textSelection(.enabled)
    }
}
