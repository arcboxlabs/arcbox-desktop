import SwiftUI

/// Detail tab for images
enum ImageDetailTab: String, CaseIterable, Identifiable {
    case info = "Info"
    case terminal = "Terminal"
    case files = "Files"

    var id: String { rawValue }
}

/// Image list state
@Observable
class ImagesViewModel {
    var images: [ImageViewModel] = []
    var selectedID: String? = nil
    var activeTab: ImageDetailTab = .info
    var listWidth: CGFloat = 380

    var totalSize: String {
        let bytes: UInt64 = images.map(\.sizeBytes).reduce(0, +)
        let gb = Double(bytes) / 1_000_000_000.0
        if gb >= 1.0 {
            return String(format: "%.2f GB total", gb)
        }
        let mb = Double(bytes) / 1_000_000.0
        return String(format: "%.0f MB total", mb)
    }

    var selectedImage: ImageViewModel? {
        guard let id = selectedID else { return nil }
        return images.first { $0.id == id }
    }

    func selectImage(_ id: String) {
        selectedID = id
    }

    func loadSampleData() {
        images = SampleData.images
    }
}
