import SwiftUI

/// Terminal tab showing an interactive-style terminal view for images
struct ImageTerminalTab: View {
    let image: ImageViewModel

    @State private var inputText = ""
    @State private var terminalLines: [TerminalLine] = []

    var body: some View {
        VStack(spacing: 0) {
            // Terminal content
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            // Welcome message
                            Text("Interactive shell for image \(image.fullName)")
                                .foregroundStyle(Color.cyan)
                                .padding(.bottom, 8)

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

        terminalLines.append(
            TerminalLine(text: "/ # \(cmd)", color: .white)
        )

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
                    text: "bin   dev   etc   home   lib   media   mnt   opt   proc   root   run   sbin   srv   sys   tmp   usr   var",
                    color: .white)
            ]
        case "whoami":
            return [TerminalLine(text: "root", color: .white)]
        case "hostname":
            return [TerminalLine(text: String(image.id.prefix(12)), color: .white)]
        case "pwd":
            return [TerminalLine(text: "/", color: .white)]
        case "uname -a", "uname":
            return [
                TerminalLine(
                    text: "Linux \(String(image.id.prefix(12))) 6.6.12-linuxkit #1 SMP \(image.architecture) GNU/Linux",
                    color: .white)
            ]
        case "cat /etc/os-release":
            return [
                TerminalLine(text: "PRETTY_NAME=\"\(image.repository) \(image.tag)\"", color: .white),
                TerminalLine(text: "NAME=\"\(image.repository)\"", color: .white),
                TerminalLine(text: "VERSION=\"\(image.tag)\"", color: .white),
            ]
        case "arch":
            return [TerminalLine(text: image.architecture, color: .white)]
        default:
            return [
                TerminalLine(text: "sh: \(cmd): not found", color: Color.red.opacity(0.8))
            ]
        }
    }
}
