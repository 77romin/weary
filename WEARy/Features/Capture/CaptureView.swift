import SwiftUI

struct CaptureView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                WEARyTheme.ink.ignoresSafeArea()
                VStack(spacing: 26) {
                    Spacer()
                    ZStack {
                        RoundedRectangle(cornerRadius: 36)
                            .stroke(WEARyTheme.lime, style: StrokeStyle(lineWidth: 2, dash: [10]))
                            .frame(width: 220, height: 360)
                        Image(systemName: "figure.stand")
                            .font(.system(size: 140, weight: .ultraLight))
                            .foregroundStyle(WEARyTheme.surface.opacity(0.82))
                    }
                    VStack(spacing: 8) {
                        Text("오늘의 룩을 남겨보세요")
                            .font(.system(.title2, design: .rounded, weight: .bold))
                        Text("전신이 프레임 안에 들어오면\n내 옷장에서 입은 옷을 찾아드려요.")
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    Button {
                    } label: {
                        Label("착장 기록 시작", systemImage: "camera.fill")
                            .font(.headline)
                            .foregroundStyle(WEARyTheme.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(WEARyTheme.lime, in: Capsule())
                    }
                    .padding(.horizontal, 28)
                    Spacer()
                }
                .foregroundStyle(.white)
            }
            .navigationTitle("착장 기록")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}
