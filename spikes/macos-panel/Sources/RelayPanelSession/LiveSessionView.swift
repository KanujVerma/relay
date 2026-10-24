import SwiftUI
import AppKit
import RelaySessionPanel

/// Current accepted content and app-owned typed/transcript controls.
struct LiveSessionView:View {
    let state:RelaySessionPresentation
    var question:String?
    var answer:RelayAnswerPresentation?
    var status="Listening"
    var contextLabel="Screen off"
    var contextDetail:String?
    var error:String?
    var elapsed:String?
    var fixture=false
    var assistant:TypedAssistantController?
    var guideLabel:String?
    var onResponsePreferences:(()->Void)?
    var learningExplanation:String?
    var onLearningSettings:(()->Void)?
    var attachScroll:(@MainActor (NSWindow,NSScrollView?)->Void)?
    @Binding var expanded:Bool
    @Binding var detailExpanded:Bool
    let onAction:(RelayUIAction)->Void
    var body:some View {
        VStack(spacing:10){
            SessionToolbar(state:state,elapsed:elapsed,expanded:expanded,onExpand:{expanded.toggle();if !expanded{detailExpanded=false}},onAction:onAction)
            if expanded {
                VStack(spacing:0){
                    HStack(spacing:8){Image(systemName:"sparkles").foregroundStyle(RelayTheme.muted);Text("Live assistance").font(.system(size:13,weight:.semibold));Spacer();if let guideLabel,let onResponsePreferences{ResponseGuideButton(name:guideLabel,action:onResponsePreferences)};if fixture{Text("SYNTHETIC DEMO").font(.system(size:10,weight:.medium)).foregroundStyle(RelayTheme.muted)};RelayIconButton(title:"My Context",symbol:"person.text.rectangle",enabled:!fixture){onAction(.context)};RelayIconButton(title:"Settings",symbol:"gearshape"){onAction(.settings)};RelayIconButton(title:"Hide Relay window",symbol:"minus"){onAction(.hide)}}.padding(.horizontal,12).frame(height:56)
                    Divider().overlay(RelayTheme.line)
                    if let assistant{AssistantComposerView(assistant:assistant);Divider().overlay(RelayTheme.line)}
                    ScrollView{
                        VStack(alignment:.leading,spacing:22){
                            if let question,state.running || state.assistantActive {
                                HStack{Spacer(minLength:60);VStack(alignment:.leading,spacing:6){Text("CURRENT QUESTION").font(.system(size:10,weight:.semibold)).tracking(1).foregroundStyle(RelayTheme.muted);Text(question).font(.system(size:13,weight:.medium)).lineSpacing(5).textSelection(.enabled)}.padding(.horizontal,14).padding(.vertical,10).frame(maxWidth:530,alignment:.leading).background(.white.opacity(0.065),in:UnevenRoundedRectangle(topLeadingRadius:17,bottomLeadingRadius:17,bottomTrailingRadius:6,topTrailingRadius:17))}
                            }
                            if let answer,state.running || state.assistantActive{
                                AnswerCardView(answer:answer,expanded:$detailExpanded)
                                if let learningExplanation,let onLearningSettings{
                                    HStack(alignment:.top){Text(learningExplanation).font(.system(size:11)).foregroundStyle(RelayTheme.muted);Spacer(minLength:10);Button("Why this response",action:onLearningSettings).buttonStyle(.plain).font(.system(size:11)).foregroundStyle(RelayTheme.secondary)}
                                }
                            }
                            else{emptyContent}
                            if let error{Label(error,systemImage:"exclamationmark.circle").font(.system(size:12)).foregroundStyle(.orange).fixedSize(horizontal:false,vertical:true)}
                        }.padding(.horizontal,18).padding(.top,12).padding(.bottom,18).frame(maxWidth:.infinity,alignment:.leading)
                            .background{if let attachScroll{SessionWindowAttachment(resolve:attachScroll)}}
                    }.frame(maxHeight:.infinity)
                    Divider().overlay(RelayTheme.line)
                    HStack{
                        ContextStatusView(label:contextLabel,detail:contextDetail,onSettings:{onAction(.settings)})
                        Spacer()
                        Text(state.paused ? "Fresh conversation on resume":status).font(.system(size:11)).foregroundStyle(RelayTheme.muted).lineLimit(1)
                        Spacer()
                        RelayIconButton(title:"Copy current answer",symbol:"doc.on.doc",enabled:state.allows(.copy)){onAction(.copy)}
                        RelayIconButton(title:"Expand current answer detail",symbol:"arrow.up.left.and.arrow.down.right",enabled:state.allows(.expand)){onAction(.expand)}
                    }.padding(.horizontal,12).frame(height:48).background(.black.opacity(0.13))
                }.frame(width:RelayTheme.chatWidth,height:500).background(RelayTheme.raised,in:RoundedRectangle(cornerRadius:16)).overlay{RoundedRectangle(cornerRadius:16).strokeBorder(RelayTheme.line)}.shadow(color:.black.opacity(0.2),radius:16,y:6)
            }
        }.padding(8).foregroundStyle(.white).preferredColorScheme(.dark).frame(width:706)
    }
    @ViewBuilder private var emptyContent:some View {
        let message=RelayEmptyAnswerPresentation(state:state,status:status,hasQuestion:question != nil)
        VStack(alignment:.leading,spacing:12){
            Image(systemName:message.symbol).font(.system(size:26,weight:.light)).foregroundStyle(RelayTheme.muted)
            Text(message.title).font(.system(size:19,weight:.medium))
            Text(message.detail).font(.system(size:13)).lineSpacing(5).foregroundStyle(RelayTheme.muted)
            if let action=message.recoveryAction{Button("Connect ChatGPT"){onAction(action)}.buttonStyle(RelayPrimaryButtonStyle())}
        }.padding(.vertical,26).frame(maxWidth:.infinity,alignment:.leading)
    }
}
