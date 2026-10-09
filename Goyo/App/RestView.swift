import SwiftUI

struct RestView: View {
    @EnvironmentObject private var breaks: BreakModel
    @EnvironmentObject private var app: AppModel
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, Int(ceil((breaks.until ?? context.date).timeIntervalSince(context.date))))
            VStack(spacing: 28) {
                Image(systemName: "cup.and.saucer").font(.system(size: 48)).foregroundStyle(GoyoTheme.violet)
                Text("잠시 쉬어가세요").font(.largeTitle.bold())
                Text(String(format: "%02d:%02d", remaining / 60, remaining % 60))
                    .font(.system(size: 64, weight: .light, design: .rounded)).monospacedDigit()
                Text("화면에서 눈을 떼고 잠깐 쉬세요.").foregroundStyle(.white.opacity(0.8))
                Button("계속하기") { breaks.finishRest() }
                    .buttonStyle(.borderedProminent).tint(GoyoTheme.violet).controlSize(.large).disabled(remaining > 0)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(GoyoTheme.charcoal).foregroundStyle(.white)
        }.interactiveDismissDisabled().saturation(app.settings.grayscale ? 0 : 1)
    }
}
