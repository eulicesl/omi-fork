import Cocoa
import SwiftUI

/// Reusable chat input field with send button, extracted from ChatPage.
/// Used by both ChatPage (main chat) and TaskChatPanel (task sidebar chat).
///
/// When `isSending` is true:
///   - Input stays enabled so the user can type a follow-up
///   - If input is empty, the button becomes a stop button
///   - If input has text, pressing send calls `onFollowUp` (redirects the agent)
struct ChatInputView: View {
    let onSend: (String, Data?) -> Void
    var onFollowUp: ((String) -> Void)? = nil
    var onStop: (() -> Void)? = nil
    let isSending: Bool
    var isStopping: Bool = false
    var placeholder: String = "Type a message..."
    @Binding var mode: ChatMode
    /// Optional text to pre-fill the input (e.g. task context). Consumed on change.
    var pendingText: Binding<String>?

    @AppStorage("askModeEnabled") private var askModeEnabled = false
    @Environment(\.fontScale) private var fontScale
    @Binding var inputText: String

    /// Single-image attachment captured from a drag-drop. Stored as raw bytes
    /// for the chip preview and the send payload. Phase 1 MVP — multi-attachment
    /// and non-image types are follow-on phases.
    @State private var pendingAttachment: Data?
    @State private var isDropTargeted = false

    private var hasText: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Send is enabled when either text is present or an image is attached.
    private var hasSendableContent: Bool {
        hasText || pendingAttachment != nil
    }

    /// Padding used for both the NSTextView (via textContainerInset) and the
    /// placeholder overlay — guaranteeing the cursor and placeholder align.
    private let inputPaddingH: CGFloat = 12
    private let inputPaddingV: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let attachment = pendingAttachment {
                attachmentChip(for: attachment)
            }
            inputRow
        }
        .padding(12)
        .omiPanel(fill: OmiColors.backgroundSecondary, radius: 22, stroke: OmiColors.border.opacity(0.2), shadowOpacity: 0.1, shadowRadius: 12, shadowY: 6)
        .overlay {
            // Drop zone visual feedback — highlights the panel border while a
            // drag is hovering over the composer.
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(OmiColors.purplePrimary, lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL, .image], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
        }
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            // When ask mode is disabled, ensure we're always in act mode
            if !askModeEnabled {
                mode = .act
            }
            if let pending = pendingText?.wrappedValue, !pending.isEmpty {
                inputText = pending
                pendingText?.wrappedValue = ""
            }
        }
        .onChange(of: pendingText?.wrappedValue ?? "") { _, newValue in
            if !newValue.isEmpty {
                inputText = newValue
                pendingText?.wrappedValue = ""
            }
        }
        .onChange(of: askModeEnabled) { _, enabled in
            if !enabled {
                mode = .act
            }
        }
    }

    private var inputRow: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // Input field with floating toggle
            ZStack(alignment: .topTrailing) {
                // Hidden Text drives the SwiftUI height; OmiTextEditor overlays it exactly.
                // This lets SwiftUI measure height from text content without fighting AppKit's
                // scroll view layout — the onHeightChange pattern caused layout loops inside
                // the TaskChatPanel VStack with frame(maxHeight: .infinity).
                Text(inputText.isEmpty ? " " : inputText + " ")
                    .scaledFont(size: 14)
                    .padding(.horizontal, inputPaddingH)
                    .padding(.vertical, inputPaddingV)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .overlay(alignment: .topLeading) {
                        // Placeholder text — padding matches textContainerInset exactly
                        if inputText.isEmpty {
                            Text(placeholder)
                                .scaledFont(size: 14)
                                .foregroundColor(OmiColors.textTertiary)
                                .padding(.horizontal, inputPaddingH)
                                .padding(.vertical, inputPaddingV)
                                .allowsHitTesting(false)
                        }
                    }
                    .overlay {
                        OmiTextEditor(
                            text: $inputText,
                            fontSize: round(14 * fontScale),
                            textColor: NSColor(OmiColors.textPrimary),
                            textContainerInset: NSSize(width: inputPaddingH, height: inputPaddingV),
                            onSubmit: handleSubmit
                        )
                    }
                    .frame(maxHeight: 200)
                    .clipped()
                    .background(OmiColors.backgroundTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                // Floating Ask/Act toggle (top-right, inside the input area)
                if askModeEnabled {
                    ChatModeToggle(mode: $mode)
                        .padding(.top, 8)
                        .padding(.trailing, 8)
                }
            }

            // Send/Stop button — inline to the right of the input
            if isSending && !hasText {
                if isStopping {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 24, height: 24)
                } else {
                    Button(action: { onStop?() }) {
                        Image(systemName: "stop.circle.fill")
                            .scaledFont(size: 24)
                            .foregroundColor(.red.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Button(action: handleSubmit) {
                    Image(systemName: "arrow.up.circle.fill")
                        .scaledFont(size: 24)
                        .foregroundColor(hasSendableContent ? OmiColors.purplePrimary : OmiColors.textQuaternary)
                }
                .buttonStyle(.plain)
                .disabled(!hasSendableContent)
            }
        }
    }

    /// Inline preview chip for the pending image attachment. Tap × to remove
    /// before sending. Single-image only in Phase 1.
    private func attachmentChip(for data: Data) -> some View {
        let thumb = NSImage(data: data)
        return ZStack(alignment: .topTrailing) {
            Group {
                if let thumb = thumb {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(OmiColors.backgroundTertiary)
                        .frame(width: 60, height: 60)
                        .overlay(
                            Image(systemName: "doc")
                                .scaledFont(size: 18)
                                .foregroundColor(OmiColors.textTertiary)
                        )
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(OmiColors.border.opacity(0.3), lineWidth: 1)
            )

            Button(action: { pendingAttachment = nil }) {
                Image(systemName: "xmark.circle.fill")
                    .scaledFont(size: 16)
                    .foregroundColor(.white)
                    .background(
                        Circle()
                            .fill(Color.black.opacity(0.65))
                            .frame(width: 14, height: 14)
                    )
            }
            .buttonStyle(.plain)
            .offset(x: 6, y: -6)
        }
        .padding(.leading, 4)
        .padding(.top, 4)
    }

    /// Accept image-typed file URLs from a drag-drop. Two paths in order of
    /// likelihood for a sandboxed macOS app:
    ///   1. `loadFileRepresentation` — AppKit stages a security-scoped temp
    ///      file we can read without bookmarks. Right path for Finder drops.
    ///   2. `loadDataRepresentation` — for in-memory images from web pages,
    ///      screenshot tools, etc. that ship raw bytes directly.
    /// Bare `loadObject(ofClass: URL.self)` was tried first and fails silently
    /// in sandboxed builds because `Data(contentsOf:)` on the returned URL
    /// needs security scope the URL provider does not auto-grant.
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        if provider.hasItemConformingToTypeIdentifier("public.image") {
            provider.loadFileRepresentation(forTypeIdentifier: "public.image") { url, error in
                if let error = error {
                    logError("ChatInput: loadFileRepresentation failed", error: error)
                    return
                }
                guard let url = url, let data = try? Data(contentsOf: url) else { return }
                DispatchQueue.main.async {
                    self.pendingAttachment = data
                }
            }
            return true
        }

        if provider.hasItemConformingToTypeIdentifier("public.png")
            || provider.hasItemConformingToTypeIdentifier("public.jpeg")
            || provider.hasItemConformingToTypeIdentifier("public.tiff") {
            let typeId = provider.registeredTypeIdentifiers.first(where: {
                ["public.png", "public.jpeg", "public.tiff", "public.image"].contains($0)
            }) ?? "public.image"
            provider.loadDataRepresentation(forTypeIdentifier: typeId) { data, error in
                if let error = error {
                    logError("ChatInput: loadDataRepresentation failed", error: error)
                    return
                }
                guard let data = data, NSImage(data: data) != nil else { return }
                DispatchQueue.main.async {
                    self.pendingAttachment = data
                }
            }
            return true
        }

        return false
    }

    private func handleSubmit() {
        guard hasSendableContent else { return }
        let text = inputText
        let attachment = pendingAttachment
        inputText = ""
        pendingAttachment = nil
        if isSending {
            // Follow-ups don't carry attachments today — Phase 1 keeps the
            // attachment path on the primary send only. (The agent receives the
            // image with the original send and remembers it across the turn.)
            onFollowUp?(text)
        } else {
            onSend(text, attachment)
        }
    }
}

// MARK: - Ask/Act Mode Toggle

struct ChatModeToggle: View {
    @Binding var mode: ChatMode

    var body: some View {
        HStack(spacing: 0) {
            modeButton(for: .ask, label: "Ask")
            modeButton(for: .act, label: "Act")
        }
        .background(OmiColors.backgroundQuaternary.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func modeButton(for targetMode: ChatMode, label: String) -> some View {
        Button(action: { mode = targetMode }) {
            Text(label)
                .scaledFont(size: 12, weight: .medium)
                .foregroundColor(mode == targetMode ? .white : OmiColors.textTertiary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(mode == targetMode ? OmiColors.userBubble : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
