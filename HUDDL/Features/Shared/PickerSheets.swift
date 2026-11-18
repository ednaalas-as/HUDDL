import SwiftUI
import PhotosUI
import CoreLocation

// MARK: - Photo source sheet (library / camera / remove)

struct PhotoSourceSheet: View {
    var allowsRemove = false
    let onImage: (UIImage) -> Void
    var onRemove: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(ToastCenter.self) private var toasts
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SheetTitle(title: "Profile photo")
            PhotosPicker(selection: $pickerItem, matching: .images) {
                HStack(spacing: 14) {
                    ZStack { Circle().fill(HColor.avatarBG).frame(width: 40, height: 40)
                        Image(systemName: "photo.on.rectangle").foregroundStyle(HColor.brandNavy) }
                    Text("Choose from library").font(HFont.inter(15, .semibold)).foregroundStyle(HColor.darkText)
                    Spacer()
                }
                .padding(.vertical, 8)
            }
            SheetOptionRow(symbol: "camera.fill", title: "Take a photo") {
                if UIImagePickerController.isSourceTypeAvailable(.camera) { showCamera = true }
                else { toasts.info("Camera isn’t available on this device") }
            }
            if allowsRemove {
                SheetOptionRow(symbol: "trash", title: "Remove photo", destructive: true) { onRemove?(); dismiss() }
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .huddlSheet([.height(allowsRemove ? 300 : 240)])
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    onImage(image); dismiss()
                } else { toasts.error("Couldn’t load that photo. Try another one.") }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in onImage(image); dismiss() }.ignoresSafeArea()
        }
    }
}

/// Native camera capture (UIKit bridge — SwiftUI has no camera view).
struct CameraPicker: UIViewControllerRepresentable {
    var allowsVideo = false
    let onImage: (UIImage) -> Void
    var onVideo: ((URL) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        if allowsVideo { picker.mediaTypes = ["public.image", "public.movie"]; picker.videoMaximumDuration = 60 }
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            else if let url = info[.mediaURL] as? URL { parent.onVideo?(url) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

// MARK: - Home area sheet (current location or list)

struct HomeAreaSheet: View {
    let current: HomeArea?
    let onPick: (HomeArea) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(ToastCenter.self) private var toasts
    @State private var locator = LocationFetcher()

    static let areas: [HomeArea] = [
        Geo.lucena,
        area("Tayabas City", 14.0259, 121.5927),
        area("Sariaya", 13.9634, 121.5264),
        area("Pagbilao", 13.9718, 121.6869),
        area("Lucban", 14.1137, 121.5569),
        area("Candelaria", 13.9311, 121.4233),
    ]
    static func area(_ name: String, _ lat: Double, _ lon: Double) -> HomeArea {
        HomeArea(name: name, latitude: lat, longitude: lon, geohash: Geo.geohash(lat: lat, lon: lon))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SheetTitle(title: "Home area", subtitle: "Discover suggests games within 10 km of here.")
            SheetOptionRow(symbol: "location.fill", title: locator.isLocating ? "Finding your location…" : "Use my current location") {
                Task {
                    do {
                        let area = try await locator.currentArea()
                        onPick(area); dismiss()
                    } catch {
                        toasts.error(error.localizedDescription)
                    }
                }
            }
            Divider().padding(.vertical, 4)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Self.areas, id: \.name) { a in
                        SheetOptionRow(symbol: "mappin.and.ellipse", title: a.name, subtitle: "Quezon",
                                       isSelected: a.name == current?.name) { onPick(a); dismiss() }
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .huddlSheet([.medium, .large])
    }
}

@MainActor
@Observable
final class LocationFetcher: NSObject, CLLocationManagerDelegate {
    var isLocating = false
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?

    struct LocationError: LocalizedError {
        let errorDescription: String?
    }

    func currentArea() async throws -> HomeArea {
        isLocating = true
        defer { isLocating = false }
        manager.delegate = self
        switch manager.authorizationStatus {
        case .denied, .restricted:
            throw LocationError(errorDescription: "Location is off for HUDDL. Turn it on in Settings or pick an area from the list.")
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default: break
        }
        let location = try await withCheckedThrowingContinuation { (c: CheckedContinuation<CLLocation, Error>) in
            continuation = c
            manager.requestLocation()
        }
        let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first
        let name = placemark?.locality ?? placemark?.subAdministrativeArea ?? "Current location"
        let lat = location.coordinate.latitude, lon = location.coordinate.longitude
        return HomeArea(name: name, latitude: lat, longitude: lon, geohash: Geo.geohash(lat: lat, lon: lon))
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            if let l = locations.last { continuation?.resume(returning: l); continuation = nil }
        }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            continuation?.resume(throwing: LocationError(errorDescription: "Couldn’t get your location. Pick an area from the list."))
            continuation = nil
        }
    }
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            if manager.authorizationStatus == .denied {
                continuation?.resume(throwing: LocationError(errorDescription: "Location is off for HUDDL. Pick an area from the list."))
                continuation = nil
            }
        }
    }
}

// MARK: - Sport & skill pickers (shared by Profile setup, Sports & skill)

struct SportChipsGrid: View {
    @Binding var selected: Set<Sport>
    var sports: [Sport] = Sport.allCases
    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(sports) { s in
                SelectChip(text: s.title, isOn: selected.contains(s)) {
                    if selected.contains(s) { selected.remove(s) } else { selected.insert(s) }
                    UISelectionFeedbackGenerator().selectionChanged()
                }
            }
        }
    }
}

/// Simple wrapping layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, width: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > maxW, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing; rowH = max(rowH, s.height); width = max(width, x - spacing)
        }
        return CGSize(width: proposal.width ?? width, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
    }
}
