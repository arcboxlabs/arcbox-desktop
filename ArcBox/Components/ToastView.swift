import SwiftUI

/// Lightweight toast banner that slides in from the top and auto-dismisses.
struct ToastView: View {
    let message: String
    var icon: String = "exclamationmark.triangle.fill"
    var onDismiss: () -> Void = {}

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColors.error)

            Text(message)
                .font(.system(size: 12))
                .lineLimit(2)
                .foregroundStyle(AppColors.text)

            Spacer(minLength: 0)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(AppColors.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppColors.error.opacity(0.3), lineWidth: 1)
        }
        .padding(.horizontal, 16)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

/// View modifier that shows a toast when `message` is non-nil.
struct ToastModifier: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let msg = message {
                ToastView(message: msg) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        message = nil
                    }
                }
                .task {
                    try? await Task.sleep(for: .seconds(4))
                    if !Task.isCancelled {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            message = nil
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
        .animation(.spring(duration: 0.3), value: message != nil)
    }
}

extension View {
    /// Show an error toast that auto-dismisses after 4 seconds.
    func errorToast(message: Binding<String?>) -> some View {
        modifier(ToastModifier(message: message))
    }
}
