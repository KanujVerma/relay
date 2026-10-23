import SwiftUI
import UniformTypeIdentifiers

@MainActor public struct ProfilePreparationView: View {
    @ObservedObject private var controller: ProfileController
    @State private var role = "developer"
    @State private var purpose = "resume"
    @State private var label = "Selected résumé"
    @State private var project = ""
    @State private var enteredText = ""
    @State private var selectingFile = false
    @State private var actor = "unknown"
    @State private var topic = ""
    @State private var replaceExisting = false

    public init(controller: ProfileController) { self.controller = controller }

    private var claimKey: String {
        topic.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: ".", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Prepare your interview context").font(.title2.bold())
                Text("Review your résumé, project notes and job context once before the interview. Only approved facts support personal talking points.")
                    .foregroundStyle(.secondary)
                if !controller.opened {
                    Button("Open protected profile") { Task { await controller.openProfile() } }
                        .buttonStyle(.borderedProminent)
                    Text("Opening may ask macOS for access to Relay's profile key. No files are selected automatically.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    GroupBox("Add selected context") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                TextField("Interview role", text: $role)
                                Picker("Source", selection: $purpose) {
                                    Text("Résumé").tag("resume")
                                    Text("Project notes").tag("project")
                                    Text("Job description").tag("job")
                                }.frame(width: 235)
                            }
                            HStack {
                                TextField("Label for this source", text: $label)
                                TextField("Project (optional)", text: $project)
                            }
                            Button("Choose a TXT, PDF or DOCX file") { selectingFile = true }
                                .disabled(role.trimmingCharacters(in: .whitespaces).isEmpty || label.isEmpty)
                            Text("Or enter project notes or a job excerpt:").font(.caption)
                            TextEditor(text: $enteredText).frame(minHeight: 75, maxHeight: 130)
                                .border(Color.secondary.opacity(0.25))
                            Button("Add for review") {
                                let selected = enteredText
                                Task {
                                    await controller.stageEnteredText(selected, purpose: purpose, label: label,
                                                                       role: role, project: project.isEmpty ? nil : project)
                                    if controller.errorStatus == nil { enteredText = "" }
                                }
                            }.disabled(enteredText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || role.isEmpty || label.isEmpty)
                            Text("PDFs need selectable text. Simple DOCX paragraphs are supported; unsupported layouts stop for review. Job excerpts are limited to 4,000 characters.")
                                .font(.caption).foregroundStyle(.secondary)
                        }.padding(6)
                    }
                    if let card = controller.card {
                        GroupBox("Review a source-backed fact (\(controller.pendingCount) remaining)") {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(card.snippet).textSelection(.enabled).font(.body)
                                Text("Original source characters \(card.spanStart) to \(card.spanEnd), revision \(card.reviewRevision). Source fingerprint \(card.sourceSHA256.prefix(12)).")
                                    .font(.caption).foregroundStyle(.secondary)
                                Picker("Whose contribution is described?", selection: $actor) {
                                    Text("Choose ownership").tag("unknown")
                                    Text("My own").tag("self")
                                    Text("Our team").tag("team")
                                    Text("A teammate").tag("teammate")
                                }
                                TextField("Fact topic, e.g. Atlas storage choice", text: $topic)
                                Button("Check for an earlier fact on this topic") {
                                    Task { await controller.lookupExisting(claimKey: claimKey) }
                                }.disabled(claimKey.isEmpty)
                                if let earlier = controller.existingFact {
                                    Text("Earlier approved fact: \(earlier.claimText)").font(.callout)
                                    Toggle("Replace this earlier fact with the reviewed statement", isOn: $replaceExisting)
                                }
                                HStack {
                                    Button("Reject") { Task { await controller.reject(card) } }
                                    Spacer()
                                    Button("Approve fact") {
                                        Task {
                                            await controller.review(card, actor: actor, claimKey: claimKey,
                                                replaces: replaceExisting ? controller.existingFact : nil)
                                        }
                                    }.buttonStyle(.borderedProminent)
                                        .disabled(actor == "unknown" || claimKey.isEmpty || claimKey.count > 160 ||
                                            (controller.existingFact != nil && !replaceExisting))
                                }
                                Text("Team or teammate statements cannot become claims about your own work. Add a corrected source statement when ownership needs to change.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }.padding(6)
                        }.id(card.factID)
                    } else if let job = controller.job {
                        GroupBox("Review job context") {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(job.text).textSelection(.enabled)
                                Text("This describes the role. It does not verify your skills or experience.")
                                    .font(.caption).foregroundStyle(.secondary)
                                Button("Use this job context") { Task { await controller.approveJob(job) } }
                                    .buttonStyle(.borderedProminent)
                            }.padding(6)
                        }
                    } else {
                        Text("No facts are waiting for review.").foregroundStyle(.secondary)
                    }
                    if !controller.sources.isEmpty {
                        GroupBox("Selected sources") {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(controller.sources) { source in
                                    HStack {
                                        Text(source.label)
                                        Spacer()
                                        Button("Revoke") { Task { await controller.revoke(source) } }
                                    }
                                }
                                Text("Revoking a source retires its dependent facts. It does not erase backups or filesystem snapshots.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }.padding(6)
                        }
                    }
                    Button("Lock profile") { Task { await controller.close() } }
                }
                if let error = controller.errorStatus { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                if controller.busy { ProgressView("Updating protected profile…") }
            }.padding(24)
        }
        .disabled(controller.busy)
        .frame(minWidth: 740, minHeight: 620)
        .onChange(of: controller.card?.factID) { _, _ in
            actor = "unknown"; topic = ""; replaceExisting = false
        }
        .onChange(of: topic) { _, _ in replaceExisting = false }
        .fileImporter(isPresented: $selectingFile,
            allowedContentTypes: [.plainText, .pdf, UTType(filenameExtension: "docx") ?? .data],
            allowsMultipleSelection: false) { result in
                if case .success(let urls) = result, let url = urls.first {
                    Task { await controller.stageSelectedFile(url, purpose: purpose, label: label,
                                                             role: role, project: project.isEmpty ? nil : project) }
                }
            }
    }
}
