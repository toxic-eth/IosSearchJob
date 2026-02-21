import SwiftUI
import CoreLocation

struct AddShiftView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let centerCoordinate: CLLocationCoordinate2D

    @State private var title = ""
    @State private var details = ""
    @State private var pay = 100
    @State private var startDate = Date()
    @State private var endDate = Calendar.current.date(byAdding: .hour, value: 8, to: Date()) ?? Date()
    @State private var latitude = ""
    @State private var longitude = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Описание") {
                    TextField("Название подработки", text: $title)
                    TextField("Краткое описание", text: $details)
                    Stepper("Оплата: $\(pay)/ч", value: $pay, in: 1...1000)
                }

                Section("Время") {
                    DatePicker("Начало", selection: $startDate)
                    DatePicker("Окончание", selection: $endDate)
                }

                Section("Точка на карте") {
                    TextField("Широта", text: $latitude)
                        .keyboardType(.decimalPad)
                    TextField("Долгота", text: $longitude)
                        .keyboardType(.decimalPad)
                    Text("Пусто = центр карты")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Новая смена")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Сохранить") {
                        let coordinate = parsedCoordinate ?? centerCoordinate
                        appState.addShift(
                            title: title.isEmpty ? "Без названия" : title,
                            details: details,
                            pay: pay,
                            startDate: startDate,
                            endDate: max(endDate, startDate),
                            coordinate: coordinate
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
