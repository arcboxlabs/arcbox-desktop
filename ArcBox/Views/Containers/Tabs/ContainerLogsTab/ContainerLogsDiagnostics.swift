import Foundation

#if DEBUG
    /// Counts the two paths whose cost once grew with the buffer, so the batch tests
    /// assert they stay off the per-batch path instead of inferring it from time.
    ///
    /// Off until a test arms it: a Debug session of the app records nothing, so the
    /// counters neither grow nor cost on the path they measure. Main-actor state like
    /// its call sites; the module's default isolation holds callers to that. Release
    /// builds compile the call sites out.
    enum ContainerLogsDiagnostics {
        private(set) static var isRecording = false
        /// Full passes of the filter over the buffer in `ContainerLogsModel.filteredEntries`.
        private(set) static var filterRescans = 0
        /// Scrolls following asked for, by target: the end marker, or anything else.
        private(set) static var scrollsToEnd = 0
        private(set) static var scrollsElsewhere = 0

        /// Zeroes the counts and records from here on.
        static func startRecording() {
            filterRescans = 0
            scrollsToEnd = 0
            scrollsElsewhere = 0
            isRecording = true
        }

        static func stopRecording() {
            isRecording = false
        }

        static func recordFilterRescan() {
            guard isRecording else { return }
            filterRescans += 1
        }

        static func recordScroll(to target: AnyHashable) {
            guard isRecording else { return }
            if target == AnyHashable(ContainerLogsContent.endID) {
                scrollsToEnd += 1
            } else {
                scrollsElsewhere += 1
            }
        }
    }
#endif
