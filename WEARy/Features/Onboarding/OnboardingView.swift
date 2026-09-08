import SwiftUI

struct OnboardingView: View {
    let onComplete: () -> Void
    @State private var page = OnboardingPage.wardrobe

    var body: some View {
        ZStack {
            WEARyTheme.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Text("!WEARy")
                        .font(.system(.title3, design: .rounded, weight: .black))
                    Spacer()
                    Button("건너뛰기", action: onComplete)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WEARyTheme.secondaryInk)
                        .accessibilityIdentifier("onboarding.skip")
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)

                TabView(selection: $page) {
                    ForEach(OnboardingPage.allCases) { item in
                        OnboardingPageView(page: item)
                            .tag(item)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                VStack(spacing: 18) {
                    HStack(spacing: 7) {
                        ForEach(OnboardingPage.allCases) { item in
                            Capsule()
                                .fill(item == page ? WEARyTheme.ink : WEARyTheme.ink.opacity(0.16))
                                .frame(width: item == page ? 26 : 7, height: 7)
                                .animation(.snappy, value: page)
                        }
                    }
                    .accessibilityHidden(true)

                    Button {
                        advance()
                    } label: {
                        HStack {
                            Text(page == .discovery ? "내 옷장 시작하기" : "다음")
                            Spacer()
                            Image(systemName: page == .discovery ? "hanger" : "arrow.right")
                        }
                        .font(.headline)
                        .foregroundStyle(WEARyTheme.surface)
                        .lightTextOutline()
                        .padding(.horizontal, 22)
                        .frame(height: 58)
                        .background(WEARyTheme.ink, in: Capsule())
                    }
                    .accessibilityIdentifier(page == .discovery ? "onboarding.start" : "onboarding.next")
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 18)
            }
        }
    }

    private func advance() {
        guard let next = page.next else {
            onComplete()
            return
        }
        withAnimation(.snappy) { page = next }
    }
}

private enum OnboardingPage: Int, CaseIterable, Identifiable {
    case wardrobe
    case record
    case discovery

    var id: Int { rawValue }

    var eyebrow: String {
        switch self {
        case .wardrobe: "MY CLOSET"
        case .record: "TODAY'S WEAR"
        case .discovery: "DISCOVER & REWEAR"
        }
    }

    var title: String {
        switch self {
        case .wardrobe: "옷을 산 순간부터\n기록해요"
        case .record: "오늘 입은 옷을\n사진 한 장으로"
        case .discovery: "내 취향을 발견하고\n다음 옷장으로"
        }
    }

    var description: String {
        switch self {
        case .wardrobe:
            "사진, 가격과 사이즈를 등록하면\n나만의 옷장이 차곡차곡 만들어져요."
        case .record:
            "AI가 내 옷장에서 후보를 찾고\n내가 확인한 옷만 착용 기록에 남겨요."
        case .discovery:
            "달력과 통계로 자주 입는 옷을 찾고\n안 입는 옷은 판매 글로 이어보세요."
        }
    }

    var accent: Color {
        switch self {
        case .wardrobe: WEARyTheme.coral
        case .record: WEARyTheme.lime
        case .discovery: Color(hex: "A7B9CE")
        }
    }

    var next: OnboardingPage? {
        OnboardingPage(rawValue: rawValue + 1)
    }
}

private struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                OnboardingArtwork(page: page)
                    .frame(height: 330)
                    .padding(.top, 16)

                VStack(alignment: .leading, spacing: 12) {
                    Text(page.eyebrow)
                        .font(.caption.weight(.black))
                        .tracking(2)
                        .foregroundStyle(page == .record ? WEARyTheme.ink : WEARyTheme.coral)
                    Text(page.title)
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .minimumScaleFactor(0.78)
                    Text(page.description)
                        .font(.body)
                        .foregroundStyle(WEARyTheme.secondaryInk)
                        .lineSpacing(4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
        .accessibilityElement(children: .contain)
    }
}

private struct OnboardingArtwork: View {
    let page: OnboardingPage

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 38)
                .fill(page.accent.opacity(page == .record ? 0.78 : 0.48))
                .padding(.horizontal, 24)

            switch page {
            case .wardrobe:
                wardrobeArtwork
            case .record:
                recordArtwork
            case .discovery:
                discoveryArtwork
            }
        }
        .accessibilityHidden(true)
    }

    private var wardrobeArtwork: some View {
        ZStack {
            asset("DemoCurvedDenim", width: 145, height: 220)
                .rotationEffect(.degrees(8)).offset(x: 62, y: 32)
            asset("DemoLeatherJacket", width: 190, height: 180)
                .rotationEffect(.degrees(-7)).offset(x: -48, y: -36)
            asset("DemoWhiteTee", width: 125, height: 125)
                .offset(x: 75, y: -78)
        }
    }

    private var recordArtwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28)
                .stroke(WEARyTheme.ink, lineWidth: 3)
                .frame(width: 206, height: 278)
            VStack(spacing: -2) {
                asset("DemoWhiteTee", width: 100, height: 82)
                asset("DemoCurvedDenim", width: 100, height: 128)
                asset("DemoSilverSneakers", width: 94, height: 60)
            }
            Image(systemName: "viewfinder")
                .font(.system(size: 244, weight: .ultraLight))
                .foregroundStyle(WEARyTheme.ink.opacity(0.24))
        }
    }

    private var discoveryArtwork: some View {
        HStack(spacing: 10) {
            VStack(spacing: 9) {
                Text("12회")
                    .font(.system(.title, design: .rounded, weight: .black))
                Text("이번 달 최애")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WEARyTheme.secondaryInk)
                asset("DemoWhiteTee", width: 104, height: 112)
            }
            .frame(width: 145, height: 220)
            .background(WEARyTheme.surface, in: RoundedRectangle(cornerRadius: 24))

            Image(systemName: "arrow.right")
                .font(.headline.bold())

            VStack(spacing: 9) {
                Image(systemName: "tag.fill")
                    .font(.title2)
                    .foregroundStyle(WEARyTheme.coral)
                asset("DemoRedBag", width: 116, height: 120)
                Text("다음 옷장으로")
                    .font(.caption.weight(.bold))
            }
            .frame(width: 145, height: 220)
            .background(WEARyTheme.surface, in: RoundedRectangle(cornerRadius: 24))
        }
    }

    private func asset(_ name: String, width: CGFloat, height: CGFloat) -> some View {
        Image(name)
            .resizable()
            .scaledToFit()
            .frame(width: width, height: height)
    }
}
