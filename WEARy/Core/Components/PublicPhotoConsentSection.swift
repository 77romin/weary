import SwiftUI

struct PublicPhotoPublicationConsent: Equatable {
    var acknowledgesPublicUpload = false
    var confirmsPublicationRights = false

    var isComplete: Bool {
        acknowledgesPublicUpload && confirmsPublicationRights
    }

    mutating func reset() {
        acknowledgesPublicUpload = false
        confirmsPublicationRights = false
    }
}

enum PublicPhotoConsentPolicy {
    static func permitsSaving(
        publishesToFeed: Bool,
        consent: PublicPhotoPublicationConsent
    ) -> Bool {
        !publishesToFeed || consent.isComplete
    }
}

struct PublicPhotoConsentSection: View {
    @Binding var consent: PublicPhotoPublicationConsent

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("공개 전 확인", systemImage: "person.crop.rectangle.badge.checkmark")
                .font(.subheadline.weight(.bold))

            Toggle("착장 사진이 서버에 업로드되어 다른 사용자에게 공개되는 것을 이해했어요.", isOn: $consent.acknowledgesPublicUpload)
                .accessibilityIdentifier("photoConsent.publicUpload")

            Toggle("사진을 게시할 권리가 있으며, 다른 사람이 보인다면 게시 동의를 받았어요.", isOn: $consent.confirmsPublicationRights)
                .accessibilityIdentifier("photoConsent.publicationRights")

            Text("위 확인은 게시할 때마다 필요하며 개인 착장 기록에는 적용되지 않아요.")
                .font(.caption)
                .foregroundStyle(WEARyTheme.secondaryInk)
        }
        .font(.subheadline)
    }
}
