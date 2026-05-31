import SwiftUI

@MainActor
final class CursorPTTOverlayState: ObservableObject {

    enum Phase: Equatable {
        case hidden      // app not ready yet (pre-setup)
        case idle        // always-on tiny dot
        case listening   // pulsing dot + live transcript
        case processing  // spinning ring + animated dots (between release and first token)
        case responding  // response bubble streaming
        case notifying   // proactive notification (amber styling)
        case executing   // executing a plan (step-by-step progress card)
    }

    @Published var phase: Phase = .hidden
    @Published var streamingText: String = ""
    @Published var transcriptText: String = ""
    @Published var displayedQuery: String = ""
    @Published var cursorPosition: CGPoint = .zero

    /// Set while a `.notifying` bubble represents an actionable task — drives
    /// the **Execute** affordance. Nil for passive (Focus/Insight) alerts and
    /// once Execute has been tapped (so the button doesn't re-fire).
    @Published var executableNotification: FloatingBarNotification?
}
