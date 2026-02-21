import SwiftUI
import MapKit

struct MainMapView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var locationService: LocationService

    @State private var searchText = ""
    @State private var minPay: Double = 80
    @State private var maxDuration: Double = 12
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

                return UkraineRegion.contains(shift.coordinate) &&
                    visibleByStatus &&
                    Double(shift.pay) >= minPay &&
                    Double(shift.durationHours) <= maxDuration &&
                    (searchText.isEmpty || shift.title.localizedCaseInsensitiveContains(searchText) || shift.details.localizedCaseInsensitiveContains(searchText))
            }
            .sorted { $0.startDate < $1.startDate }
    }

    private var upcomingCount: Int {
        filteredShifts.filter { $0.startDate > Date() }.count
    }

    var body: some View {
        TabView {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 14) {
                        summaryCard
                        filtersBlock
                        mapSection
                        shiftListSection
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 16)
                }
                .navigationTitle("Смены по Украине")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Выйти") { appState.logout() }
                    }

                    if appState.currentUser?.role == .employer {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("+ Смена") { showCreateShift = true }
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
            .tabItem {
                Label("Смены", systemImage: "map")
            }

            ActivityView()
                .tabItem {
                    Label("Активность", systemImage: "list.bullet.clipboard")
                }

            ProfileView()
                .tabItem {
                    Label("Профиль", systemImage: "person.crop.circle")
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
        .frame(height: 320)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
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
        VStack(alignment: .leading, spacing: 6) {
            Text("Сегодня доступно")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("\(upcomingCount) смен")
                .font(.title2.bold())
            Text("Новый апдейт: смены теперь с лимитом мест, автозакрытием и прозрачным набором.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.blue.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var filtersBlock: some View {
        VStack(spacing: 8) {
            TextField("Поиск по названию или описанию", text: $searchText)
                .textFieldStyle(.roundedBorder)

            HStack {
                Text("Мин. оплата: $\(Int(minPay))/ч")
                Slider(value: $minPay, in: 0...500, step: 10)
            }
            .font(.caption)

            HStack {
                Text("Макс. длительность: \(Int(maxDuration)) ч")
                Slider(value: $maxDuration, in: 1...24, step: 1)
            }
            .font(.caption)
        }
    }
}

private struct ShiftPinView: View {
    let pay: Int

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: "mappin.circle.fill")
                .font(.title2)
                .foregroundStyle(.red)
            Text("$\(pay)/ч")
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
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(shift.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(shift.status.title)
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(shift.status == .open ? Color.blue.opacity(0.15) : Color.gray.opacity(0.2))
                        .clipShape(Capsule())
                }

                Text(shift.details)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack {
                    Label("$\(shift.pay)/ч", systemImage: "dollarsign.circle")
                    Label("\(shift.durationHours) ч", systemImage: "clock")
                    Label("\(accepted)/\(shift.requiredWorkers)", systemImage: "person.3")
                    if let employer {
                        Label(employer.name, systemImage: "building.2")
                            .lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
