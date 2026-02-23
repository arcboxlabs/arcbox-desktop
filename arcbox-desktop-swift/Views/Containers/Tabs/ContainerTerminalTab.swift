import SwiftUI

/// Terminal tab showing an interactive-style terminal view
struct ContainerTerminalTab: View {
    let container: ContainerViewModel

    @State private var inputText = ""
    @State private var terminalLines: [TerminalLine] = []
    @State private var debugShell = false

    var body: some View {
        VStack(spacing: 0) {
            // Terminal toolbar
            HStack {
                Spacer()
                Toggle("Debug Shell", isOn: $debugShell)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            // Terminal content
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            // Welcome message
                            if debugShell {
                                Text(
                                    "Debug Shell provides useful commands & tools, making it easy to debug any container (even minimal/distroless)."
                                )
                                .foregroundStyle(Color.yellow)
                                .padding(.bottom, 2)

                                Text(
                                    "It also allows installing over 80,000 packages."
                                )
                                .foregroundStyle(Color.yellow)
                                .padding(.bottom, 12)
                            }

                            // Output lines
                            ForEach(terminalLines) { line in
                                Text(line.text)
                                    .foregroundStyle(line.color)
                                    .id(line.id)
                            }

                            // Current prompt line with input
                            HStack(spacing: 0) {
                                Text("/ # ")
                                    .foregroundStyle(Color.white)
                                TextField("", text: $inputText)
                                    .textFieldStyle(.plain)
                                    .foregroundStyle(Color.white)
                                    .onSubmit {
                                        submitCommand()
                                    }
                            }
                            .id("prompt")
                        }
                        .font(.system(size: 13, design: .monospaced))
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onChange(of: terminalLines.count) {
                        proxy.scrollTo("prompt", anchor: .bottom)
                    }
                }
            }
            .background(Color(red: 0.1, green: 0.1, blue: 0.1))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(red: 0.1, green: 0.1, blue: 0.1))
    }

    private func submitCommand() {
        let cmd = inputText.trimmingCharacters(in: .whitespaces)
        guard !cmd.isEmpty else { return }

        // Add the command line to output
        terminalLines.append(
            TerminalLine(text: "/ # \(cmd)", color: .white)
        )

        // Simulate basic command responses
        let response = simulateCommand(cmd)
        for line in response {
            terminalLines.append(line)
        }

        inputText = ""
    }

    private func simulateCommand(_ cmd: String) -> [TerminalLine] {
        switch cmd.lowercased() {
        case "ls":
            return [
                TerminalLine(
                    text:
                        "bin   dev   docker-entrypoint.d   docker-entrypoint.sh   etc   home   lib   media   mnt   opt   proc   root   run   sbin   srv   sys   tmp   usr   var",
                    color: .white)
            ]
        case "whoami":
            return [TerminalLine(text: "root", color: .white)]
        case "hostname":
            return [TerminalLine(text: container.id, color: .white)]
        case "pwd":
            return [TerminalLine(text: "/", color: .white)]
        case "uname -a", "uname":
            return [
                TerminalLine(
                    text: "Linux \(container.id) 6.6.12-linuxkit #1 SMP aarch64 GNU/Linux",
                    color: .white)
            ]
        case "cat /etc/os-release":
            return [
                TerminalLine(
                    text: "PRETTY_NAME=\"Debian GNU/Linux 12 (bookworm)\"", color: .white),
                TerminalLine(text: "NAME=\"Debian GNU/Linux\"", color: .white),
                TerminalLine(text: "VERSION_ID=\"12\"", color: .white),
            ]
        default:
            return [
                TerminalLine(text: "sh: \(cmd): not found", color: Color.red.opacity(0.8))
            ]
        }
    }
}

struct TerminalLine: Identifiable {
    let id = UUID()
    let text: String
    let color: Color
}
