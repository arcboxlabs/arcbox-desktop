/// Detail tab for images
enum ImageDetailTab: String, CaseIterable, Identifiable {
    case info = "Info"
    case terminal = "Terminal"
    case files = "Files"

    var id: String { rawValue }
}

/// Sort field for images
enum ImageSortField: String, CaseIterable {
    case name = "Name"
    case dateCreated = "Date Created"
    case size = "Size"
}
