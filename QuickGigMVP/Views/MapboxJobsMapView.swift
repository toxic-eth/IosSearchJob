import SwiftUI
import CoreLocation

#if canImport(MapboxMaps)
import MapboxMaps

struct MapboxCameraUpdate {
    let id: UUID
    let center: CLLocationCoordinate2D
    let zoom: CGFloat
    let bearing: CLLocationDirection
    let pitch: CGFloat
    let animated: Bool
    let duration: Double
}

struct MapboxJobsMapView: UIViewRepresentable {
    var shifts: [JobShift]
    var focusedShiftId: UUID?
    var drawnPolygon: [CLLocationCoordinate2D]
    var cameraUpdate: MapboxCameraUpdate?
    var pointsToConvert: [CGPoint]
    var isDarkTheme: Bool
    var onShiftTap: (JobShift) -> Void
    var onCameraChange: (CLLocationCoordinate2D, CLLocationDirection, CGFloat, CGFloat) -> Void
    var onConvertedPoints: ([CLLocationCoordinate2D]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> MapView {
        let camera = CameraOptions(center: shifts.first?.coordinate, zoom: 11.8, bearing: 0, pitch: 0)
        let options = MapInitOptions(cameraOptions: camera, styleURI: .streets)
        let mapView = MapView(frame: .zero, mapInitOptions: options)

        context.coordinator.applyThemeIfNeeded(isDarkTheme, on: mapView)
        var ornaments = mapView.ornaments.options
        ornaments.compass.visibility = .hidden
        ornaments.scaleBar.visibility = .hidden
        ornaments.logo.position = .bottomLeading
        ornaments.logo.margins = CGPoint(x: 40, y: -39)
        ornaments.attributionButton.position = .bottomTrailing
        ornaments.attributionButton.margins = CGPoint(x: 40, y: -39)
        ornaments.attributionButton.tintColor = UIColor.white.withAlphaComponent(0.55)
        mapView.ornaments.options = ornaments
        mapView.ornaments.logoView.alpha = 0.0
        mapView.ornaments.attributionButton.alpha = 0.0

        mapView.location.options.puckType = .puck2D()
        context.coordinator.pointManager = mapView.annotations.makePointAnnotationManager(
            clusterOptions: Coordinator.clusterOptions(),
            onClusterTap: { [weak mapView] context in
                guard let mapView else { return }
                let current = mapView.mapboxMap.cameraState
                let targetZoom = max(current.zoom + 0.8, (context.expansionZoom ?? current.zoom) + 0.35)
                let camera = CameraOptions(
                    center: context.coordinate,
                    zoom: targetZoom,
                    bearing: current.bearing,
                    pitch: current.pitch
                )
                mapView.camera.ease(to: camera, duration: 0.28)
            }
        )
        context.coordinator.polygonManager = mapView.annotations.makePolygonAnnotationManager()

        context.coordinator.cameraCancelable = mapView.mapboxMap.onCameraChanged.observe { [weak mapView] _ in
            guard let mapView else { return }
            let state = mapView.mapboxMap.cameraState
            onCameraChange(state.center, state.bearing, state.pitch, state.zoom)
        }
        context.coordinator.styleErrorCancelable = mapView.mapboxMap.onMapLoadingError.observe { _ in
            mapView.mapboxMap.loadStyle(.streets)
        }

        return mapView
    }

    func updateUIView(_ mapView: MapView, context: Context) {
        context.coordinator.parent = self
        applyThemeStyle(on: mapView, using: context.coordinator)
        updateShiftAnnotations(using: context.coordinator)
        updateDrawnPolygon(using: context.coordinator)
        applyCameraUpdateIfNeeded(on: mapView, using: context.coordinator)
        convertPointsIfNeeded(on: mapView, using: context.coordinator)
    }

    static func dismantleUIView(_ uiView: MapView, coordinator: Coordinator) {
        coordinator.cameraCancelable?.cancel()
        coordinator.styleErrorCancelable?.cancel()
    }

    private func applyThemeStyle(on mapView: MapView, using coordinator: Coordinator) {
        coordinator.applyThemeIfNeeded(isDarkTheme, on: mapView)
    }

    private func updateShiftAnnotations(using coordinator: Coordinator) {
        guard let pointManager = coordinator.pointManager else { return }
        let annotationsFingerprint = shifts.reduce(into: Hasher()) { hasher, shift in
            hasher.combine(shift.id)
            hasher.combine(shift.pay)
            hasher.combine(shift.coordinate.latitude.bitPattern)
            hasher.combine(shift.coordinate.longitude.bitPattern)
        }.finalize()
        let focusedId = focusedShiftId
        let stateFingerprint = annotationsFingerprint ^ focusedId.hashValue
        guard coordinator.lastAnnotationsFingerprint != stateFingerprint else { return }
        coordinator.lastAnnotationsFingerprint = stateFingerprint

        pointManager.iconAllowOverlap = true
        pointManager.iconIgnorePlacement = true

        let annotations: [PointAnnotation] = shifts.map { shift in
            var annotation = PointAnnotation(coordinate: shift.coordinate)
            annotation.image = .init(
                image: Coordinator.pinImage(pay: shift.pay, isFocused: shift.id == focusedShiftId),
                name: "shift-pin-\(shift.id)-\(shift.pay)-\(shift.id == focusedShiftId)"
            )
            annotation.iconAnchor = .bottom
            annotation.iconSize = 1.0
            annotation.iconOffset = [0, 0]
            annotation.tapHandler = { _ in
                onShiftTap(shift)
                return true
            }
            return annotation
        }

        pointManager.annotations = annotations
    }

    private func updateDrawnPolygon(using coordinator: Coordinator) {
        guard let polygonManager = coordinator.polygonManager else { return }
        guard drawnPolygon.count >= 3 else {
            polygonManager.annotations = []
            return
        }

        let polygon = Polygon([drawnPolygon])
        var annotation = PolygonAnnotation(polygon: polygon)
        annotation.fillColor = StyleColor(UIColor.systemPurple.withAlphaComponent(0.14))
        annotation.fillOutlineColor = StyleColor(UIColor.systemPurple.withAlphaComponent(0.95))
        polygonManager.annotations = [annotation]
    }

    private func applyCameraUpdateIfNeeded(on mapView: MapView, using coordinator: Coordinator) {
        guard let cameraUpdate else { return }
        guard coordinator.lastCameraUpdateId != cameraUpdate.id else { return }
        coordinator.lastCameraUpdateId = cameraUpdate.id

        let camera = CameraOptions(
            center: cameraUpdate.center,
            zoom: cameraUpdate.zoom,
            bearing: cameraUpdate.bearing,
            pitch: cameraUpdate.pitch
        )
        if cameraUpdate.animated {
            mapView.camera.ease(to: camera, duration: cameraUpdate.duration)
        } else {
            mapView.mapboxMap.setCamera(to: camera)
        }
    }

    private func convertPointsIfNeeded(on mapView: MapView, using coordinator: Coordinator) {
        guard !pointsToConvert.isEmpty else { return }
        let fingerprint = pointsToConvert.reduce(into: Hasher()) { hasher, point in
            hasher.combine(point.x.bitPattern)
            hasher.combine(point.y.bitPattern)
        }.finalize()
        guard fingerprint != coordinator.lastConversionFingerprint else { return }
        coordinator.lastConversionFingerprint = fingerprint

        let coordinates = pointsToConvert.map { mapView.mapboxMap.coordinate(for: $0) }
        onConvertedPoints(coordinates)
    }

    final class Coordinator {
        var parent: MapboxJobsMapView
        var pointManager: PointAnnotationManager?
        var polygonManager: PolygonAnnotationManager?
        var cameraCancelable: Cancelable?
        var styleErrorCancelable: Cancelable?
        var lastCameraUpdateId: UUID?
        var lastConversionFingerprint: Int?
        var lastAnnotationsFingerprint: Int?
        var lastThemeIsDark: Bool?

        init(parent: MapboxJobsMapView) {
            self.parent = parent
        }

        func applyThemeIfNeeded(_ isDark: Bool, on mapView: MapView) {
            guard lastThemeIsDark != isDark else { return }
            lastThemeIsDark = isDark
            mapView.mapboxMap.mapStyle = .standard(
                lightPreset: isDark ? .night : .day,
                showPointOfInterestLabels: false,
                showTransitLabels: false
            )
        }

        static func clusterOptions() -> ClusterOptions {
            ClusterOptions(
                circleRadius: .constant(22),
                circleColor: .constant(StyleColor(UIColor(red: 0.42, green: 0.22, blue: 0.78, alpha: 0.92))),
                textColor: .constant(StyleColor(UIColor.white)),
                textSize: .constant(12),
                textField: .expression(Exp(.get) { "point_count" }),
                clusterRadius: 50,
                clusterMaxZoom: 14,
                clusterMinPoints: 2
            )
        }

        static func pinImage(pay: Int, isFocused: Bool) -> UIImage {
            let bubbleText = "\(pay) грн/год"
            let textColor = UIColor.white
            let accent = isFocused
                ? UIColor(red: 0.78, green: 0.42, blue: 1.0, alpha: 1.0)
                : UIColor(red: 0.66, green: 0.34, blue: 0.94, alpha: 1.0)
            let bubbleFill = UIColor(red: 0.10, green: 0.10, blue: 0.16, alpha: 0.90)
            let textAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: textColor
            ]
            let textSize = (bubbleText as NSString).size(withAttributes: textAttributes)
            let bubbleWidth = max(70, textSize.width + 18)
            let width = bubbleWidth
            let height: CGFloat = 46
            let bubbleRect = CGRect(x: 0, y: 0, width: bubbleWidth, height: 22)

            let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
            return renderer.image { ctx in
                let cg = ctx.cgContext

                let bubblePath = UIBezierPath(roundedRect: bubbleRect, cornerRadius: 11)
                cg.setFillColor(bubbleFill.cgColor)
                bubblePath.fill()
                cg.setStrokeColor(accent.withAlphaComponent(0.85).cgColor)
                cg.setLineWidth(1.2)
                bubblePath.stroke()

                let textRect = CGRect(
                    x: (bubbleWidth - textSize.width) / 2,
                    y: (bubbleRect.height - textSize.height) / 2,
                    width: textSize.width,
                    height: textSize.height
                )
                (bubbleText as NSString).draw(in: textRect, withAttributes: textAttributes)

                let pinCenter = CGPoint(x: width / 2, y: bubbleRect.maxY + 11.5)
                let outerRadius: CGFloat = isFocused ? 7.5 : 6.5
                let innerRadius: CGFloat = 2.6

                cg.setFillColor(UIColor.black.withAlphaComponent(0.55).cgColor)
                cg.addEllipse(in: CGRect(x: pinCenter.x - outerRadius, y: pinCenter.y - outerRadius, width: outerRadius * 2, height: outerRadius * 2))
                cg.fillPath()
                cg.setStrokeColor(accent.cgColor)
                cg.setLineWidth(1.6)
                cg.strokeEllipse(in: CGRect(x: pinCenter.x - outerRadius, y: pinCenter.y - outerRadius, width: outerRadius * 2, height: outerRadius * 2))

                cg.setFillColor(textColor.cgColor)
                cg.addEllipse(in: CGRect(x: pinCenter.x - innerRadius, y: pinCenter.y - innerRadius, width: innerRadius * 2, height: innerRadius * 2))
                cg.fillPath()
            }
        }
    }
}

#else

struct MapboxCameraUpdate {
    let id: UUID
    let center: CLLocationCoordinate2D
    let zoom: CGFloat
    let bearing: CLLocationDirection
    let pitch: CGFloat
    let animated: Bool
    let duration: Double
}

struct MapboxJobsMapView: View {
    var shifts: [JobShift]
    var focusedShiftId: UUID?
    var drawnPolygon: [CLLocationCoordinate2D]
    var cameraUpdate: MapboxCameraUpdate?
    var pointsToConvert: [CGPoint]
    var isDarkTheme: Bool
    var onShiftTap: (JobShift) -> Void
    var onCameraChange: (CLLocationCoordinate2D, CLLocationDirection, CGFloat, CGFloat) -> Void
    var onConvertedPoints: ([CLLocationCoordinate2D]) -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.12)
            Text("Mapbox SDK not available")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onChange(of: pointsToConvert.count) { _, _ in
            onConvertedPoints([])
        }
    }
}

#endif
