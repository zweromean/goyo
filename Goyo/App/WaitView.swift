import SwiftUI
import Combine

struct WaitView: View {
    let title: String
    let seconds: Int
    let onComplete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @EnvironmentObject private var app: AppModel
    @State private var remaining: Int
    @State private var lastTick: Date?
    private let clock = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    @State private var elapsed: TimeInterval = 0

    init(title: String, seconds: Int, onComplete: @escaping () -> Void) {
        self.title = title
        self.seconds = max(0, seconds)
        self.onComplete = onComplete
        _remaining = State(initialValue: max(0, seconds))
    }
    var body: some View {
        VStack(spacing: 28) {
            HStack { Spacer(); Button("취소") { dismiss() } }.padding()
            Spacer()
            Image(systemName: "hourglass").font(.system(size: 44)).foregroundStyle(GoyoTheme.violet)
            Text(title).font(.title2.weight(.semibold))
            ZStack {
                Circle().stroke(.white.opacity(0.12), lineWidth: 10)
                Circle().trim(from: 0, to: seconds == 0 ? 1 : CGFloat(1 - Double(remaining) / Double(seconds)))
                    .stroke(GoyoTheme.violet, style: StrokeStyle(lineWidth: 10, lineCap: .round)).rotationEffect(.degrees(-90))
                Text(String(format: "%d:%02d", remaining / 60, remaining % 60)).font(.system(size: 64, weight: .light, design: .rounded)).monospacedDigit()
            }.frame(width: 220, height: 220)
            Text(remaining == 0 ? "준비되셨으면 열어주세요." : "잠깐 쉬어가세요.").font(.title3)
            Spacer()
            Button("계속하기") { onComplete() }
                .buttonStyle(.borderedProminent).controlSize(.large).tint(GoyoTheme.violet)
                .disabled(remaining > 0).padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity).foregroundStyle(.white)
        .background(GoyoTheme.charcoal)
        .saturation(app.settings.grayscale ? 0 : 1)
        .onReceive(clock) { now in
            guard phase == .active, remaining > 0 else { lastTick = nil; return }
            if let previous = lastTick { elapsed += min(0.25, max(0, now.timeIntervalSince(previous))) }
            lastTick = now
            remaining = max(0, seconds - Int(elapsed))
        }
        .onChange(of: phase) { _, _ in lastTick = nil }
    }
}
