# Security Policy

## Supported version

이 저장소는 현재 프로토타입의 최신 `main` 브랜치만 보안 수정 대상으로 관리합니다.

## Reporting a vulnerability

취약점이나 민감정보 노출 가능성을 발견했다면 공개 Issue, Discussion 또는 Pull Request에 재현 정보나 비밀값을 올리지 마세요. GitHub 프로필의 비공개 연락 수단으로 저장소 관리자에게 먼저 알려 주세요.

신고에는 가능한 범위에서 영향받는 기능, 재현 조건, 예상 영향과 완화 방법을 포함해 주세요. 실제 사용자 데이터 접근, 계정 탈취, 서비스 방해 또는 비용을 유발하는 검증은 수행하지 마세요.

## Secrets and local configuration

- iOS 앱에는 Supabase publishable key만 사용합니다.
- Supabase secret/service-role key와 OAuth provider secret은 앱 번들 및 Git 이력에 포함하지 않습니다.
- 로컬 연결값은 Git에서 제외된 `Config/Supabase.local.xcconfig`에 보관합니다.
- 의심되는 비밀값은 저장소에서 지우는 것만으로 끝내지 않고 제공자에서 즉시 폐기·교체합니다.
