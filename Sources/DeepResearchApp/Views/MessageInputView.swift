import SwiftUI

struct MessageInputView: View {
    @Binding var text: String
    let isDisabled: Bool
    let onSend: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.dsBorder)
                .frame(height: 1)

            HStack(alignment: .center, spacing: 14) {
                textInputField

                sendButton
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color.dsCardBackground)
        }
    }

    // MARK: - Text Input

    private var textInputField: some View {
        // Outer container handles all visual styling (background, border, shape).
        // The TextEditor sits inside untouched — no clipShape or padding on it
        // directly — so the underlying NSTextView keeps its full responder area.
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .focused($isFocused)
                .font(.dsBody)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 44, maxHeight: 140)
                .onKeyPress(.return, phases: .down) { press in
                    if press.modifiers.contains(.shift) {
                        return .ignored
                    }
                    guard canSend else {
                        // Let TextEditor handle Return (newline) when submit is unavailable.
                        return .ignored
                    }
                    onSend()
                    return .handled
                }

            // Placeholder (only when empty and not focused)
            if text.isEmpty && !isFocused {
                Text("Ask a research question...")
                    .font(.dsBody)
                    .foregroundStyle(.dsLightSlate)
                    .padding(.leading, 5)  // matches NSTextView internal inset
                    .padding(.top, 8)      // matches NSTextView internal inset
                    .allowsHitTesting(false)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.dsSurface, in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(isFocused ? Color.dsIndigo.opacity(0.5) : Color.dsBorder, lineWidth: 1.5)
        }
        .onAppear {
            isFocused = true
        }
    }

    // MARK: - Send Button

    private var sendButton: some View {
        Button(action: sendIfAllowed) {
            Image(systemName: "paperplane.fill")
                .font(.dsBodyBold)
                .foregroundStyle(canSend ? .dsNavy : .white)
                .frame(width: 48, height: 48)
                .background(canSend ? Color.dsIndigo : Color.dsLightSlate.opacity(0.4))
                .clipShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
        .animation(DSAnimation.quick, value: canSend)
    }

    private var canSend: Bool {
        !isDisabled && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendIfAllowed() {
        guard canSend else { return }
        onSend()
    }
}
