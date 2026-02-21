import SwiftUI
import MapKit

struct MainMapView: View {
    @EnvironmentObject private var appState: AppState

    @State private var minPay: Double = 0
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
        appState.shifts.filter { shift in
            Double(shift.pay) >= minPay && Double(shift.durationHours) <= maxDuration
        }
    }

    var body: some View {
        TabView {
            NavigationStack {
                VStack(spacing: 12) {
                    filterPanel

                    Map(position: $cameraPosition) {
                        ForEach(filteredShifts) { shift in
                            Annotation(shift.title, coordinate: shift.coordinate) {
                                Button {
                                    selectedShift = shift
                                } label: {
                                    VStack(spacing: 4) {
                                        Image(systemName: "mappin.circle.fill")
                                            .font(.title2)
                                            .foregroundStyle(.red)
                                        Text("$\(shift.pay)/ч")
                                            .font(.caption2)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(.ultraThinMaterial)
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                        }
                    }
                    .mapControls {
                        MapCompass()
                        MapScaleView()
                    }
                    .frame(maxWidth: .infinity, maxHeight: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    List(filteredShifts) { shift in
                        Button {
                            selectedShift = shift
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(shift.title)
                                    .font(.headline)
                                Text("$\(shift.pay)/ч • \(shift.durationHours) ч")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
                .padding(.horizontal)
                .navigationTitle("Карта подработки")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Выйти") {
                            appState.logout()
                        }
                    }

                    if appState.currentUser?.role == .employer {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("+ Смена") {
                                showCreateShift = true
                            }
                        }
                    }
                }
                .sheet(item: $selectedShift) { shift in
                    ShiftDetailView(shift: shift)
                        .environmentObject(appState)
                }
                .sheet(isPresented: $showCreateShift) {
                    AddShiftView(centerCoordinate: currentMapCenter)
                        .environmentObject(appState)
                }
            }
            .tabItem {
                Label("Карта", systemImage: "map")
            }

            ProfileView()
                .tabItem {
                    Label("Профиль", systemImage: "person.circle")
                }
        }
    }

    private var currentMapCenter: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: 55.7558, longitude: 37.6173)
    }

    private var filterPanel: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Мин. оплата: $\(Int(minPay))/ч")
                Slider(value: $minPay, in: 0...300, step: 10)
            }
            HStack {
                Text("Макс. длительность: \(Int(maxDuration)) ч")
                Slider(value: $maxDuration, in: 1...24, step: 1)
            }
        }
        .font(.caption)
    }
}
