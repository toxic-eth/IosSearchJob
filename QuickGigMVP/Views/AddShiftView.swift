import SwiftUI
import CoreLocation
import MapKit
import Combine

struct AddShiftView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let centerCoordinate: CLLocationCoordinate2D

    @State private var title = ""
    @State private var details = ""
    @State private var payText = "100"
    @State private var requiredWorkers = 1
    @State private var workFormat: WorkFormat = .offline
    @State private var startDate = Date()
    @State private var endDate = Calendar.current.date(byAdding: .hour, value: 8, to: Date()) ?? Date()
    @State private var address = ""
    @State private var pickedCoordinate: CLLocationCoordinate2D
    @State private var geocodingError = ""
    @State private var isGeocoding = false
    @State private var showLocationPicker = false

    private let geocoder = CLGeocoder()

    init(centerCoordinate: CLLocationCoordinate2D) {
        self.centerCoordinate = centerCoordinate
        _pickedCoordinate = State(initialValue: centerCoordinate)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Опис") {
                    TextField("Назва підробітку", text: $title)
                    TextField("Короткий опис", text: $details, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                    TextField("Оплата, грн/год", text: $payText)
                        .keyboardType(.numberPad)
                    Stepper("Потрібно працівників: \(requiredWorkers)", value: $requiredWorkers, in: 1...30)
                }

                Section("Формат") {
                    Picker("Тип роботи", selection: $workFormat) {
                        ForEach(WorkFormat.allCases) { format in
                            Text(format.title).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Час") {
                    DatePicker("Початок", selection: $startDate)
                    DatePicker("Завершення", selection: $endDate)
                }

                Section("Адреса") {
                    TextField("Адреса роботи", text: $address, axis: .vertical)
                        .lineLimit(2, reservesSpace: true)

                    Button("Знайти на карті") {
                        showLocationPicker = true
                    }

                    if !geocodingError.isEmpty {
                        Text(geocodingError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section("Локація") {
                    Text(address.isEmpty ? "Адресу ще не обрано" : address)
                        .foregroundStyle(address.isEmpty ? .secondary : .primary)
                }
            }
            .navigationTitle("Нова зміна")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Скасувати") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Зберегти") {
                        appState.addShift(
                            title: title.isEmpty ? "Без назви" : title,
                            details: details,
                            address: address,
                            pay: parsedPay,
                            startDate: startDate,
                            endDate: max(endDate, startDate),
                            coordinate: pickedCoordinate,
                            workFormat: workFormat,
                            requiredWorkers: requiredWorkers
                        )
                        dismiss()
                    }
                    .disabled(parsedPay < 1)
                }
            }
            .sheet(isPresented: $showLocationPicker) {
                LocationPickerView(
                    initialCoordinate: pickedCoordinate
                ) { coordinate, resolvedAddress in
                    pickedCoordinate = coordinate
                    if !resolvedAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        address = resolvedAddress
                    }
                }
            }
            .onAppear {
                reverseGeocode(coordinate: centerCoordinate)
            }
        }
    }

    private var parsedPay: Int {
        Int(payText.filter(\.isNumber)) ?? 0
    }

    private func setPickedCoordinate(_ coordinate: CLLocationCoordinate2D) {
        pickedCoordinate = coordinate
    }

    private func geocodeAddress() {
        let query = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        isGeocoding = true
        geocodingError = ""

        geocoder.geocodeAddressString("\(query), Україна") { placemarks, error in
            isGeocoding = false
            if let location = placemarks?.first?.location {
                setPickedCoordinate(location.coordinate)
                if let normalized = formattedAddress(from: placemarks?.first) {
                    address = normalized
                }
                return
            }
            geocodingError = error?.localizedDescription ?? "Адресу не знайдено"
        }
    }

    private func reverseGeocode(coordinate: CLLocationCoordinate2D) {
        isGeocoding = true
        geocoder.reverseGeocodeLocation(CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) { placemarks, _ in
            isGeocoding = false
            if let normalized = formattedAddress(from: placemarks?.first) {
                address = normalized
                geocodingError = ""
            }
        }
    }

    private func formattedAddress(from placemark: CLPlacemark?) -> String? {
        guard let placemark else { return nil }
        let components = [
            placemark.locality,
            placemark.thoroughfare,
            placemark.subThoroughfare
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !components.isEmpty else { return nil }
        return components.joined(separator: ", ")
    }
}

private struct LocationPickerView: View {
    @Environment(\.dismiss) private var dismiss

    let initialCoordinate: CLLocationCoordinate2D
    let onConfirm: (CLLocationCoordinate2D, String) -> Void

    @State private var cameraPosition: MapCameraPosition
    @State private var centerCoordinate: CLLocationCoordinate2D
    @State private var resolvedAddress = ""
    @State private var isPinLifted = false
    @State private var isResolvingAddress = false
    @State private var pendingResolveTask: DispatchWorkItem?
    @State private var searchText = ""
    @StateObject private var searchModel = AddressSearchModel()
    @FocusState private var isSearchFocused: Bool
    private let geocoder = CLGeocoder()

    init(initialCoordinate: CLLocationCoordinate2D, onConfirm: @escaping (CLLocationCoordinate2D, String) -> Void) {
        self.initialCoordinate = initialCoordinate
        self.onConfirm = onConfirm
        _centerCoordinate = State(initialValue: initialCoordinate)
        _cameraPosition = State(initialValue: .region(
            MKCoordinateRegion(
                center: initialCoordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.018, longitudeDelta: 0.018)
            )
        ))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Map(position: $cameraPosition)
                    .onMapCameraChange(frequency: .continuous) { context in
                        centerCoordinate = context.region.center
                        liftPinTemporarily()
                    }

                CenterPinView(isLifted: isPinLifted)
                    .allowsHitTesting(false)

                VStack {
                    VStack(spacing: 0) {
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)
                            TextField("Пошук адреси", text: $searchText)
                                .textInputAutocapitalization(.words)
                                .autocorrectionDisabled(true)
                                .focused($isSearchFocused)
                                .onChange(of: searchText) { _, newValue in
                                    searchModel.updateQuery(newValue)
                                }
                            if !searchText.isEmpty {
                                Button {
                                    searchText = ""
                                    searchModel.clear()
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                        if !searchModel.results.isEmpty && isSearchFocused {
                            ScrollView {
                                VStack(spacing: 0) {
                                    ForEach(searchModel.results.indices, id: \.self) { idx in
                                        let item = searchModel.results[idx]
                                        Button {
                                            selectSearchResult(item)
                                        } label: {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(item.title)
                                                    .font(.subheadline)
                                                    .foregroundStyle(.primary)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                                if !item.subtitle.isEmpty {
                                                    Text(item.subtitle)
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                        .frame(maxWidth: .infinity, alignment: .leading)
                                                }
                                            }
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 9)
                                        }
                                        .buttonStyle(.plain)

                                        if idx < searchModel.results.count - 1 {
                                            Divider().padding(.leading, 12)
                                        }
                                    }
                                }
                            }
                            .frame(maxHeight: 220)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .padding(.top, 8)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 10)

                    Spacer()
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Адреса точки")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(resolvedAddress.isEmpty ? "Визначаємо адресу..." : resolvedAddress)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                }
            }
            .navigationTitle("Вибір точки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Скасувати") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") {
                        onConfirm(centerCoordinate, resolvedAddress)
                        dismiss()
                    }
                }
            }
            .onAppear {
                searchModel.setRegion(center: initialCoordinate)
                resolveAddressDebounced(for: initialCoordinate, immediate: true)
            }
        }
    }

    private func liftPinTemporarily() {
        withAnimation(.easeOut(duration: 0.12)) {
            isPinLifted = true
        }
        resolveAddressDebounced(for: centerCoordinate, immediate: false)
    }

    private func resolveAddressDebounced(for coordinate: CLLocationCoordinate2D, immediate: Bool) {
        pendingResolveTask?.cancel()
        searchModel.setRegion(center: coordinate)
        let work = DispatchWorkItem {
            resolveAddress(for: coordinate)
            withAnimation(.easeInOut(duration: 0.18)) {
                isPinLifted = false
            }
        }
        pendingResolveTask = work
        let delay: TimeInterval = immediate ? 0.01 : 0.35
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func resolveAddress(for coordinate: CLLocationCoordinate2D) {
        guard !isResolvingAddress else { return }
        isResolvingAddress = true
        geocoder.cancelGeocode()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        geocoder.reverseGeocodeLocation(location) { placemarks, _ in
            isResolvingAddress = false
            if let placemark = placemarks?.first {
                let components = [
                    placemark.locality,
                    placemark.thoroughfare,
                    placemark.subThoroughfare
                ]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                if !components.isEmpty {
                    resolvedAddress = components.joined(separator: ", ")
                    return
                }
            }
            resolvedAddress = String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
        }
    }

    private func selectSearchResult(_ completion: MKLocalSearchCompletion) {
        isSearchFocused = false
        searchText = completion.title
        searchModel.clear()

        let request = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: request)
        search.start { response, _ in
            guard let item = response?.mapItems.first else { return }
            let coordinate = item.placemark.coordinate
            centerCoordinate = coordinate
            withAnimation(.easeInOut(duration: 0.28)) {
                cameraPosition = .region(
                    MKCoordinateRegion(
                        center: coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015)
                    )
                )
            }
            resolveAddressDebounced(for: coordinate, immediate: true)
        }
    }
}

private struct CenterPinView: View {
    let isLifted: Bool

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.92))
                    .frame(width: 24, height: 24)
                Circle()
                    .fill(Color.white)
                    .frame(width: 8, height: 8)
            }
            .scaleEffect(isLifted ? 1.2 : 1.0, anchor: .bottom)
            .shadow(color: .black.opacity(0.24), radius: 8, x: 0, y: 3)

            TrianglePointer()
                .fill(Color.purple.opacity(0.92))
                .frame(width: 10, height: 8)
        }
        .offset(y: -16)
        .animation(.spring(response: 0.24, dampingFraction: 0.78), value: isLifted)
    }
}

private struct TrianglePointer: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

private final class AddressSearchModel: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var results: [MKLocalSearchCompletion] = []

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address]
    }

    func updateQuery(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count < 2 {
            results = []
            return
        }
        completer.queryFragment = trimmed
    }

    func setRegion(center: CLLocationCoordinate2D) {
        completer.region = MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: 0.35, longitudeDelta: 0.35)
        )
    }

    func clear() {
        results = []
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        results = Array(completer.results.prefix(8))
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        results = []
    }
}
