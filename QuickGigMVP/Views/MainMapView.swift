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
    @State private var showCreateShift = false
    @State private var selectedCity = Self.cityOptions[0]

    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: Self.cityOptions[0].coordinate,
            span: MKCoordinateSpan(latitudeDelta: Self.cityOptions[0].latitudeDelta, longitudeDelta: Self.cityOptions[0].longitudeDelta)
        )
    )

    private static let cityOptions: [CityOption] = [
        CityOption(name: "Київ", coordinate: CLLocationCoordinate2D(latitude: 50.4501, longitude: 30.5234), latitudeDelta: 0.16, longitudeDelta: 0.16, radiusKm: 35),
        CityOption(name: "Львів", coordinate: CLLocationCoordinate2D(latitude: 49.8397, longitude: 24.0297), latitudeDelta: 0.15, longitudeDelta: 0.15, radiusKm: 28),
        CityOption(name: "Одеса", coordinate: CLLocationCoordinate2D(latitude: 46.4825, longitude: 30.7233), latitudeDelta: 0.18, longitudeDelta: 0.18, radiusKm: 30),
        CityOption(name: "Дніпро", coordinate: CLLocationCoordinate2D(latitude: 48.4647, longitude: 35.0462), latitudeDelta: 0.16, longitudeDelta: 0.16, radiusKm: 30),
        CityOption(name: "Харків", coordinate: CLLocationCoordinate2D(latitude: 49.9935, longitude: 36.2304), latitudeDelta: 0.18, longitudeDelta: 0.18, radiusKm: 32)
    ]

    private var filteredShifts: [JobShift] {
        let role = appState.currentUser?.role

        return appState.shifts
            .filter { shift in
                let visibleByStatus = role == .worker ? shift.status == .open : true
                let employer = appState.user(by: shift.employerId)
                let verifiedMatch = role == .worker ? (!verifiedOnly || (employer?.isVerifiedEmployer == true)) : true
                let textMatch = searchText.isEmpty || shift.title.localizedCaseInsensitiveContains(searchText) || shift.details.localizedCaseInsensitiveContains(searchText)

                return UkraineRegion.contains(shift.coordinate) &&
                    visibleByStatus &&
                    verifiedMatch &&
                    matchesWorkFormat(shift.workFormat) &&
                    isWithinUserDistance(shift.coordinate, workFormat: shift.workFormat) &&
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
                if discoveryMode == .map {
                    fullScreenMapMode
                } else {
                    listMode
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
            .onAppear {
                if appState.consumeLocationPermissionRequest() {
                    locationService.requestPermission()
                }
                centerOnSelectedCity(animated: false)
            }
            .onChange(of: selectedCity.name) { _, _ in
                centerOnSelectedCity(animated: true)
            }
        }
    }

    private var fullScreenMapMode: some View {
        ZStack(alignment: .bottom) {
            cityMap
                .ignoresSafeArea()

            if !filteredShifts.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(filteredShifts.prefix(8)) { shift in
                            ShiftRow(
                                shift: shift,
                                employer: appState.user(by: shift.employerId),
                                accepted: appState.acceptedApplicationsCount(for: shift.id)
                            ) {
                                selectedShift = shift
                            }
                            .frame(width: 300)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 8)
            }
        }
        .safeAreaInset(edge: .top) {
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

    private var listMode: some View {
        ZStack {
            AppBackgroundView()

            ScrollView {
                VStack(spacing: 12) {
                    summaryCard
                    filterControls

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
                                    accepted: appState.acceptedApplicationsCount(for: shift.id)
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
                cityMenu
                TextField(I18n.t("search.placeholder", language), text: $searchText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(.thinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isDarkTheme ? .white.opacity(0.25) : .black.opacity(0.12), lineWidth: 1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))

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

            Picker("Формат", selection: $workFormatFilter) {
                ForEach(WorkFormatFilter.allCases) { item in
                    Text(item.title(language)).tag(item)
                }
            }
            .pickerStyle(.segmented)

            if locationService.currentLocation != nil {
                HStack {
                    Text("\(I18n.t("filters.max_distance", language)): \(Int(maxDistanceKm)) \(I18n.t("filters.distance_km", language))")
                        .foregroundStyle(secondaryOnBackground)
                    Slider(value: $maxDistanceKm, in: 1...100, step: 1)
                        .tint(.purple)
                }
                .font(.caption)
            }

            Toggle("Фільтр за датою та часом", isOn: $useDateTimeFilter)
                .font(.caption)
                .foregroundStyle(secondaryOnBackground)
                .tint(.purple)

            if useDateTimeFilter {
                DatePicker("Бажана дата", selection: $desiredDate, displayedComponents: .date)
                    .tint(.purple)

                DatePicker("Від", selection: $desiredFromTime, displayedComponents: .hourAndMinute)
                    .tint(.purple)

                DatePicker("До", selection: $desiredToTime, displayedComponents: .hourAndMinute)
                    .tint(.purple)
            }
        }
        .frostedPanel()
    }

    private var cityMenu: some View {
        Menu {
            ForEach(Self.cityOptions) { city in
                Button {
                    selectedCity = city
                } label: {
                    HStack {
                        Text(city.name)
                        if city.name == selectedCity.name {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "location.circle.fill")
                Text(selectedCity.name)
                    .lineLimit(1)
            }
            .foregroundStyle(primaryOnBackground)
        }
        .buttonStyle(FrostedButtonStyle())
    }

    private var filterControls: some View {
        VStack(spacing: 10) {
            HStack {
                Text("\(I18n.t("filters.min_pay", language)): \(Int(minPay)) грн/год")
                    .foregroundStyle(secondaryOnBackground)
                Slider(value: $minPay, in: 0...500, step: 10)
                    .tint(.purple)
            }
            .font(.caption)

            HStack {
                Text("\(I18n.t("filters.max_duration", language)): \(Int(maxDuration)) год")
                    .foregroundStyle(secondaryOnBackground)
                Slider(value: $maxDuration, in: 1...24, step: 1)
                    .tint(.purple)
            }
            .font(.caption)

            if appState.currentUser?.role == .worker {
                Toggle(I18n.t("filters.verified", language), isOn: $verifiedOnly)
                    .font(.caption)
                    .foregroundStyle(secondaryOnBackground)
                    .tint(.purple)
            }
        }
        .glassCard()
    }

    private var cityMap: some View {
        Map(position: $cameraPosition) {
            ForEach(filteredShifts) { shift in
                Annotation(shift.title, coordinate: shift.coordinate) {
                    Button {
                        selectedShift = shift
                    } label: {
                        ShiftPinView(pay: shift.pay)
                    }
                }
            }
        }
        .mapStyle(.hybrid(elevation: .realistic, pointsOfInterest: .excludingAll, showsTraffic: false))
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
        let region = MKCoordinateRegion(
            center: selectedCity.coordinate,
            span: MKCoordinateSpan(latitudeDelta: selectedCity.latitudeDelta, longitudeDelta: selectedCity.longitudeDelta)
        )

        if animated {
            withAnimation(.easeInOut(duration: 0.35)) {
                cameraPosition = .region(region)
            }
        } else {
            cameraPosition = .region(region)
        }
    }

    private func isWithinSelectedCity(_ coordinate: CLLocationCoordinate2D) -> Bool {
        let point = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let cityCenter = CLLocation(latitude: selectedCity.coordinate.latitude, longitude: selectedCity.coordinate.longitude)
        return point.distance(from: cityCenter) <= selectedCity.radiusKm * 1000
    }

    private func isWithinUserDistance(_ coordinate: CLLocationCoordinate2D, workFormat: WorkFormat) -> Bool {
        if workFormat == .online { return true }
        guard let userCoordinate = locationService.currentLocation else { return true }
        let userPoint = CLLocation(latitude: userCoordinate.latitude, longitude: userCoordinate.longitude)
        let shiftPoint = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return userPoint.distance(from: shiftPoint) <= maxDistanceKm * 1000
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
}

private struct ShiftPinView: View {
    let pay: Int

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: "mappin.circle.fill")
                .font(.title2)
                .foregroundStyle(.pink)
            Text("\(pay) грн/год")
                .font(.caption2.bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.thickMaterial)
                .clipShape(Capsule())
        }
    }
}

private struct ShiftRow: View {
    let shift: JobShift
    let employer: AppUser?
    let accepted: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(shift.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
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

                HStack {
                    Label("\(shift.pay) грн/год", systemImage: "dollarsign.circle")
                    Label("\(shift.durationHours) год", systemImage: "clock")
                    Label(shift.workFormat.title, systemImage: shift.workFormat == .online ? "wifi" : "mappin.and.ellipse")
                    Label("\(accepted)/\(shift.requiredWorkers)", systemImage: "person.3")
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
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
        }
        .buttonStyle(.plain)
    }
}
