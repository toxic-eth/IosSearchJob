import SwiftUI

private enum ModerationFilter: String, CaseIterable, Identifiable {
    case openOnly
    case inReviewOnly
    case allOpenQueue

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openOnly:
            return "Відкриті"
        case .inReviewOnly:
            return "В роботі"
        case .allOpenQueue:
            return "Черга"
        }
    }
}

private enum ModerationQueueScope: String, CaseIterable, Identifiable {
    case myQueue
    case allQueue

    var id: String { rawValue }

    var title: String {
        switch self {
        case .myQueue:
            return "Моя черга"
        case .allQueue:
            return "Уся черга"
        }
    }
}

struct ModerationView: View {
    @EnvironmentObject private var appState: AppState

    @State private var selectedFilter: ModerationFilter = .allOpenQueue
    @State private var queueScope: ModerationQueueScope = .myQueue
    @State private var noteByCaseId: [UUID: String] = [:]
    @State private var assigneeByCaseId: [UUID: UUID?] = [:]
    @State private var roleDraftByUserId: [UUID: ModerationRole] = [:]

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackgroundView()

                if canModerate {
                    ScrollView {
                        VStack(spacing: 12) {
                            teamCard
                            summaryCard
                            scopePicker
                            filterPicker
                            queueCard
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 20)
                    }
                } else {
                    AppStateBanner(
                        title: "Немає доступу",
                        message: "Доступ до модерації мають лише призначені модератори.",
                        tone: .warning
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }
            }
            .navigationTitle("Модерація")
        }
    }

    private var canModerate: Bool {
        appState.currentUserCanAccessModeration()
    }

    private var queue: [ModerationCase] {
        let cases = appState.moderationQueueOpenCases()
        let base: [ModerationCase]
        if queueScope == .myQueue, let currentUser = appState.currentUser {
            base = cases.filter { $0.assignedModeratorId == currentUser.id || ($0.status == .open && $0.assignedModeratorId == nil) }
        } else {
            base = cases
        }
        switch selectedFilter {
        case .openOnly:
            return base.filter { $0.status == .open }
        case .inReviewOnly:
            return base.filter { $0.status == .inReview }
        case .allOpenQueue:
            return base
        }
    }

    private var summaryCard: some View {
        let openCount = appState.moderationQueueOpenCases().filter { $0.status == .open }.count
        let inReviewCount = appState.moderationQueueOpenCases().filter { $0.status == .inReview }.count
        let overdueCount = appState.moderationQueueOpenCases().filter { appState.moderationIsOverdue($0) }.count

        return HStack(spacing: 8) {
            metric("Open", "\(openCount)", .purple)
            metric("In review", "\(inReviewCount)", .blue)
            metric("SLA risk", "\(overdueCount)", .orange)
        }
        .glassCard()
    }

    @ViewBuilder
    private var teamCard: some View {
        if appState.currentUserCanManageModerators() {
            let employers = appState.users
                .filter { $0.role == .employer }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            VStack(alignment: .leading, spacing: 10) {
                Text("Команда модерації")
                    .font(.headline)
                    .foregroundStyle(.primary)

                ForEach(employers) { employer in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(employer.name)
                                .font(.caption.bold())
                            Text("Поточна роль: \(employer.moderationRole.title)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Picker(
                            "Роль",
                            selection: Binding(
                                get: { roleDraftByUserId[employer.id] ?? employer.moderationRole },
                                set: { roleDraftByUserId[employer.id] = $0 }
                            )
                        ) {
                            ForEach(ModerationRole.allCases, id: \.rawValue) { role in
                                Text(role.title).tag(role)
                            }
                        }
                        .pickerStyle(.menu)
                        .font(.caption)

                        Button("Ок") {
                            _ = appState.assignModerationRole(
                                userId: employer.id,
                                role: roleDraftByUserId[employer.id] ?? employer.moderationRole
                            )
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)
                    }
                    .padding(8)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
        }
    }

    private var scopePicker: some View {
        Picker("Черга", selection: $queueScope) {
            ForEach(ModerationQueueScope.allCases) { item in
                Text(item.title).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .glassCard()
    }

    private func metric(_ title: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(tint)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var filterPicker: some View {
        Picker("Фільтр", selection: $selectedFilter) {
            ForEach(ModerationFilter.allCases) { item in
                Text(item.title).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .glassCard()
    }

    private var queueCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Черга кейсів")
                .font(.headline)
                .foregroundStyle(.primary)

            if queue.isEmpty {
                Text("Немає кейсів за поточним фільтром")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(queue) { item in
                    caseRow(item)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func caseRow(_ item: ModerationCase) -> some View {
        let overdue = appState.moderationIsOverdue(item)
        let age = appState.moderationAgeHours(item)
        let sla = appState.moderationSLAHours(for: item.type)
        let history = appState.moderationActions(for: item.id, limit: 4)
        let canAssign = appState.currentUserCanAssignModeration()

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(item.type.title) • \(item.subject)")
                    .font(.caption.bold())
                Spacer()
                AppStatusPill(title: item.status.title, tone: overdue ? .warning : .info)
            }

            Text(item.details)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text("Відповідальний: \(appState.moderationCaseAssigneeName(item))")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack {
                Text("Age: \(age)h")
                Text("SLA: \(sla)h")
                if overdue { Text("SLA breached") }
            }
            .font(.caption2)
            .foregroundStyle(overdue ? .orange : .secondary)

            if overdue {
                AppStateBanner(
                    title: "SLA risk",
                    message: "Кейс перевищив SLA, рекомендовано пріоритетний розгляд.",
                    tone: .warning
                )
            }

            if canAssign {
                HStack(spacing: 8) {
                    Picker(
                        "Призначити",
                        selection: Binding(
                            get: { assigneeByCaseId[item.id] ?? item.assignedModeratorId },
                            set: { assigneeByCaseId[item.id] = $0 }
                        )
                    ) {
                        Text("Без агента").tag(Optional<UUID>.none)
                        ForEach(appState.moderationAgents()) { moderator in
                            Text(moderator.name).tag(Optional(moderator.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .font(.caption)

                    Button("Оновити") {
                        _ = appState.assignModerationCase(caseId: item.id, to: assigneeByCaseId[item.id] ?? item.assignedModeratorId)
                    }
                    .buttonStyle(.bordered)
                    .font(.caption)
                }
            }

            if item.status == .open {
                Button("Взяти в роботу") {
                    _ = appState.assignModerationCase(caseId: item.id, to: appState.currentUser?.id)
                    _ = appState.startModerationReview(caseId: item.id)
                }
                .buttonStyle(.bordered)
            }

            TextField(
                "Коментар модератора",
                text: Binding(
                    get: { noteByCaseId[item.id] ?? "" },
                    set: { noteByCaseId[item.id] = $0 }
                )
            )
            .textFieldStyle(.roundedBorder)
            .disabled(!appState.currentUserCanAccessModeration())

            HStack(spacing: 8) {
                Button("Схвалити") {
                    let note = noteByCaseId[item.id] ?? "Схвалено модерацією"
                    _ = appState.processModerationCase(caseId: item.id, approve: true, note: note)
                    noteByCaseId[item.id] = ""
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(!canResolve(item))

                Button("Відхилити") {
                    let note = noteByCaseId[item.id] ?? "Відхилено модерацією"
                    _ = appState.processModerationCase(caseId: item.id, approve: false, note: note)
                    noteByCaseId[item.id] = ""
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .disabled(!canResolve(item))
            }

            if !history.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Історія")
                        .font(.caption.bold())
                    ForEach(history) { action in
                        Text(historyLine(for: action))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func canResolve(_ item: ModerationCase) -> Bool {
        guard let currentUser = appState.currentUser else { return false }
        if currentUser.moderationRole.canResolveAnyCase { return true }
        return item.assignedModeratorId == currentUser.id
    }

    private func historyLine(for action: ModerationCaseAction) -> String {
        let actor = action.actorUserId.flatMap { id in
            appState.users.first(where: { $0.id == id })?.name
        } ?? "System"
        return "\(action.type.title): \(actor) • \(action.note)"
    }
}
