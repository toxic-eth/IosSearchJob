import SwiftUI
import MapKit

private enum DiscoveryMode: String, CaseIterable, Identifiable {
    case list
    case map

    var id: String { rawValue }

    func title(_ language: AppLanguage) -> String {
        switch self {
        case .list:
            return I18n.t("mode.list", language)
        case .map:
            return I18n.t("mode.map", language)
        }
    }
}

private enum WorkFormatFilter: String, CaseIterable, Identifiable {
    case all
    case online
    case offline

    var id: String { rawValue }

    func title(_ language: AppLanguage) -> String {
        switch self {
        case .all:
            return I18n.t("format.all", language)
        case .online:
            return I18n.t("format.online", language)
        case .offline:
            return I18n.t("format.offline", language)
        }
    }
}

private enum MapDimensionMode {
    case twoD
    case threeD
}

private struct CityOption: Identifiable {
    let id = UUID()
    let name: String
    let coordinate: CLLocationCoordinate2D
    let latitudeDelta: Double
    let longitudeDelta: Double
    let radiusKm: Double
}

struct MainMapView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var locationService: LocationService
    @AppStorage("appTheme") private var appThemeRawValue = AppTheme.dark.rawValue
    @AppStorage("appLanguage") private var appLanguageRawValue = AppLanguage.uk.rawValue

    @State private var discoveryMode: DiscoveryMode = .map
    @State private var searchText = ""
    @State private var minPay: Double = 80
    @State private var maxDuration: Double = 12
    @State private var maxDistanceKm: Double = 20
    @State private var useDateTimeFilter = false
    @State private var desiredDate = Date()
    @State private var desiredFromTime = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var desiredToTime = Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var verifiedOnly = false
    @State private var workFormatFilter: WorkFormatFilter = .all
    @State private var selectedShift: JobShift?
    @State private var focusedShiftOnMap: JobShift?
    @State private var sheetVisibleFraction: CGFloat = 0.5
    @State private var centeredCarouselShiftId: UUID?
    @State private var routeDistanceKmByShift: [UUID: Double] = [:]
    @State private var routeDistanceTask: Task<Void, Never>?
    @State private var lastRouteOrigin: CLLocationCoordinate2D?
    @State private var showCreateShift = false
    @State private var showFiltersSheet = false
    @State private var selectedCity = Self.cityOptions[0]
    @State private var skipCityAutoCenter = false
    @State private var mapDimensionMode: MapDimensionMode = .twoD
    @State private var mapHeading: CLLocationDirection = 0
    @State private var mapPitch: CGFloat = 0
    @State private var mapZoom: CGFloat = 11.8
    @State private var mapCenterCoordinate = Self.cityOptions[0].coordinate
    @State private var isDrawingArea = false
    @State private var drawingPoints: [CGPoint] = []
    @State private var drawnAreaCoordinates: [CLLocationCoordinate2D] = []
    @State private var drawPointsToConvert: [CGPoint] = []
    @State private var mapboxCameraUpdate: MapboxCameraUpdate?

    private static let cityOptions: [CityOption] = [
        CityOption(name: "Київ", coordinate: CLLocationCoordinate2D(latitude: 50.4501, longitude: 30.5234), latitudeDelta: 0.16, longitudeDelta: 0.16, radiusKm: 35),
        CityOption(name: "Львів", coordinate: CLLocationCoordinate2D(latitude: 49.8397, longitude: 24.0297), latitudeDelta: 0.15, longitudeDelta: 0.15, radiusKm: 28),
        CityOption(name: "Одеса", coordinate: CLLocationCoordinate2D(latitude: 46.4825, longitude: 30.7233), latitudeDelta: 0.18, longitudeDelta: 0.18, radiusKm: 30),
        CityOption(name: "Дніпро", coordinate: CLLocationCoordinate2D(latitude: 48.4647, longitude: 35.0462), latitudeDelta: 0.16, longitudeDelta: 0.16, radiusKm: 30),
        CityOption(name: "Харків", coordinate: CLLocationCoordinate2D(latitude: 49.9935, longitude: 36.2304), latitudeDelta: 0.18, longitudeDelta: 0.18, radiusKm: 32)
    ]

    private var filteredShifts: [JobShift] {
        let role = appState.currentUser?.role
        let isWorkerRole = role == .worker

        return appState.shifts
            .filter { shift in
                let visibleByStatus = isWorkerRole ? shift.status == .open : true
                let employer = appState.user(by: shift.employerId)
                let verifiedMatch = isWorkerRole ? (!verifiedOnly || (employer?.isVerifiedEmployer == true)) : true
                let textMatch = searchText.isEmpty || shift.title.localizedCaseInsensitiveContains(searchText) || shift.details.localizedCaseInsensitiveContains(searchText)
                let mapFormatMatch = discoveryMode == .map ? shift.workFormat == .offline : true

                return UkraineRegion.contains(shift.coordinate) &&
                    visibleByStatus &&
                    verifiedMatch &&
                    mapFormatMatch &&
                    matchesWorkFormat(shift.workFormat) &&
                    (isWorkerRole ? isWithinUserDistance(shift) : true) &&
                    matchesDrawnArea(shift.coordinate) &&
                    matchesDesiredDateTime(shift.startDate) &&
                    textMatch &&
                    Double(shift.pay) >= minPay &&
                    Double(shift.durationHours) <= maxDuration &&
                    isWithinSelectedCity(shift.coordinate)
            }
            .sorted { lhs, rhs in
                if isWorkerRole {
                    let lhsScore = shiftDiscoveryScore(lhs)
                    let rhsScore = shiftDiscoveryScore(rhs)
                    if abs(lhsScore - rhsScore) > 0.001 {
                        return lhsScore > rhsScore
                    }
                }
                return lhs.startDate < rhs.startDate
            }
    }

    private var upcomingCount: Int {
        filteredShifts.filter { $0.startDate > Date() }.count
    }

    private var unreadNotifications: Int {
        appState.unreadNotificationsCountForCurrentUser()
    }

    private var unreadChats: Int {
        appState.unreadChatCountForCurrentUser()
    }

    private var language: AppLanguage {
        resolvedLanguage(from: appLanguageRawValue)
    }

    private var isDarkTheme: Bool {
        resolvedTheme(from: appThemeRawValue) == .dark
    }

    private var palette: AppPalette {
        AppPalette.forTheme(resolvedTheme(from: appThemeRawValue))
    }

    private var primaryOnBackground: Color {
        palette.textPrimary
    }

    private var secondaryOnBackground: Color {
        palette.textSecondary
    }

    private var activeFiltersCount: Int {
        var count = 0
        if minPay > 80 { count += 1 }
        if maxDuration < 12 { count += 1 }
        if workFormatFilter != .all { count += 1 }
        if locationService.currentLocation != nil && maxDistanceKm < 20 { count += 1 }
        if useDateTimeFilter { count += 1 }
        if verifiedOnly { count += 1 }
        return count
    }

    var body: some View {
        let currentRole = appState.currentUser?.role
        TabView {
            dashboard
                .tabItem {
                    if currentRole == .employer {
                        Label("Публікації", systemImage: "briefcase")
                    } else {
                        Label(I18n.t("tab.shifts", language), systemImage: "map")
                    }
                }

            ActivityView()
                .tabItem {
                    if currentRole == .employer {
                        Label("Операції", systemImage: "chart.line.text.clipboard")
                    } else {
                        Label(I18n.t("tab.activity", language), systemImage: "list.bullet.clipboard")
                    }
                }

            CommunicationHubView()
                .tabItem {
                    Label("Комунікація", systemImage: "bubble.left.and.bubble.right")
                }
                .badge(unreadChats)

            if appState.currentUserCanAccessModeration() {
                ModerationView()
                    .tabItem {
                        Label("Модерація", systemImage: "shield.lefthalf.filled")
                    }
                    .badge(appState.moderationQueueOpenCases().count)
            }

            NotificationsView()
                .tabItem {
                    if currentRole == .employer {
                        Label("Сигнали", systemImage: "bell")
                    } else {
                        Label(I18n.t("tab.notifications", language), systemImage: "bell")
                    }
                }
                .badge(unreadNotifications)

            ProfileView()
                .tabItem {
                    Label(I18n.t("tab.profile", language), systemImage: "person.crop.circle")
                }
        }
        .tint(palette.accent)
    }

    private var dashboard: some View {
        NavigationStack {
            Group {
                if appState.currentUser?.role == .employer {
                    employerDashboard
                } else {
                    if discoveryMode == .map {
                        fullScreenMapMode
                    } else {
                        listMode
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $selectedShift) { shift in
                ShiftDetailView(shift: shift)
                    .environmentObject(appState)
                    .environmentObject(locationService)
            }
                .sheet(isPresented: $showCreateShift) {
                    AddShiftView(centerCoordinate: selectedCity.coordinate)
                        .environmentObject(appState)
                }
            .sheet(isPresented: $showFiltersSheet) {
                FiltersSheet(
                    language: language,
                    isWorker: appState.currentUser?.role == .worker,
                    canFilterByDistance: locationService.currentLocation != nil,
                    cityNames: Self.cityOptions.map(\.name),
                    selectedCityName: Binding(
                        get: { selectedCity.name },
                        set: { newValue in
                            if let matched = Self.cityOptions.first(where: { $0.name == newValue }) {
                                selectedCity = matched
                            }
                        }
                    ),
                    filteredCount: filteredShifts.count,
                    minPay: $minPay,
                    maxDuration: $maxDuration,
                    maxDistanceKm: $maxDistanceKm,
                    workFormatFilter: $workFormatFilter,
                    useDateTimeFilter: $useDateTimeFilter,
                    desiredDate: $desiredDate,
                    desiredFromTime: $desiredFromTime,
                    desiredToTime: $desiredToTime,
                    verifiedOnly: $verifiedOnly
                )
            }
            .onAppear {
                locationService.requestPermission()
                if appState.consumeLocationPermissionRequest() {
                    locationService.requestPermission()
                }
                centerOnSelectedCity(animated: false)
                refreshRouteDistances()
            }
            .onChange(of: selectedCity.name) { _, _ in
                if skipCityAutoCenter {
                    skipCityAutoCenter = false
                } else {
                    centerOnSelectedCity(animated: true)
                }
                refreshRouteDistances()
            }
            .onChange(of: locationService.currentLocation?.latitude) { _, _ in
                refreshRouteDistances()
            }
            .onChange(of: locationService.currentLocation?.longitude) { _, _ in
                refreshRouteDistances()
            }
        }
    }

    private var employerDashboard: some View {
        ZStack {
            AppBackgroundView()

            ScrollView {
                VStack(spacing: 12) {
                    employerSummaryCard
                    employerAnalyticsCard
                    employerPayoutQueueCard

                    Button {
                        showCreateShift = true
                    } label: {
                        Label("Створити вакансію", systemImage: "plus")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)

                    if employerShifts.isEmpty {
                        Text("У вас ще немає вакансій")
                            .font(.subheadline)
                            .foregroundStyle(secondaryOnBackground)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassCard()
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(employerShifts) { shift in
                                employerShiftRow(shift)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
    }

    private var employerShifts: [JobShift] {
        guard let currentUserId = appState.currentUser?.id else { return [] }
        return appState.shifts
            .filter { $0.employerId == currentUserId }
            .sorted { $0.startDate > $1.startDate }
    }

    private var employerSummaryCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("Мої вакансії")
                    .font(.caption)
                    .foregroundStyle(secondaryOnBackground)
                Text("\(employerShifts.count)")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(primaryOnBackground)
                Text("Активні та заплановані зміни")
                    .font(.footnote)
                    .foregroundStyle(secondaryOnBackground)
            }
            Spacer()
            Image(systemName: "person.3.sequence.fill")
                .font(.system(size: 30))
                .foregroundStyle(secondaryOnBackground)
        }
        .glassCard()
    }

    private var employerAnalyticsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Аналітика вакансій")
                .font(.headline)
                .foregroundStyle(primaryOnBackground)

            HStack(spacing: 8) {
                employerMetricTile(
                    title: "Відгуки",
                    value: "\(employerPendingApplications + employerAcceptedApplications + employerRejectedApplications)",
                    subtitle: "кандидатів у воронці",
                    tint: .purple
                )
                employerMetricTile(
                    title: "Fill Rate",
                    value: percentText(employerFillRate),
                    subtitle: "\(employerAcceptedApplications)/\(max(1, employerTotalSlots)) слотів",
                    tint: .green
                )
            }

            HStack(spacing: 8) {
                employerMetricTile(
                    title: "No-show",
                    value: "\(employerNoShowCount)",
                    subtitle: "завершені зміни без виходу",
                    tint: .orange
                )
                employerMetricTile(
                    title: "Виплачено",
                    value: "\(employerPaidCount)",
                    subtitle: "завершень зі статусом paid",
                    tint: .blue
                )
            }

            HStack(spacing: 12) {
                Label("Pending: \(employerPendingApplications)", systemImage: "clock")
                Label("Accepted: \(employerAcceptedApplications)", systemImage: "checkmark.circle")
                Label("Rejected: \(employerRejectedApplications)", systemImage: "xmark.circle")
            }
            .font(.caption)
            .foregroundStyle(secondaryOnBackground)
        }
        .glassCard()
    }

    private func employerMetricTile(title: String, value: String, subtitle: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(secondaryOnBackground)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(primaryOnBackground)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(secondaryOnBackground)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(tint.opacity(isDarkTheme ? 0.18 : 0.1), in: RoundedRectangle(cornerRadius: 14))
    }

    private var employerShiftIds: Set<UUID> {
        Set(employerShifts.map(\.id))
    }

    private var employerApplications: [ShiftApplication] {
        appState.applications.filter { employerShiftIds.contains($0.shiftId) }
    }

    private var employerPendingApplications: Int {
        employerApplications.filter { $0.status == .pending }.count
    }

    private var employerAcceptedApplications: Int {
        employerApplications.filter { $0.status == .accepted }.count
    }

    private var employerRejectedApplications: Int {
        employerApplications.filter { $0.status == .rejected }.count
    }

    private var employerTotalSlots: Int {
        max(1, employerShifts.reduce(0) { $0 + max(0, $1.requiredWorkers) })
    }

    private var employerFillRate: Double {
        let accepted = Double(employerAcceptedApplications)
        let slots = Double(employerTotalSlots)
        return min(1, max(0, accepted / slots))
    }

    private var employerNoShowCount: Int {
        employerApplications.filter { application in
            guard application.status == .accepted,
                  application.progressStatus == .scheduled,
                  let shift = appState.shift(by: application.shiftId) else { return false }
            return shift.endDate < Date()
        }.count
    }

    private var employerPaidCount: Int {
        employerApplications.filter { $0.status == .accepted && $0.progressStatus == .paid }.count
    }

    private func percentText(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func employerShiftRow(_ shift: JobShift) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(shift.title)
                    .font(.headline)
                Spacer()
                Text(shift.status.title)
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(shift.status == .open ? Color.purple.opacity(0.24) : Color.gray.opacity(0.22))
                    .clipShape(Capsule())
            }
            Text(shift.address)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Label("\(shift.pay) грн/год", systemImage: "dollarsign.circle")
                Label("\(appState.acceptedApplicationsCount(for: shift.id))/\(shift.requiredWorkers)", systemImage: "person.3")
                Text(shift.startDate.formatted(date: .abbreviated, time: .shortened))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var employerPayoutQueueCard: some View {
        let pending = appState.pendingPayoutsForCurrentEmployer()
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Черга виплат")
                    .font(.headline)
                    .foregroundStyle(primaryOnBackground)
                Spacer()
                Text("\(pending.count)")
                    .font(.title3.bold())
                    .foregroundStyle(.purple)
            }

            if pending.isEmpty {
                Text("Немає виплат у статусі pending release")
                    .font(.caption)
                    .foregroundStyle(secondaryOnBackground)
            } else {
                ForEach(pending.prefix(3)) { payout in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Заявка \(payout.applicationId.uuidString.prefix(6)) • \(payout.workerNetAmount) грн")
                            .font(.caption.bold())
                            .foregroundStyle(primaryOnBackground)
                        Text(payout.note)
                            .font(.caption2)
                            .foregroundStyle(secondaryOnBackground)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                }

                Button("Провести всі виплати") {
                    _ = appState.releasePendingPayoutsForCurrentEmployer()
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
        }
        .glassCard()
    }

    private var fullScreenMapMode: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                cityMap
                    .ignoresSafeArea()

                if focusedShiftOnMap != nil {
                    Color.black
                        .opacity(0.12 + 0.18 * max(0, min(1, (sheetVisibleFraction - 0.5) / 0.42)))
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }

                LinearGradient(
                    colors: [.black.opacity(0.18), .clear],
                    startPoint: .top,
                    endPoint: .center
                )
                .frame(height: 180)
                .frame(maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea()
                .allowsHitTesting(false)

                if focusedShiftOnMap == nil, !filteredShifts.isEmpty {
                    let cardWidth = min(340, proxy.size.width - 44)
                    let sideInset = max(16, (proxy.size.width - cardWidth) / 2)
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        ScrollView(.horizontal) {
                            LazyHStack(spacing: 12) {
                                ForEach(filteredShifts.prefix(16)) { shift in
                                ShiftCardView(
                                    shift: shift,
                                    employer: appState.user(by: shift.employerId),
                                    accepted: appState.acceptedApplicationsCount(for: shift.id),
                                    distanceKm: distanceForDisplay(shift),
                                    layout: .compact
                                ) {
                                    focusOnShift(shift)
                                }
                                    .frame(width: cardWidth, height: 164, alignment: .top)
                                    .scrollTransition(axis: .horizontal) { content, phase in
                                        content
                                            .scaleEffect(phase.isIdentity ? 1 : 0.965)
                                            .opacity(phase.isIdentity ? 1 : 0.86)
                                    }
                                    .id(shift.id)
                                }
                            }
                            .scrollTargetLayout()
                        }
                        .frame(height: 176)
                        .scrollIndicators(.hidden)
                        .contentMargins(.horizontal, sideInset, for: .scrollContent)
                        .scrollTargetBehavior(.viewAligned)
                        .scrollPosition(id: $centeredCarouselShiftId)
                        .onAppear {
                            centeredCarouselShiftId = centeredCarouselShiftId ?? filteredShifts.first?.id
                        }
                        .onChange(of: filteredShifts.map(\.id)) { _, shiftIds in
                            if centeredCarouselShiftId == nil || !shiftIds.contains(where: { $0 == centeredCarouselShiftId }) {
                                centeredCarouselShiftId = shiftIds.first
                            }
                        }
                        .onChange(of: centeredCarouselShiftId) { _, newId in
                            guard focusedShiftOnMap == nil,
                                  let newId,
                                  let shift = filteredShifts.first(where: { $0.id == newId }) else { return }
                            centerOnCarouselShift(shift, animated: true)
                        }
                    }
                    .padding(.bottom, 12)
                }

                rightMapControls
                    .padding(.trailing, 12)
                    .padding(.top, focusedShiftOnMap == nil ? 10 : 8)

                if let shift = focusedShiftOnMap {
                    ShiftMapBottomSheet(
                        shift: shift,
                        employer: appState.user(by: shift.employerId),
                        accepted: appState.acceptedApplicationsCount(for: shift.id),
                        distanceKm: distanceForDisplay(shift),
                        maxHeight: proxy.size.height,
                        visibleFraction: $sheetVisibleFraction,
                        onClose: {
                            focusedShiftOnMap = nil
                            sheetVisibleFraction = 0.5
                        },
                        onOpenDetails: {
                            focusedShiftOnMap = nil
                            sheetVisibleFraction = 0.5
                            selectedShift = shift
                        }
                    )
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
                }
            }
        }
        .safeAreaInset(edge: .top) {
            if focusedShiftOnMap == nil {
                topControlsContainer(showEmptyHint: filteredShifts.isEmpty)
            }
        }
        .onChange(of: sheetVisibleFraction) { _, _ in
            guard let shift = focusedShiftOnMap else { return }
            recenterFocusedShift(shift, animated: true)
        }
    }

    private var listMode: some View {
        ZStack {
            AppBackgroundView()

            ScrollView {
                VStack(spacing: 12) {
                    if filteredShifts.isEmpty {
                        Text(I18n.t("filters.no_results", language))
                            .font(.subheadline)
                            .foregroundStyle(secondaryOnBackground)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassCard()
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(filteredShifts) { shift in
                                ShiftCardView(
                                    shift: shift,
                                    employer: appState.user(by: shift.employerId),
                                    accepted: appState.acceptedApplicationsCount(for: shift.id),
                                    distanceKm: distanceForDisplay(shift),
                                    layout: .expanded
                                ) {
                                    selectedShift = shift
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .safeAreaInset(edge: .top) {
            topControlsContainer(showEmptyHint: false)
        }
    }

    private func topControlsContainer(showEmptyHint: Bool) -> some View {
        VStack(spacing: 10) {
            topControls
            if showEmptyHint {
                Text(I18n.t("empty.city", language))
                    .font(.caption)
                    .foregroundStyle(secondaryOnBackground)
                    .glassCard()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 2)
    }

    private var topControls: some View {
        VStack(spacing: 10) {
            Picker("Режим", selection: $discoveryMode) {
                ForEach(DiscoveryMode.allCases) { mode in
                    Text(mode.title(language)).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 10) {
                AppSearchField(
                    text: $searchText,
                    placeholder: I18n.t("search.placeholder", language)
                )

                AppIconSquareButton(size: 44, foreground: primaryOnBackground, action: {
                    showFiltersSheet = true
                }) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "slider.horizontal.3")
                        if activeFiltersCount > 0 {
                            Text("\(activeFiltersCount)")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(palette.accent)
                                .clipShape(Capsule())
                                .offset(x: 10, y: -10)
                        }
                    }
                }
                .accessibilityLabel("Відкрити фільтри")
                .accessibilityHint("Налаштувати параметри пошуку підробітку")

                if appState.currentUser?.role == .employer {
                    AppIconSquareButton(size: 44, foreground: primaryOnBackground, action: {
                        showCreateShift = true
                    }) {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Створити вакансію")
                    .accessibilityHint("Відкрити форму додавання нової зміни")
                }
            }

            if appState.currentUser?.role == .worker {
                quickFiltersBar
            }
        }
        .frostedPanel()
    }

    private var quickFiltersBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                quickFilterChip(
                    title: "Усі",
                    isActive: workFormatFilter == .all
                ) {
                    workFormatFilter = .all
                }
                quickFilterChip(
                    title: I18n.t("format.online", language),
                    isActive: workFormatFilter == .online
                ) {
                    workFormatFilter = .online
                }
                quickFilterChip(
                    title: I18n.t("format.offline", language),
                    isActive: workFormatFilter == .offline
                ) {
                    workFormatFilter = .offline
                }
                if locationService.currentLocation != nil {
                    quickFilterChip(
                        title: "До 5 км",
                        isActive: maxDistanceKm <= 5
                    ) {
                        maxDistanceKm = maxDistanceKm <= 5 ? 20 : 5
                    }
                }
                quickFilterChip(
                    title: "Сьогодні",
                    isActive: useDateTimeFilter
                ) {
                    useDateTimeFilter.toggle()
                    if useDateTimeFilter {
                        desiredDate = Date()
                    }
                }
                quickFilterChip(
                    title: "Перевірені",
                    isActive: verifiedOnly
                ) {
                    verifiedOnly.toggle()
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func quickFilterChip(title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(isActive ? .white : primaryOnBackground)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isActive ? palette.accent : Color.primary.opacity(0.10))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var cityMap: some View {
        MapboxJobsMapView(
            shifts: filteredShifts,
            focusedShiftId: focusedShiftOnMap?.id,
            drawnPolygon: drawnAreaCoordinates,
            cameraUpdate: mapboxCameraUpdate,
            pointsToConvert: drawPointsToConvert,
            isDarkTheme: isDarkTheme,
            onShiftTap: { tappedShift in
                focusOnShift(tappedShift)
            },
            onCameraChange: { center, heading, pitch, zoom in
                mapCenterCoordinate = center
                mapHeading = heading
                mapPitch = pitch
                mapZoom = zoom
            },
            onConvertedPoints: { coordinates in
                if coordinates.count >= 3 {
                    drawnAreaCoordinates = coordinates
                } else {
                    drawnAreaCoordinates = []
                }
                drawPointsToConvert = []
            }
        )
        .overlay {
            if isDrawingArea {
                Path { path in
                    guard let first = drawingPoints.first else { return }
                    path.move(to: first)
                    for point in drawingPoints.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                .stroke(.purple.opacity(0.95), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .contentShape(Rectangle())
                .highPriorityGesture(drawingGesture())
            }
        }
    }

    private var rightMapControls: some View {
        VStack(spacing: 10) {
            mapControlButton(action: {
                resetNorthUp()
            }) {
                Image(systemName: "location.north.line.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .rotationEffect(.degrees(mapHeading))
            }
            .accessibilityLabel("Компас")
            .accessibilityHint("Повернути карту так, щоб північ була зверху")

            mapControlButton(action: {
                centerOnUserLocationAndSyncCity(animated: true)
            }) {
                Image(systemName: "location.fill")
                    .font(.system(size: 18, weight: .semibold))
            }
            .accessibilityLabel("Моя геолокація")
            .accessibilityHint("Відцентрувати карту на вашій позиції")

            mapControlButton(action: {
                toggleMapDimension()
            }) {
                Text(mapDimensionMode == .twoD ? "2D" : "3D")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
            }
            .accessibilityLabel("Перемкнути 2D або 3D")
            .accessibilityValue(mapDimensionMode == .twoD ? "2D" : "3D")

            mapControlButton(action: {
                toggleDrawingMode()
            }, foreground: isDrawingArea ? .purple : primaryOnBackground) {
                Image(systemName: isDrawingArea ? "checkmark" : "pencil")
                    .font(.system(size: 18, weight: .semibold))
            }
            .accessibilityLabel(isDrawingArea ? "Завершити виділення області" : "Намалювати область пошуку")
            .accessibilityHint("Обмежити пошук вакансій обраною зоною на карті")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .allowsHitTesting(focusedShiftOnMap == nil)
        .opacity(focusedShiftOnMap == nil ? 1 : 0)
    }

    private func mapControlButton<Content: View>(
        action: @escaping () -> Void,
        foreground: Color? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        AppIconSquareButton(size: 48, foreground: foreground ?? primaryOnBackground, action: action) {
            content()
        }
    }

    private var summaryCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text("\(selectedCity.name): \(I18n.t("summary.available_now", language))")
                    .font(.caption)
                    .foregroundStyle(secondaryOnBackground)
                Text("\(upcomingCount) змін")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(primaryOnBackground)
                Text(I18n.t("summary.city_radius", language))
                    .font(.footnote)
                    .foregroundStyle(secondaryOnBackground)
            }

            Spacer()

            Image(systemName: "sparkles.rectangle.stack.fill")
                .font(.system(size: 32))
                .foregroundStyle(secondaryOnBackground)
        }
        .glassCard()
    }

    private func centerOnSelectedCity(animated: Bool) {
        applyMapboxCameraUpdate(
            center: selectedCity.coordinate,
            zoom: zoomLevel(forLatitudeDelta: selectedCity.latitudeDelta),
            bearing: mapHeading,
            pitch: mapDimensionMode == .threeD ? 58 : 0,
            animated: animated
        )
    }

    private func focusOnShift(_ shift: JobShift) {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.88, blendDuration: 0.12)) {
            sheetVisibleFraction = 0.5
            focusedShiftOnMap = shift
        }
        recenterFocusedShift(shift, animated: true, duration: 0.36)
    }

    private func recenterFocusedShift(_ shift: JobShift, animated: Bool, duration: Double = 0.24) {
        let latitudeDelta = 0.035
        let verticalShift = latitudeDelta * (sheetVisibleFraction / 2.0)
        let center = CLLocationCoordinate2D(
            latitude: shift.coordinate.latitude - verticalShift,
            longitude: shift.coordinate.longitude
        )
        applyMapboxCameraUpdate(
            center: center,
            zoom: zoomLevel(forLatitudeDelta: latitudeDelta),
            bearing: mapHeading,
            pitch: mapDimensionMode == .threeD ? max(mapPitch, 58) : 0,
            animated: animated,
            duration: duration
        )
    }

    private func centerOnUserLocation(animated: Bool) {
        guard let user = locationService.currentLocation else {
            locationService.requestPermission()
            return
        }

        let latitudeDelta = 0.03
        // In regular map mode keep the user marker lower (near the vacancies lane),
        // and when bottom sheet is opened keep marker in the visible upper area.
        let verticalShift: Double
        if focusedShiftOnMap == nil {
            verticalShift = -latitudeDelta * 0.18
        } else {
            verticalShift = latitudeDelta * (sheetVisibleFraction / 2.0)
        }
        let center = CLLocationCoordinate2D(
            latitude: user.latitude - verticalShift,
            longitude: user.longitude
        )
        applyMapboxCameraUpdate(
            center: center,
            zoom: zoomLevel(forLatitudeDelta: latitudeDelta),
            bearing: mapHeading,
            pitch: mapDimensionMode == .threeD ? max(mapPitch, 58) : 0,
            animated: animated
        )
    }

    private func centerOnUserLocationAndSyncCity(animated: Bool) {
        guard let user = locationService.currentLocation else {
            locationService.requestPermission()
            return
        }

        if let nearestCity = nearestCityOption(to: user), nearestCity.name != selectedCity.name {
            skipCityAutoCenter = true
            selectedCity = nearestCity
        }

        centerOnUserLocation(animated: animated)
    }

    private func nearestCityOption(to coordinate: CLLocationCoordinate2D) -> CityOption? {
        let userPoint = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return Self.cityOptions.min { lhs, rhs in
            let lhsPoint = CLLocation(latitude: lhs.coordinate.latitude, longitude: lhs.coordinate.longitude)
            let rhsPoint = CLLocation(latitude: rhs.coordinate.latitude, longitude: rhs.coordinate.longitude)
            return userPoint.distance(from: lhsPoint) < userPoint.distance(from: rhsPoint)
        }
    }

    private func centerOnCarouselShift(_ shift: JobShift, animated: Bool) {
        applyMapboxCameraUpdate(
            center: shift.coordinate,
            zoom: zoomLevel(forLatitudeDelta: 0.03),
            bearing: mapHeading,
            pitch: mapDimensionMode == .threeD ? max(mapPitch, 58) : 0,
            animated: animated,
            duration: 0.24
        )
    }

    private func resetNorthUp() {
        applyMapboxCameraUpdate(
            center: mapCenterCoordinate,
            zoom: mapZoom,
            bearing: 0,
            pitch: mapPitch,
            animated: true
        )
    }

    private func toggleMapDimension() {
        mapDimensionMode = mapDimensionMode == .twoD ? .threeD : .twoD
        let updatedPitch: CGFloat = mapDimensionMode == .threeD ? 58 : 0
        mapPitch = updatedPitch
        applyMapboxCameraUpdate(
            center: mapCenterCoordinate,
            zoom: mapZoom,
            bearing: mapHeading,
            pitch: updatedPitch,
            animated: true
        )
    }

    private func toggleDrawingMode() {
        if isDrawingArea {
            isDrawingArea = false
            if drawingPoints.count < 3 {
                drawnAreaCoordinates = []
            }
            drawingPoints = []
        } else {
            drawingPoints = []
            drawnAreaCoordinates = []
            isDrawingArea = true
        }
    }

    private func drawingGesture() -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard isDrawingArea else { return }
                let point = value.location
                if let last = drawingPoints.last {
                    let dx = point.x - last.x
                    let dy = point.y - last.y
                    if (dx * dx + dy * dy) < 20 { return }
                }
                drawingPoints.append(point)
            }
            .onEnded { _ in
                guard isDrawingArea else { return }
                drawPointsToConvert = drawingPoints
                drawingPoints = []
                isDrawingArea = false
            }
    }

    private func applyMapboxCameraUpdate(
        center: CLLocationCoordinate2D,
        zoom: CGFloat,
        bearing: CLLocationDirection,
        pitch: CGFloat,
        animated: Bool,
        duration: Double = 0.32
    ) {
        mapboxCameraUpdate = MapboxCameraUpdate(
            id: UUID(),
            center: center,
            zoom: min(max(zoom, 3), 18.5),
            bearing: bearing,
            pitch: min(max(pitch, 0), 70),
            animated: animated,
            duration: duration
        )
    }

    private func zoomLevel(forLatitudeDelta delta: Double) -> CGFloat {
        let clamped = max(delta, 0.001)
        let zoom = log2(360.0 / clamped)
        return CGFloat(min(max(zoom, 3), 18.5))
    }

    private func matchesDrawnArea(_ coordinate: CLLocationCoordinate2D) -> Bool {
        guard drawnAreaCoordinates.count >= 3 else { return true }
        return isInsidePolygon(coordinate, polygon: drawnAreaCoordinates)
    }

    private func isInsidePolygon(_ coordinate: CLLocationCoordinate2D, polygon: [CLLocationCoordinate2D]) -> Bool {
        let x = coordinate.longitude
        let y = coordinate.latitude
        var isInside = false
        var j = polygon.count - 1

        for i in 0..<polygon.count {
            let xi = polygon[i].longitude
            let yi = polygon[i].latitude
            let xj = polygon[j].longitude
            let yj = polygon[j].latitude

            let intersects = ((yi > y) != (yj > y)) && (x < ((xj - xi) * (y - yi) / ((yj - yi) + 0.0000001)) + xi)
            if intersects {
                isInside.toggle()
            }
            j = i
        }
        return isInside
    }

    private func isWithinSelectedCity(_ coordinate: CLLocationCoordinate2D) -> Bool {
        let point = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let cityCenter = CLLocation(latitude: selectedCity.coordinate.latitude, longitude: selectedCity.coordinate.longitude)
        return point.distance(from: cityCenter) <= selectedCity.radiusKm * 1000
    }

    private func isWithinUserDistance(_ shift: JobShift) -> Bool {
        if shift.workFormat == .online { return true }
        guard let distanceKm = effectiveDistanceKm(for: shift) else { return false }
        return distanceKm <= maxDistanceKm
    }

    private func matchesWorkFormat(_ workFormat: WorkFormat) -> Bool {
        switch workFormatFilter {
        case .all:
            return true
        case .online:
            return workFormat == .online
        case .offline:
            return workFormat == .offline
        }
    }

    private func matchesDesiredDateTime(_ date: Date) -> Bool {
        guard useDateTimeFilter else { return true }
        let calendar = Calendar.current

        let sameDay = calendar.isDate(date, inSameDayAs: desiredDate)
        guard sameDay else { return false }

        let startComponents = calendar.dateComponents([.hour, .minute], from: desiredFromTime)
        let endComponents = calendar.dateComponents([.hour, .minute], from: desiredToTime)
        let shiftComponents = calendar.dateComponents([.hour, .minute], from: date)

        let startMinutes = (startComponents.hour ?? 0) * 60 + (startComponents.minute ?? 0)
        let endMinutes = (endComponents.hour ?? 23) * 60 + (endComponents.minute ?? 59)
        let shiftMinutes = (shiftComponents.hour ?? 0) * 60 + (shiftComponents.minute ?? 0)

        if startMinutes <= endMinutes {
            return shiftMinutes >= startMinutes && shiftMinutes <= endMinutes
        }
        return shiftMinutes >= startMinutes || shiftMinutes <= endMinutes
    }

    private func distanceForDisplay(_ shift: JobShift) -> Double? {
        effectiveDistanceKm(for: shift)
    }

    private func effectiveDistanceKm(for shift: JobShift) -> Double? {
        guard shift.workFormat == .offline,
              let user = locationService.currentLocation else { return nil }
        return routeDistanceKmByShift[shift.id] ?? straightLineDistanceKm(from: user, to: shift.coordinate)
    }

    private func straightLineDistanceKm(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let first = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let second = CLLocation(latitude: to.latitude, longitude: to.longitude)
        return first.distance(from: second) / 1000
    }

    private func shiftDiscoveryScore(_ shift: JobShift) -> Double {
        let employer = appState.user(by: shift.employerId)
        let reliability = (employer?.reliabilityScore ?? 0) / 100.0
        let rating = min(1.0, max(0.0, (employer?.rating ?? 0) / 5.0))
        let riskPenalty = appState.riskScore(for: shift.employerId) / 100.0
        let payScore = min(1.0, Double(shift.pay) / 320.0)
        let verificationScore = (employer?.isVerifiedEmployer == true) ? 0.08 : 0

        let distanceScore: Double
        if shift.workFormat == .online {
            distanceScore = 0.7
        } else if let distance = effectiveDistanceKm(for: shift) {
            distanceScore = max(0, 1 - (distance / 35.0))
        } else {
            distanceScore = 0.45
        }

        let hoursUntilStart = max(0, shift.startDate.timeIntervalSinceNow / 3600)
        let urgencyScore = 1 / (1 + (hoursUntilStart / 48))

        return (reliability * 0.38) +
            (rating * 0.22) +
            (distanceScore * 0.20) +
            (payScore * 0.14) +
            (urgencyScore * 0.06) +
            verificationScore -
            (riskPenalty * 0.25)
    }

    private func refreshRouteDistances() {
        guard let user = locationService.currentLocation else {
            routeDistanceTask?.cancel()
            routeDistanceKmByShift = [:]
            lastRouteOrigin = nil
            return
        }

        if let oldOrigin = lastRouteOrigin {
            let movedKm = straightLineDistanceKm(from: oldOrigin, to: user)
            if movedKm > 0.5 {
                routeDistanceKmByShift = [:]
            }
        }
        lastRouteOrigin = user

        routeDistanceTask?.cancel()
        let candidates = appState.shifts
            .filter { $0.workFormat == .offline && isWithinSelectedCity($0.coordinate) }
            .prefix(90)

        routeDistanceTask = Task {
            for shift in candidates {
                if Task.isCancelled { return }
                if routeDistanceKmByShift[shift.id] != nil { continue }

                let roadKm = await fetchRoadDistanceKm(from: user, to: shift.coordinate)
                let finalKm = roadKm ?? straightLineDistanceKm(from: user, to: shift.coordinate)
                await MainActor.run {
                    routeDistanceKmByShift[shift.id] = finalKm
                }
            }
        }
    }

    private func fetchRoadDistanceKm(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async -> Double? {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
        request.transportType = .automobile
        request.requestsAlternateRoutes = false

        do {
            let response = try await MKDirections(request: request).calculate()
            return response.routes.first.map { $0.distance / 1000 }
        } catch {
            return nil
        }
    }
}

private struct ShiftMapBottomSheet: View {
    let shift: JobShift
    let employer: AppUser?
    let accepted: Int
    let distanceKm: Double?
    let maxHeight: CGFloat
    @Binding var visibleFraction: CGFloat
    let onClose: () -> Void
    let onOpenDetails: () -> Void

    @State private var snappedFraction: CGFloat = 0.5
    @GestureState private var dragTranslation: CGFloat = 0
    private let snapFractions: [CGFloat] = [0.5, 0.72, 0.92]

    private var panelHeight: CGFloat {
        let minimum = maxHeight * (snapFractions.first ?? 0.5)
        let maximum = maxHeight * (snapFractions.last ?? 0.92)
        let raw = (snappedFraction * maxHeight) - dragTranslation
        return min(maximum, max(minimum, raw))
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(.white.opacity(0.45))
                .frame(width: 40, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 6)
                .gesture(
                    DragGesture(minimumDistance: 4, coordinateSpace: .local)
                        .updating($dragTranslation) { value, state, _ in
                            state = value.translation.height
                        }
                        .onEnded { value in
                            let projectedHeight = panelHeight - value.predictedEndTranslation.height
                            let projectedFraction = max(0.5, min(0.92, projectedHeight / maxHeight))
                            let nearest = snapFractions.min(by: { abs($0 - projectedFraction) < abs($1 - projectedFraction) }) ?? 0.5
                            withAnimation(.interactiveSpring(response: 0.36, dampingFraction: 0.86)) {
                                snappedFraction = nearest
                                visibleFraction = nearest
                            }
                        }
                )

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(shift.title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("\(shift.pay) грн/год")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.purple, .pink.opacity(0.92)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.subheadline.bold())
                        .padding(10)
                }
                .buttonStyle(.plain)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 6)

            Divider()
                .overlay(.white.opacity(0.12))

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Label("\(shift.durationHours) год", systemImage: "clock")
                        Label(shift.workFormat.title, systemImage: shift.workFormat == .online ? "wifi" : "mappin.and.ellipse")
                        Label("\(accepted)/\(shift.requiredWorkers)", systemImage: "person.3")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Text(shift.address)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let distanceKm {
                        Text("Відстань: \(distanceKm, specifier: "%.1f") км")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Text("Час: \(shift.startDate.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let employer {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(employer.name)
                                .font(.subheadline.weight(.semibold))
                            Text("Рейтинг: \(employer.rating, specifier: "%.1f") • \(employer.reviewsCount)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Надійність: \(Int(employer.reliabilityScore))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(shift.details)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineSpacing(3)

                    Button(action: onOpenDetails) {
                        Text("Відкрити повну картку")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .padding(.top, 6)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: panelHeight, alignment: .top)
        .background(.ultraThinMaterial)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.16),
                    Color.white.opacity(0.06),
                    Color.black.opacity(0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.42), .white.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: .black.opacity(0.28), radius: 22, y: -2)
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
        .onAppear {
            snappedFraction = visibleFraction
        }
        .onChange(of: dragTranslation) { _, _ in
            visibleFraction = panelHeight / maxHeight
        }
        .onChange(of: snappedFraction) { _, newValue in
            visibleFraction = newValue
        }
        .animation(.interactiveSpring(response: 0.34, dampingFraction: 0.88), value: dragTranslation)
    }
}

private struct ShiftPinView: View {
    let pay: Int
    let isFocused: Bool

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: "mappin.circle.fill")
                .font(.title2)
                .foregroundStyle(isFocused ? .purple : .pink)
            Text("\(pay) грн/год")
                .font(.caption2.bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.thickMaterial)
                .clipShape(Capsule())
        }
        .scaleEffect(isFocused ? 1.16 : 1.0)
        .shadow(color: isFocused ? .purple.opacity(0.55) : .clear, radius: 10, y: 2)
        .animation(.spring(response: 0.32, dampingFraction: 0.72), value: isFocused)
    }
}

private struct UserLocationDotView: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.blue.opacity(0.2))
                .frame(width: 28, height: 28)
            Circle()
                .fill(Color.blue)
                .frame(width: 13, height: 13)
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.95), lineWidth: 2)
                }
        }
        .shadow(color: .blue.opacity(0.4), radius: 8)
    }
}

private struct FiltersSheet: View {
    let language: AppLanguage
    let isWorker: Bool
    let canFilterByDistance: Bool
    let cityNames: [String]
    @Binding var selectedCityName: String
    let filteredCount: Int
    @Binding var minPay: Double
    @Binding var maxDuration: Double
    @Binding var maxDistanceKm: Double
    @Binding var workFormatFilter: WorkFormatFilter
    @Binding var useDateTimeFilter: Bool
    @Binding var desiredDate: Date
    @Binding var desiredFromTime: Date
    @Binding var desiredToTime: Date
    @Binding var verifiedOnly: Bool
    @AppStorage("appTheme") private var appThemeRawValue = AppTheme.dark.rawValue
    @Environment(\.dismiss) private var dismiss

    private var isDarkTheme: Bool {
        resolvedTheme(from: appThemeRawValue) == .dark
    }

    private var palette: AppPalette {
        AppPalette.forTheme(resolvedTheme(from: appThemeRawValue))
    }

    private var primaryText: Color {
        palette.textPrimary
    }

    private var secondaryText: Color {
        palette.textSecondary
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackgroundView()

                ScrollView {
                    VStack(spacing: 14) {
                        filterCard(title: "Де працюємо") {
                            cityPickerRow
                        }

                        filterCard(title: "Формат роботи") {
                            Picker("Формат", selection: $workFormatFilter) {
                                ForEach(WorkFormatFilter.allCases) { item in
                                    Text(item.title(language)).tag(item)
                                }
                            }
                            .pickerStyle(.segmented)
                            .tint(palette.accent)
                        }

                        filterCard(title: "Бюджет і тривалість") {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("\(I18n.t("filters.min_pay", language)): \(Int(minPay)) грн/год")
                                    .foregroundStyle(secondaryText)
                                Slider(value: $minPay, in: 0...500, step: 10)
                                    .tint(palette.accent)

                                Text("\(I18n.t("filters.max_duration", language)): \(Int(maxDuration)) год")
                                    .foregroundStyle(secondaryText)
                                Slider(value: $maxDuration, in: 1...24, step: 1)
                                    .tint(palette.accent)
                            }
                        }

                        if canFilterByDistance {
                            filterCard(title: "Дистанція") {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("\(I18n.t("filters.max_distance", language)): \(Int(maxDistanceKm)) \(I18n.t("filters.distance_km", language))")
                                        .foregroundStyle(secondaryText)
                                    Slider(value: $maxDistanceKm, in: 1...100, step: 1)
                                        .tint(palette.accent)
                                }
                            }
                        }

                        filterCard(title: "Дата і час") {
                            Toggle("Фільтр за датою та часом", isOn: $useDateTimeFilter)
                                .tint(palette.accent)
                                .foregroundStyle(primaryText)

                            if useDateTimeFilter {
                                DatePicker("Бажана дата", selection: $desiredDate, displayedComponents: .date)
                                    .tint(palette.accent)
                                    .foregroundStyle(primaryText)

                                DatePicker("Від", selection: $desiredFromTime, displayedComponents: .hourAndMinute)
                                    .tint(palette.accent)
                                    .foregroundStyle(primaryText)

                                DatePicker("До", selection: $desiredToTime, displayedComponents: .hourAndMinute)
                                    .tint(palette.accent)
                                    .foregroundStyle(primaryText)
                            }
                        }

                        if isWorker {
                            filterCard(title: "Надійність") {
                                Toggle(I18n.t("filters.verified", language), isOn: $verifiedOnly)
                                    .tint(palette.accent)
                                    .foregroundStyle(primaryText)
                            }
                        }

                        Button {
                            dismiss()
                        } label: {
                            Text("Показати \(filteredCount) пропозицій")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .foregroundStyle(.white)
                                .background(palette.accent)
                                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                    .padding(.bottom, 22)
                }
            }
            .navigationTitle("Фільтри")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Закрити") { dismiss() }
                        .foregroundStyle(primaryText)
                }
            }
        }
    }

    private func filterCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(primaryText)
            content()
        }
        .padding(16)
        .background(.regularMaterial)
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(isDarkTheme ? .white.opacity(0.2) : .black.opacity(0.1), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var cityPickerRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(cityNames, id: \.self) { city in
                    Button {
                        selectedCityName = city
                    } label: {
                        Text(city)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .frame(minWidth: 130)
                            .padding(.vertical, 14)
                            .foregroundStyle(selectedCityName == city ? .white : primaryText)
                            .background(
                                selectedCityName == city
                                    ? palette.accent
                                    : (isDarkTheme ? Color.white.opacity(0.14) : Color.black.opacity(0.08))
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
            }
        }
    }
}
