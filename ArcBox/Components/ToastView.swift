import SwiftUI

/// Lightweight toast banner that slides in from the top and auto-dismisses.
struct ToastView: View {
    let message: String
    var icon: String = "exclamationmark.triangle.fill"
    var onDismiss: () -> Void = {}

    @State private var isVisible = false

    var body: some View {
        if isVisible {
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
                    dismiss()
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

    private func dismiss() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isVisible = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            onDismiss()
        }
    }

    func show() {
        withAnimation(.spring(duration: 0.3)) {
            isVisible = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            if isVisible { dismiss() }
        }
    }
}

/// View modifier that shows a toast when `message` is non-nil.
struct ToastModifier: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let msg = message {
                ToastView(message: msg) {
                    message = nil
                }
                .onAppear {
                    withAnimation(.spring(duration: 0.3)) {}
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            message = nil
                        }
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
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
