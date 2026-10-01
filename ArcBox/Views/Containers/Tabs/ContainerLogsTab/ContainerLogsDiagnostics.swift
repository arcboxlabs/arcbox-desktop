import Foundation

#if DEBUG
    /// Counts the two paths whose cost once grew with the buffer, so the batch tests
    /// assert they stay off the per-batch path instead of inferring it from time.
    ///
    /// Main-actor state like its call sites; the module's default isolation holds
    /// callers to that. Release builds compile the call sites out.
    enum ContainerLogsDiagnostics {
        /// Full passes of the filter over the buffer in `ContainerLogsModel.filteredEntries`.
        static var filterRescans = 0
        /// Every target `ContainerLogsContent` asked its scroll view to scroll to.
        static var scrollTargets: [AnyHashable] = []

        static func reset() {
            filterRescans = 0
            scrollTargets = []
        }
    }
#endif
