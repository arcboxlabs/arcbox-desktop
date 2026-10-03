import SwiftUI

/// Lightweight toast banner that slides in from the top.
struct ToastView: View {
    let message: String
    var icon: String = "exclamationmark.triangle.fill"
    var onDismiss: () -> Void = {}

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColors.error)
                .accessibilityHidden(true)

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
            .accessibilityLabel("Dismiss")
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
    var dismissAfter: Duration? = .seconds(4)

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let msg = message {
                ToastView(message: msg) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        message = nil
                    }
                }
                .task(id: dismissAfter == nil ? nil : msg) {
                    guard let dismissAfter else { return }
                    try? await Task.sleep(for: dismissAfter)
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

    /// Keep operation failures separate from non-blocking list refresh failures.
    func listErrorToast(
        operationError: Binding<String?>,
        refreshError: Binding<String?>,
        resourceName: String
    ) -> some View {
        let message = Binding<String?> {
            operationError.wrappedValue
                ?? refreshError.wrappedValue.map {
                    "Couldn’t refresh \(resourceName). Showing cached results. \($0)"
                }
        } set: { newValue in
            guard newValue == nil else { return }
            if operationError.wrappedValue != nil {
                operationError.wrappedValue = nil
            } else {
                refreshError.wrappedValue = nil
            }
        }
        return modifier(
            ToastModifier(
                message: message,
                dismissAfter: operationError.wrappedValue == nil ? .seconds(4) : nil
            ))
    }
}
