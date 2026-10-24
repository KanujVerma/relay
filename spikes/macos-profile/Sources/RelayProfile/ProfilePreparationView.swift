import SwiftUI
import UniformTypeIdentifiers

@MainActor public struct ProfilePreparationView: View {
    @ObservedObject private var controller: ProfileController
    @State private var role: String
    private let boundRole: Bool
    private let sessionUse: SessionContextUseSnapshot?
    private let actions: ProfilePreparationActions
    @State private var purpose = "resume"
    @State private var label = "My résumé"
    @State private var project = ""
    @State private var enteredText = ""
    @State private var selectingFile = false
    @State private var addingNotes = false
    @State private var importOptionsExpanded = false
    @State private var sourceDetailsExpanded = false
    @State private var reviewOptionsExpanded = false
    @State private var actor = "unknown"
    @State private var topic = ""
    @State private var replaceExisting = false
    @State private var lookupKey: String?
    @State private var selectedCorrection: ProfileMemoryFact?

    public init(controller: ProfileController, role: String? = nil,
                sessionUse: SessionContextUseSnapshot? = nil,
                onOpen: (@MainActor () -> Void)? = nil, onLock: (@MainActor () -> Void)? = nil) {
        self.controller = controller
        _role = State(initialValue: role ?? "developer")
        boundRole = role != nil
        self.sessionUse = sessionUse
        actions = ProfilePreparationActions(controller: controller, onOpen: onOpen, onLock: onLock)
    }

    private var claimKey: String {
        guard let card = controller.card else { return "" }
        return ProfileReviewPresentation.claimKey(sourceID: card.sourceID, factID: card.factID, topic: topic,
                                                   selectedClaimKey: selectedCorrection?.claimKey)
    }
    private var earlierFact: ProfileExistingFact? {
        guard lookupKey == claimKey, controller.existingClaimKey == claimKey,
              let fact = controller.existingFact else { return nil }
        guard selectedCorrection == nil || fact.factID == selectedCorrection?.factID else { return nil }
        return fact
    }
    private var busyMessage: String {
        if let sessionUse, sessionUse.isBusy { return sessionUse.message }
        return "Updating your context…"
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("My Context").font(.system(size: 26, weight: .semibold))
                        Text("Your résumé, projects and experience, ready when questions come up.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if actions.canLock(sessionUse: sessionUse) {
                        Button { actions.lock() } label: {
                            Label("Lock", systemImage: "lock")
                        }.help("Lock your saved context and turn off its use in sessions")
                    }
                }
                Group {
                    if controller.opened { contextWorkspace }
                    else { lockedWorkspace }
                }.disabled(controller.busy || sessionUse?.isBusy == true)
                if controller.busy || sessionUse?.isBusy == true {
                    ProgressView(busyMessage).controlSize(.small)
                }
                if let sessionUse, !sessionUse.isBusy {
                    Text(sessionUse.message).font(.callout).foregroundStyle(.secondary)
                }
                if sessionUse != nil {
                    Text("Opening My Context enables your saved background in future sessions. Lock turns that off.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error = controller.errorStatus {
                    Label(error, systemImage: "exclamationmark.circle").font(.callout)
                        .foregroundStyle(.red).textSelection(.enabled)
                }
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 480, minHeight: 500)
        .onChange(of: controller.card?.factID) { _, _ in
            actor = "unknown"; topic = ""; replaceExisting = false; lookupKey = nil
            selectedCorrection = nil
            sourceDetailsExpanded = false; reviewOptionsExpanded = false
        }
        .onChange(of: topic) { _, _ in
            guard selectedCorrection == nil else { return }
            replaceExisting = false
            if lookupKey != claimKey { lookupKey = nil }
        }
        .fileImporter(isPresented: $selectingFile,
            allowedContentTypes: [.plainText, .pdf, UTType(filenameExtension: "docx") ?? .data],
            allowsMultipleSelection: false) { result in
                guard case .success(let urls) = result, let url = urls.first else { return }
                let selectedPurpose = purpose, selectedRole = role
                let selectedProject = project.isEmpty ? nil : project
                let name = String(url.deletingPathExtension().lastPathComponent.prefix(64))
                let selectedLabel = name.isEmpty ? label : name
                label = selectedLabel
                Task {
                    await controller.stageSelectedFile(url, purpose: selectedPurpose, label: selectedLabel,
                                                       role: selectedRole, project: selectedProject)
                }
            }
    }

    private var lockedWorkspace: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.rectangle.stack").font(.system(size: 38, weight: .light))
                .foregroundStyle(.secondary)
            Text("Make Relay familiar with your background").font(.title3.weight(.semibold))
            Text("Add a résumé or project notes, then choose what to remember. Your context is protected on this Mac.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 400)
            Button("Open My Context") { actions.open() }
                .buttonStyle(.borderedProminent).controlSize(.large)
            Text("macOS may ask for access to Relay’s profile key.")
                .font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, minHeight: 290).padding(24)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 16))
    }

    private var contextWorkspace: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 10) {
                Button { chooseFile("resume") } label: { Label("Add résumé", systemImage: "doc.badge.plus") }
                    .buttonStyle(.borderedProminent)
                Menu {
                    Button("Upload project notes") { chooseFile("project") }
                    Button("Upload a job description") { chooseFile("job") }
                    Divider()
                    Button("Write project notes") { beginNotes("project") }
                    Button("Paste a job description") { beginNotes("job") }
                } label: { Label("Add context", systemImage: "plus") }
                Spacer()
                if controller.pendingCount > 0 {
                    Text("\(controller.pendingCount) to review").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                } else {
                    Text("\(controller.memoryCount) saved facts").font(.caption).foregroundStyle(.secondary)
                }
            }
            if addingNotes { notesComposer }
            if let card = controller.card { review(card) }
            else if let job = controller.job { reviewJob(job) }
            else {
                Text(controller.sources.isEmpty ? "Add a résumé to get started, or bring in notes about a project or role." : "Your sources are saved. Add more context whenever you need it.")
                    .font(.callout).foregroundStyle(.secondary).padding(.vertical, 12)
            }
            if controller.memoryCount > 0 { savedMemories }
            if !controller.sources.isEmpty { sourcesList }
            Text("Saved background stays separate from conversation transcripts and AI suggestions.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func chooseFile(_ selectedPurpose: String) {
        purpose = selectedPurpose; label = defaultLabel(selectedPurpose)
        addingNotes = false; selectingFile = true
    }
    private func beginNotes(_ selectedPurpose: String) {
        purpose = selectedPurpose; label = defaultLabel(selectedPurpose); addingNotes = true
    }
    private func defaultLabel(_ selectedPurpose: String) -> String {
        selectedPurpose == "resume" ? "My résumé" : selectedPurpose == "job" ? "Job description" : "Project notes"
    }

    private var notesComposer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(purpose == "job" ? "Job description" : "Project notes").font(.headline)
            TextEditor(text: $enteredText).font(.body).frame(minHeight: 110, maxHeight: 180)
                .padding(8).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
            DisclosureGroup("More options", isExpanded: $importOptionsExpanded) {
                VStack(spacing: 10) {
                    TextField("Source name", text: $label)
                    TextField("Project (optional)", text: $project)
                    if !boundRole { TextField("Interview role", text: $role) }
                }.textFieldStyle(.roundedBorder).padding(.top, 10)
            }.font(.callout)
            HStack {
                Button("Cancel") { addingNotes = false }
                Spacer()
                Button("Review this context") {
                    let text = enteredText, selectedPurpose = purpose, selectedLabel = label, selectedRole = role
                    let selectedProject = project.isEmpty ? nil : project
                    Task {
                        await controller.stageEnteredText(text, purpose: selectedPurpose, label: selectedLabel,
                                                          role: selectedRole, project: selectedProject)
                        if controller.opened && controller.errorStatus == nil { enteredText = ""; addingNotes = false }
                    }
                }.buttonStyle(.borderedProminent)
                    .disabled(enteredText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || role.isEmpty || label.isEmpty)
            }
            Text("Use selectable-text PDFs or simple DOCX files. Job excerpts can contain up to 4,000 characters.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(18).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
    }

    private func review(_ card: ProfileReviewCard) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Choose what Relay remembers", systemImage: "sparkle").font(.headline)
            Text(card.snippet).font(.system(size: 16)).textSelection(.enabled)
            Picker("Whose work is this?", selection: $actor) {
                Text("Choose ownership").tag("unknown")
                Text("My own work").tag("self")
                Text("Our team’s work").tag("team")
                Text("A teammate’s work").tag("teammate")
            }.frame(maxWidth: 380, alignment: .leading)
            Text("Only information you approve supports personal suggestions.")
                .font(.caption).foregroundStyle(.secondary)
            DisclosureGroup("Source details", isExpanded: $sourceDetailsExpanded) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(card.locator ?? "Selected source")
                    Text("Characters \(card.spanStart)–\(card.spanEnd) · revision \(card.reviewRevision)")
                    Text("Fingerprint: \(card.sourceSHA256)").textSelection(.enabled)
                    Text("Source ownership hint: \(card.actorHint). Your selection above determines ownership.")
                }.font(.caption).foregroundStyle(.secondary).padding(.top, 8)
            }.font(.callout)
            DisclosureGroup("Correct an earlier fact", isExpanded: $reviewOptionsExpanded) {
                VStack(alignment: .leading, spacing: 10) {
                    if let selectedCorrection {
                        Text("Selected saved fact from \(selectedCorrection.sourceLabel)").font(.callout)
                        Button("Clear selection") {
                            self.selectedCorrection = nil; lookupKey = nil; replaceExisting = false; topic = ""
                        }
                    } else {
                        Text("Select a saved fact below, or enter an earlier topic. Leave it blank for a new source-backed fact.")
                            .font(.caption).foregroundStyle(.secondary)
                        TextField("Memory topic (optional)", text: $topic).textFieldStyle(.roundedBorder)
                        Button("Find earlier fact") {
                            let key = claimKey; lookupKey = key
                            Task { await controller.lookupExisting(claimKey: key) }
                        }.disabled(topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    if let earlier = earlierFact {
                        Text(earlier.claimText).font(.callout)
                        Toggle("Replace this earlier fact", isOn: $replaceExisting)
                    } else if selectedCorrection != nil && !controller.busy {
                        Text("This saved fact could not be matched. Clear the selection or choose a current fact below.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.top, 10)
            }.font(.callout)
            HStack {
                Button("Skip this fact") { Task { await controller.reject(card) } }
                Spacer()
                Button("Save to memory") {
                    let selectedActor = actor, selectedKey = claimKey
                    let replacement = replaceExisting ? earlierFact : nil
                    Task { await controller.review(card, actor: selectedActor, claimKey: selectedKey, replaces: replacement) }
                }.buttonStyle(.borderedProminent)
                    .disabled(!ProfileReviewPresentation.canApprove(actor: actor, claimKey: claimKey,
                        hasExisting: earlierFact != nil, replacesExisting: replaceExisting,
                        requiresExisting: selectedCorrection != nil))
            }
        }.padding(20).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12)).id(card.factID)
    }

    private func reviewJob(_ job: ProfileJobCard) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Review the role", systemImage: "briefcase").font(.headline)
            Text(job.text).textSelection(.enabled)
            Text("This helps tailor suggestions to the role. It does not become a claim about your experience.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Use this job context") { Task { await controller.approveJob(job) } }
                .buttonStyle(.borderedProminent)
        }.padding(20).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
    }

    private var sourcesList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            Text("Your sources").font(.headline)
            ForEach(controller.sources) { source in
                HStack(spacing: 12) {
                    Image(systemName: source.purpose == "job" ? "briefcase" : "doc.text").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(source.label).font(.callout.weight(.medium))
                        Text(defaultLabel(source.purpose)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Remove from Relay") { Task { await controller.revoke(source) } }.font(.caption)
                }.padding(.vertical, 5)
            }
            Text("Removing a source retires its facts from future suggestions. Backups and filesystem snapshots are separate.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var savedMemories: some View {
        VStack(alignment: .leading, spacing: 14) {
            Divider()
            HStack {
                Text("My memory").font(.headline)
                Spacer()
                Text("\(controller.memoryCount) reviewed facts").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(controller.memories) { memory in
                VStack(alignment: .leading, spacing: 8) {
                    Text(memory.claimText).font(.callout).textSelection(.enabled)
                    HStack {
                        Text(memory.actor == "self" ? "My work" : memory.actor == "team" ? "Our team’s work" : "A teammate’s work")
                        Text("·")
                        Text(memory.sourceLabel)
                        Spacer()
                        if controller.card != nil {
                            Button("Correct this fact") {
                                selectedCorrection = memory; lookupKey = memory.claimKey
                                replaceExisting = false; reviewOptionsExpanded = true
                                Task { await controller.lookupExisting(claimKey: memory.claimKey) }
                            }.help("Compare the pending statement with this saved fact before replacing it")
                        }
                    }.font(.caption).foregroundStyle(.secondary)
                    if earlierFact?.factID == memory.factID {
                        Text("Selected for correction. Compare both statements above and confirm the replacement.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(14).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
            }
            if controller.canLoadMoreMemories {
                Button("Show more memory") { Task { await controller.loadMoreMemories() } }
            }
        }
    }
}
