import SwiftUI
import MapKit

struct MainMapView: View {
    @EnvironmentObject private var appState: AppState

    @State private var searchText = ""
    @State private var minPay: Double = 80
    @State private var maxDuration: Double = 12
    @State private var selectedShift: JobShift?
    @State private var showCreateShift = false

    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 55.7558, longitude: 37.6173),
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
        )
    )

    private var filteredShifts: [JobShift] {
        appState.shifts
            .filter { shift in
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

                        Map(position: $cameraPosition) {
                            ForEach(filteredShifts) { shift in
                                Annotation(shift.title, coordinate: shift.coordinate) {
                                    Button {
                                        selectedShift = shift
                                    } label: {
                                        VStack(spacing: 3) {
                                            Image(systemName: "mappin.circle.fill")
                                                .font(.title2)
                                                .foregroundStyle(.red)
                                            Text("$\(shift.pay)/ч")
                                                .font(.caption2.bold())
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(.thickMaterial)
                                                .clipShape(Capsule())
                                        }
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

                        LazyVStack(spacing: 10) {
                            ForEach(filteredShifts) { shift in
                                ShiftRow(shift: shift, employer: appState.user(by: shift.employerId)) {
                                    selectedShift = shift
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 16)
                }
                .navigationTitle("Смены на карте")
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
                    AddShiftView(centerCoordinate: CLLocationCoordinate2D(latitude: 55.7558, longitude: 37.6173))
                        .environmentObject(appState)
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

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Сегодня доступно")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("\(upcomingCount) смен")
                .font(.title2.bold())
            Text("Фильтруйте по оплате, длительности и открывайте детали на карте")
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

private struct ShiftRow: View {
    let shift: JobShift
    let employer: AppUser?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                Text(shift.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(shift.details)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack {
                    Label("$\(shift.pay)/ч", systemImage: "dollarsign.circle")
                    Label("\(shift.durationHours) ч", systemImage: "clock")
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
