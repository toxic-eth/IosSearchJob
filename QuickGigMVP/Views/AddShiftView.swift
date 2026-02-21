import SwiftUI
import CoreLocation

struct AddShiftView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let centerCoordinate: CLLocationCoordinate2D

    @State private var title = ""
    @State private var details = ""
    @State private var pay = 100
    @State private var requiredWorkers = 1
    @State private var startDate = Date()
    @State private var endDate = Calendar.current.date(byAdding: .hour, value: 8, to: Date()) ?? Date()
    @State private var latitude = ""
    @State private var longitude = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Опис") {
                    TextField("Назва підробітку", text: $title)
                    TextField("Короткий опис", text: $details, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                    Stepper("Оплата: $\(pay)/год", value: $pay, in: 50...1000, step: 10)
                    Stepper("Потрібно працівників: \(requiredWorkers)", value: $requiredWorkers, in: 1...30)
                }

                Section("Час") {
                    DatePicker("Початок", selection: $startDate)
                    DatePicker("Завершення", selection: $endDate)
                }

                Section("Точка на мапі") {
                    TextField("Широта", text: $latitude)
                        .keyboardType(.decimalPad)
                    TextField("Довгота", text: $longitude)
                        .keyboardType(.decimalPad)
                    Text("Якщо точка поза Україною, автоматично буде Київ")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                            pay: pay,
                            startDate: startDate,
                            endDate: max(endDate, startDate),
                            coordinate: parsedCoordinate ?? centerCoordinate,
                            requiredWorkers: requiredWorkers
                        )
                        dismiss()
                    }
                }
            }
            .onAppear {
                latitude = String(format: "%.5f", centerCoordinate.latitude)
                longitude = String(format: "%.5f", centerCoordinate.longitude)
            }
        }
    }

    private var parsedCoordinate: CLLocationCoordinate2D? {
        guard
            let lat = Double(latitude.replacingOccurrences(of: ",", with: ".")),
            let lon = Double(longitude.replacingOccurrences(of: ",", with: "."))
        else {
            return nil
        }

        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}
