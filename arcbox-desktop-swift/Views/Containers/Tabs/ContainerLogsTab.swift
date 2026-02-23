import SwiftUI

/// Logs tab showing container log output
struct ContainerLogsTab: View {
    let container: ContainerViewModel

    @State private var searchText = ""
    @State private var logEntries: [LogEntry] = []

    var filteredEntries: [LogEntry] {
        if searchText.isEmpty {
            return logEntries
        }
        return logEntries.filter {
            $0.message.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar with search and actions
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(AppColors.textSecondary)
                        .font(.system(size: 12))
                    TextField("Search", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(AppColors.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                Spacer()

                Button(action: copyLogs) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Copy logs")

                Button(action: clearLogs) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Clear logs")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Log content
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filteredEntries) { entry in
                            Text(entry.message)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(AppColors.text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 1)
                                .textSelection(.enabled)
                                .id(entry.id)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onChange(of: logEntries.count) {
                    if let last = logEntries.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
        .onAppear {
            loadSampleLogs()
        }
    }

    private func copyLogs() {
        let text = filteredEntries.map(\.message).joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func clearLogs() {
        logEntries.removeAll()
    }

    private func loadSampleLogs() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:mm:ss"

        let baseDate = Date().addingTimeInterval(-300)
        let imageName = container.image.components(separatedBy: ":").first ?? container.image

        var entries: [LogEntry] = []

        switch imageName {
        case let name where name.contains("nginx"):
            // nginx-style logs
            let nginxStartup = [
                "nginx: [notice] 1#1: using the \"epoll\" event method",
                "nginx: [notice] 1#1: nginx/1.25.3",
                "nginx: [notice] 1#1: built by gcc 12.2.0 (Debian 12.2.0-14)",
                "nginx: [notice] 1#1: OS: Linux 6.6.12-linuxkit",
            ]
            for (i, msg) in nginxStartup.enumerated() {
                let ts = formatter.string(from: baseDate.addingTimeInterval(Double(i)))
                entries.append(LogEntry(message: "\(ts) \(msg)"))
            }
            for i in 1...41 {
                let ts = formatter.string(from: baseDate.addingTimeInterval(Double(i + 4)))
                entries.append(
                    LogEntry(
                        message: "\(ts) nginx: [notice] 1#1: start worker process \(i)"
                    ))
            }
            let accessLogs = [
                "\"GET / HTTP/1.1\" 200 8702 \"-\" \"Mozilla/5.0\"",
                "\"GET /assets/stylesheets/application.css HTTP/1.1\" 200",
                "\"GET /assets/stylesheets/application-dark.css HTTP/1.1\" 200",
                "\"GET /assets/javascripts/modernizr.js HTTP/1.1\" 200",
                "\"GET /css/styles.css HTTP/1.1\" 200",
                "\"GET /assets/fonts/material-icons.woff2 HTTP/1.1\" 200",
                "\"GET /assets/fonts/font-awesome.woff2 HTTP/1.1\" 200",
                "\"GET /assets/javascripts/application.js HTTP/1.1\" 200",
                "\"GET /css/dark-mode.css HTTP/1.1\" 200",
                "\"GET /images/docker-labs-logo.svg HTTP/1.1\" 200",
                "\"GET /tutorial/ HTTP/1.1\" 200 1024",
                "\"GET /tutorial/tutorial-in-dashboard/ HTTP/1.1\" 200",
                "\"GET /assets/fonts/specimen/MaterialIcons.woff2 HTTP/1.1\" 200",
                "\"GET /fonts/hinted-Geomanist-Book.woff2 HTTP/1.1\" 200",
                "\"GET /assets/fonts/specimen/ForkAwesome.woff2 HTTP/1.1\" 200",
                "\"GET /assets/images/favicon.png HTTP/1.1\" 200",
            ]
            let accessTs = formatter.string(
                from: baseDate.addingTimeInterval(Double(nginxStartup.count + 42)))
            for log in accessLogs {
                entries.append(
                    LogEntry(
                        message:
                            "192.168.215.1 - - [\(accessTs) +0000] \(log)"
                    ))
            }

        case let name where name.contains("node"):
            let nodeLogs = [
                "Server starting...",
                "Loading environment variables",
                "Connected to database",
                "API routes registered",
                "Server listening on port 3000",
                "GET /api/health 200 12ms",
                "GET /api/users 200 45ms",
                "POST /api/auth/login 200 89ms",
            ]
            for (i, msg) in nodeLogs.enumerated() {
                let ts = formatter.string(from: baseDate.addingTimeInterval(Double(i * 2)))
                entries.append(LogEntry(message: "\(ts) [info] \(msg)"))
            }

        case let name where name.contains("postgres"):
            let pgLogs = [
                "PostgreSQL init process complete; ready for start up.",
                "LOG:  database system is ready to accept connections",
                "LOG:  listening on IPv4 address \"0.0.0.0\", port 5432",
                "LOG:  listening on IPv6 address \"::\", port 5432",
                "LOG:  checkpoint starting: time",
                "LOG:  checkpoint complete",
            ]
            for (i, msg) in pgLogs.enumerated() {
                let ts = formatter.string(from: baseDate.addingTimeInterval(Double(i * 3)))
                entries.append(LogEntry(message: "\(ts) \(msg)"))
            }

        default:
            entries.append(LogEntry(message: "No logs available"))
        }

        logEntries = entries
    }
}

struct LogEntry: Identifiable {
    let id = UUID()
    let message: String
}
