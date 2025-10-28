import SwiftUI
import WatchKit

struct WatchRecorderView: View {
    @ObservedObject var viewModel: WatchAudioRecorderViewModel
    @State private var isPressed = false
    @State private var pulseScale: CGFloat = 1.0
    @State private var rippleScale: CGFloat = 1.0
    @State private var rippleOpacity: Double = 0.0
    @State private var recordingDuration: TimeInterval = 0
    @State private var durationTimer: Timer?
    @Environment(\.isLuminanceReduced) var isLuminanceReduced
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Black background
                Color.black
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    Spacer()
                    
                    Button(action: {
                        // Haptic feedback
                        WKInterfaceDevice.current().play(.click)

                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            isPressed = true
                        }

                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                isPressed = false
                            }
                        }

                        if viewModel.isRecording {
                            // Success haptic for stopping
                            WKInterfaceDevice.current().play(.success)
                            viewModel.stopRecording()
                        } else {
                            // Start haptic for starting
                            WKInterfaceDevice.current().play(.start)
                            viewModel.startRecording()
                        }
                    }) {
                        ZStack {
                            // Pulsating ripple effect when recording
                            if viewModel.isRecording {
                                ForEach(0..<3, id: \.self) { index in
                                    Circle()
                                        .stroke(Color.white.opacity(0.3), lineWidth: 2)
                                        .frame(width: 100, height: 100)
                                        .scaleEffect(rippleScale)
                                        .opacity(rippleOpacity)
                                        .animation(
                                            Animation.easeOut(duration: 1.5)
                                                .repeatForever(autoreverses: false)
                                                .delay(Double(index) * 0.3),
                                            value: rippleScale
                                        )
                                        .onAppear {
                                            rippleScale = 2.5
                                            rippleOpacity = 0.8
                                        }
                                }
                            }
                            
                            // Main button circle (white background)
                            Circle()
                                .fill(Color.white)
                                .frame(width: 80, height: 80)
                                .scaleEffect(isPressed ? 0.95 : 1.0)
                                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
                                // Pulse effect when recording
                                .scaleEffect(viewModel.isRecording ? 1.05 : 1.0)
                                .animation(
                                    viewModel.isRecording
                                        ? .easeInOut(duration: 1.0).repeatForever(autoreverses: true)
                                        : .default,
                                    value: viewModel.isRecording
                                )
                            
                            // Logo with enhanced animation
                            Image("OmiLogo")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 40, height: 40)
                                .scaleEffect(isPressed ? 0.95 : 1.0)
                                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
                                // Dimmed for Always-On Display
                                .opacity(isLuminanceReduced ? 0.5 : 1.0)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityLabel(viewModel.isRecording ? "Stop Recording" : "Start Recording")
                    .accessibilityHint(viewModel.isRecording ? "Double tap to stop listening" : "Double tap to start listening")
                    .accessibilityAddTraits(viewModel.isRecording ? [.isButton, .startsMediaSession] : [.isButton])
                    
                    Spacer()

                    VStack(spacing: 8) {
                        Text(viewModel.isRecording ? "Listening" : "Tap to Record")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                            .opacity(isLuminanceReduced ? 0.7 : 1.0)

                        // Recording duration timer
                        if viewModel.isRecording {
                            Text(formatDuration(recordingDuration))
                                .font(.system(size: 14, weight: .regular, design: .monospaced))
                                .foregroundColor(.white.opacity(0.7))
                                .transition(.opacity)
                                .accessibilityLabel("Recording duration: \(formatDuration(recordingDuration))")
                        }

                        // Error state display
                        if let errorMessage = viewModel.errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 12, weight: .regular))
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                                .transition(.opacity)
                                .accessibilityLabel("Error: \(errorMessage)")
                                .accessibilityAddTraits(.isStaticText)
                        }
                    }
                    .padding(.bottom, 20)
                }
            }
        }
        .onAppear {
            if viewModel.isRecording {
                startRippleAnimation()
            }
        }
        .onChange(of: viewModel.isRecording) { isRecording in
            if isRecording {
                startRippleAnimation()
                startDurationTimer()
            } else {
                stopRippleAnimation()
                stopDurationTimer()
            }
        }
    }
    
    private func startRippleAnimation() {
        rippleScale = 1.0
        rippleOpacity = 0.8
        withAnimation(.easeOut(duration: 1.5).repeatForever(autoreverses: false)) {
            rippleScale = 2.5
            rippleOpacity = 0.0
        }
    }
    
    private func stopRippleAnimation() {
        rippleScale = 1.0
        rippleOpacity = 0.0
    }

    private func startDurationTimer() {
        recordingDuration = 0
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            recordingDuration += 1
        }
    }

    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
        recordingDuration = 0
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60
        let seconds = Int(duration) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}

#Preview {
    WatchRecorderView(viewModel: WatchAudioRecorderViewModel())
}
