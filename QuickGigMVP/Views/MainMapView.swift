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
            .sorted { $0.startDate < $1.startDate }
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

    private var primaryOnBackground: Color {
        isDarkTheme ? .white : .black
    }

    private var secondaryOnBackground: Color {
        isDarkTheme ? .white.opacity(0.82) : .black.opacity(0.72)
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
        TabView {
            dashboard
                .tabItem {
                    Label(I18n.t("tab.shifts", language), systemImage: "map")
                }

            ActivityView()
                .tabItem {
                    Label(I18n.t("tab.activity", language), systemImage: "list.bullet.clipboard")
                }

            CommunicationHubView()
                .tabItem {
                    Label("Чати", systemImage: "bubble.left.and.bubble.right")
                }
                .badge(unreadChats)

            NotificationsView()
                .tabItem {
                    Label(I18n.t("tab.notifications", language), systemImage: "bell")
                }
                .badge(unreadNotifications)

            ProfileView()
                .tabItem {
                    Label(I18n.t("tab.profile", language), systemImage: "person.crop.circle")
                }
        }
        .tint(.purple)
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
                                    ShiftRow(
                                    shift: shift,
                                    employer: appState.user(by: shift.employerId),
                                    accepted: appState.acceptedApplicationsCount(for: shift.id),
                                    distanceKm: distanceForDisplay(shift)
                                ) {
                                    focusOnShift(shift)
                                }
                                    .frame(width: cardWidth, height: 164, alignment: .top)
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
                VStack(spacing: 10) {
                    topControls
                    if filteredShifts.isEmpty {
                        Text(I18n.t("empty.city", language))
                            .font(.caption)
                            .foregroundStyle(secondaryOnBackground)
                            .glassCard()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 2)
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
                    summaryCard

                    if filteredShifts.isEmpty {
                        Text(I18n.t("filters.no_results", language))
                            .font(.subheadline)
                            .foregroundStyle(secondaryOnBackground)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassCard()
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(filteredShifts) { shift in
                                ShiftRow(
                                    shift: shift,
                                    employer: appState.user(by: shift.employerId),
                                    accepted: appState.acceptedApplicationsCount(for: shift.id),
                                    distanceKm: distanceForDisplay(shift)
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
            topControls
                .padding(.horizontal, 16)
                .padding(.top, 2)
        }
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
                TextField(I18n.t("search.placeholder", language), text: $searchText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(.thinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isDarkTheme ? .white.opacity(0.25) : .black.opacity(0.12), lineWidth: 1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                Button {
                    showFiltersSheet = true
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "slider.horizontal.3")
                        if activeFiltersCount > 0 {
                            Text("\(activeFiltersCount)")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.purple)
                                .clipShape(Capsule())
                                .offset(x: 10, y: -10)
                        }
                    }
                }
                .buttonStyle(FrostedButtonStyle())
                .foregroundStyle(primaryOnBackground)

                if appState.currentUser?.role == .employer {
                    Button {
                        showCreateShift = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(FrostedButtonStyle())
                    .foregroundStyle(primaryOnBackground)
                }
            }
        }
        .frostedPanel()
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

            mapControlButton(action: {
                centerOnUserLocationAndSyncCity(animated: true)
            }) {
                Image(systemName: "location.fill")
                    .font(.system(size: 18, weight: .semibold))
            }

            mapControlButton(action: {
                toggleMapDimension()
            }) {
                Text(mapDimensionMode == .twoD ? "2D" : "3D")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
            }

            mapControlButton(action: {
                toggleDrawingMode()
            }, foreground: isDrawingArea ? .purple : primaryOnBackground) {
                Image(systemName: isDrawingArea ? "checkmark" : "pencil")
                    .font(.system(size: 18, weight: .semibold))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .allowsHitTesting(focusedShiftOnMap == nil)
        .opacity(focusedShiftOnMap == nil ? 1 : 0)
    }

    private func mapControlButton<Content: View>(
        action: @escaping () -> Void,
        foreground: Color? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Button(action: action) {
            content()
                .foregroundStyle(foreground ?? primaryOnBackground)
                .frame(width: 48, height: 48)
                .background(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(isDarkTheme ? .white.opacity(0.22) : .black.opacity(0.12), lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
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

private struct ShiftRow: View {
    let shift: JobShift
    let employer: AppUser?
    let accepted: Int
    let distanceKm: Double?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(shift.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer()
                    Text(shift.status.title)
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(shift.status == .open ? Color.purple.opacity(0.24) : Color.gray.opacity(0.22))
                        .clipShape(Capsule())
                        .foregroundStyle(.primary)
                }

                Text(shift.details)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Text(shift.address)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack {
                    Label("\(shift.pay) грн/год", systemImage: "dollarsign.circle")
                    Label("\(shift.durationHours) год", systemImage: "clock")
                    Label(shift.workFormat.title, systemImage: shift.workFormat == .online ? "wifi" : "mappin.and.ellipse")
                    Label("\(accepted)/\(shift.requiredWorkers)", systemImage: "person.3")
                    if let distanceKm {
                        Label("\(distanceKm, specifier: "%.1f") км", systemImage: "road.lanes")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let employer {
                    HStack {
                        Label(employer.name, systemImage: "building.2")
                            .lineLimit(1)
                        if employer.isVerifiedEmployer {
                            Label("Перевірено", systemImage: "checkmark.seal.fill")
                                .foregroundStyle(.purple)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    Color.clear
                        .frame(height: 16)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
        }
        .buttonStyle(.plain)
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

    private var primaryText: Color {
        isDarkTheme ? .white : .black
    }

    private var secondaryText: Color {
        isDarkTheme ? .white.opacity(0.85) : .black.opacity(0.75)
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
                            .tint(.purple)
                        }

                        filterCard(title: "Бюджет і тривалість") {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("\(I18n.t("filters.min_pay", language)): \(Int(minPay)) грн/год")
                                    .foregroundStyle(secondaryText)
                                Slider(value: $minPay, in: 0...500, step: 10)
                                    .tint(.purple)

                                Text("\(I18n.t("filters.max_duration", language)): \(Int(maxDuration)) год")
                                    .foregroundStyle(secondaryText)
                                Slider(value: $maxDuration, in: 1...24, step: 1)
                                    .tint(.purple)
                            }
                        }

                        if canFilterByDistance {
                            filterCard(title: "Дистанція") {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("\(I18n.t("filters.max_distance", language)): \(Int(maxDistanceKm)) \(I18n.t("filters.distance_km", language))")
                                        .foregroundStyle(secondaryText)
                                    Slider(value: $maxDistanceKm, in: 1...100, step: 1)
                                        .tint(.purple)
                                }
                            }
                        }

                        filterCard(title: "Дата і час") {
                            Toggle("Фільтр за датою та часом", isOn: $useDateTimeFilter)
                                .tint(.purple)
                                .foregroundStyle(primaryText)

                            if useDateTimeFilter {
                                DatePicker("Бажана дата", selection: $desiredDate, displayedComponents: .date)
                                    .tint(.purple)
                                    .foregroundStyle(primaryText)

                                DatePicker("Від", selection: $desiredFromTime, displayedComponents: .hourAndMinute)
                                    .tint(.purple)
                                    .foregroundStyle(primaryText)

                                DatePicker("До", selection: $desiredToTime, displayedComponents: .hourAndMinute)
                                    .tint(.purple)
                                    .foregroundStyle(primaryText)
                            }
                        }

                        if isWorker {
                            filterCard(title: "Надійність") {
                                Toggle(I18n.t("filters.verified", language), isOn: $verifiedOnly)
                                    .tint(.purple)
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
                                .background(Color.purple)
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
                .font(.system(size: 34, weight: .bold, design: .rounded))
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
                                    ? Color.purple
                                    : (isDarkTheme ? Color.white.opacity(0.14) : Color.black.opacity(0.08))
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
            }
        }
    }
}
