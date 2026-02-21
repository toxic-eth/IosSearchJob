import SwiftUI
import MapKit

struct MainMapView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var locationService: LocationService

    @State private var searchText = ""
    @State private var minPay: Double = 80
    @State private var maxDuration: Double = 12
    @State private var verifiedOnly = false
    @State private var selectedShift: JobShift?
    @State private var showCreateShift = false

    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: UkraineRegion.center,
            span: MKCoordinateSpan(latitudeDelta: 6.0, longitudeDelta: 8.0)
        )
    )

    private var filteredShifts: [JobShift] {
        let role = appState.currentUser?.role

        return appState.shifts
            .filter { shift in
                let visibleByStatus = role == .worker ? shift.status == .open : true
                let employer = appState.user(by: shift.employerId)
                let verifiedMatch = role == .worker ? (!verifiedOnly || (employer?.isVerifiedEmployer == true)) : true

                return UkraineRegion.contains(shift.coordinate) &&
                    visibleByStatus &&
                    verifiedMatch &&
                    Double(shift.pay) >= minPay &&
                    Double(shift.durationHours) <= maxDuration &&
                    (searchText.isEmpty || shift.title.localizedCaseInsensitiveContains(searchText) || shift.details.localizedCaseInsensitiveContains(searchText))
            }
            .sorted { $0.startDate < $1.startDate }
    }

    private var upcomingCount: Int {
        filteredShifts.filter { $0.startDate > Date() }.count
    }

    private var unreadNotifications: Int {
        appState.unreadNotificationsCountForCurrentUser()
    }

    var body: some View {
        TabView {
            mapDashboard
                .tabItem {
                    Label("Зміни", systemImage: "map")
                }

            ActivityView()
                .tabItem {
                    Label("Активність", systemImage: "list.bullet.clipboard")
                }

            NotificationsView()
                .tabItem {
                    Label("Сповіщення", systemImage: "bell")
                }
                .badge(unreadNotifications)

            ProfileView()
                .tabItem {
                    Label("Профіль", systemImage: "person.crop.circle")
                }
        }
        .tint(.cyan)
    }

    private var mapDashboard: some View {
        NavigationStack {
            ZStack {
                AppBackgroundView()

                ScrollView {
                    VStack(spacing: 12) {
                        summaryCard
                        filtersBlock
                        mapSection
                        shiftListSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Зміни по Україні")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Вийти") { appState.logout() }
                }

                if appState.currentUser?.role == .employer {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("+ Зміна") { showCreateShift = true }
                    }
                }
            }
            .sheet(item: $selectedShift) { shift in
                ShiftDetailView(shift: shift)
                    .environmentObject(appState)
            }
            .sheet(isPresented: $showCreateShift) {
                AddShiftView(centerCoordinate: UkraineRegion.center)
                    .environmentObject(appState)
            }
            .onAppear {
                if appState.consumeLocationPermissionRequest() {
                    locationService.requestPermission()
                }
                updateRegionIfNeeded()
            }
            .onReceive(locationService.$currentLocation) { _ in
                updateRegionIfNeeded()
            }
        }
    }

    private var mapSection: some View {
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
        .frame(height: 330)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var shiftListSection: some View {
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

    private func updateRegionIfNeeded() {
        guard let userLocation = locationService.currentLocation, UkraineRegion.contains(userLocation) else {
            return
        }

        cameraPosition = .region(
            MKCoordinateRegion(
                center: userLocation,
                span: MKCoordinateSpan(latitudeDelta: 0.35, longitudeDelta: 0.35)
            )
        )
    }

    private var summaryCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text("Сьогодні доступно")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
                Text("\(upcomingCount) змін")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Система відстежує ліміти місць, SLA відповідей і довіру по рейтингах.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(2)
            }

            Spacer()

            Image(systemName: "sparkles.rectangle.stack.fill")
                .font(.system(size: 32))
                .foregroundStyle(.white.opacity(0.9))
        }
        .glassCard()
    }

    private var filtersBlock: some View {
        VStack(spacing: 10) {
            TextField("Пошук за назвою або описом", text: $searchText)
                .textFieldStyle(.roundedBorder)

            HStack {
                Text("Мін. оплата: $\(Int(minPay))/год")
                    .foregroundStyle(.white.opacity(0.9))
                Slider(value: $minPay, in: 0...500, step: 10)
                    .tint(.cyan)
            }
            .font(.caption)

            HStack {
                Text("Макс. тривалість: \(Int(maxDuration)) год")
                    .foregroundStyle(.white.opacity(0.9))
                Slider(value: $maxDuration, in: 1...24, step: 1)
                    .tint(.cyan)
            }
            .font(.caption)

            if appState.currentUser?.role == .worker {
                Toggle("Лише перевірені роботодавці", isOn: $verifiedOnly)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.95))
                    .tint(.cyan)
            }
        }
        .glassCard()
    }
}

private struct ShiftPinView: View {
    let pay: Int

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: "mappin.circle.fill")
                .font(.title2)
                .foregroundStyle(.red)
            Text("$\(pay)/год")
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
                        .foregroundStyle(.white)
                    Spacer()
                    Text(shift.status.title)
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(shift.status == .open ? Color.cyan.opacity(0.22) : Color.gray.opacity(0.22))
                        .clipShape(Capsule())
                        .foregroundStyle(.white)
                }

                Text(shift.details)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.84))
                    .lineLimit(2)

                HStack {
                    Label("$\(shift.pay)/год", systemImage: "dollarsign.circle")
                    Label("\(shift.durationHours) год", systemImage: "clock")
                    Label("\(accepted)/\(shift.requiredWorkers)", systemImage: "person.3")
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))

                if let employer {
                    HStack {
                        Label(employer.name, systemImage: "building.2")
                            .lineLimit(1)
                        if employer.isVerifiedEmployer {
                            Label("Перевірено", systemImage: "checkmark.seal.fill")
                                .foregroundStyle(.cyan)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
        }
        .buttonStyle(.plain)
    }
}
