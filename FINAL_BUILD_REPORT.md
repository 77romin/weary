# WEARy 프로토타입 최신 빌드·서버 검증 보고서

## 빌드 결과

| 항목 | 결과 |
| --- | --- |
| 빌드 일시 | 2026-09-14 |
| 기준 커밋 | `7433aa8` (`fix: repair email confirmation and login button hit area`) |
| 구성 | Release |
| 플랫폼 | iOS 18.0 이상 |
| 앱 버전 | 0.1.0 (1) |
| 번들 ID | `com.weary.prototype` |
| Swift | 6.0 |
| 산출물 크기 | 약 20MB |
| 코드서명 | 유효 |
| 실기기 설치·실행 | 성공 |

산출물은 로컬의 `/tmp/weary-final-release-20260914/Build/Products/Release-iphoneos/WEARy.app`에 생성했다. `/tmp`는 임시 영역이므로 장기 보관용으로 사용하지 않고, 필요할 때 아래 명령으로 다시 빌드한다.

## 검증 결과

- iOS 단위 테스트 전체 통과
- 시뮬레이터 UI 테스트 3개 전체 통과
- 실제 Supabase 왕복 통합 테스트 13개 전체 통과
- 로컬·원격 Supabase 마이그레이션 17개 일치
- Supabase DB 린트 오류 0건
- Xcode 정적 분석 통과
- 실제 iPhone Release 빌드·설치·실행 성공
- 이전 실제 iPhone 전체 사용자 흐름 확인 완료
- Release 앱 설치 후 시작 직후 비정상 종료 없음, 코드서명 문제 없음
- 옷 등록, 착장 기록, MY 캘린더, 피드, 마켓의 핵심 시연 흐름 확인 완료

이메일 가입 확인 Site URL과 Redirect URL은 `weary://auth-callback`으로 원격 Supabase에 등록했다. 이메일 또는 아이디 로그인, 이메일·아이디·닉네임 중복 확인과 닉네임 유일성도 서버에 연결했다. 메일 재전송과 앱 콜백 코드는 검증했지만, 실제 수신함에서 링크를 누르는 과정은 외부 메일 클라이언트 조작이 필요해 자동화 범위에서 제외한다.

## Release 재빌드

```bash
xcodebuild -quiet \
  -project WEARy.xcodeproj \
  -scheme WEARy \
  -configuration Release \
  -destination 'platform=iOS,id=<DEVICE_ID>' \
  -derivedDataPath /tmp/weary-final-release-20260914 \
  -allowProvisioningUpdates \
  build
```

## 현재 프로토타입의 범위

이 빌드는 로컬 우선 개인 옷장과 Supabase 공용 서비스를 결합한 네트워크 연결 프로토타입이다.

- 착장 의류 추천은 실제 이미지 AI가 아닌 `DemoOutfitAnalyzer` Mock이다.
- 개인 옷장은 현재 SwiftData에 로컬 저장되며 CloudKit 동기화는 아직 연결하지 않았다.
- 이메일 계정, 프로필, 피드 게시·소셜 상호작용·Realtime·페이지네이션은 Supabase에 연결되어 있다.
- 마켓 매물·이미지·관심·상태 변경·상품별 1:1 채팅은 Supabase에 연결되어 있다.
- 신고·차단·운영자 검토·콘텐츠 숨김 제재·앱 내 처리 알림·계정 탈퇴는 Supabase에 연결되어 있다.
- 오프라인 시연과 신규 데이터가 없는 상태를 위해 샘플 데이터와 로컬 fallback을 유지한다.
- 백업용 화면 녹화는 발표 방식 결정에 따라 생략했다.

## 다음 단계

1. 이메일 인증을 완료한 최초 운영 계정에 안전하게 `admin` 역할 부여
2. 서로 다른 실제 계정 2개를 이용한 다중 사용자 수동 시나리오 확인
3. 계정 제재·이의 제기·복구 절차 구현
4. CloudKit private database와 SwiftData 동기화 검증
5. Google·Kakao·Apple 운영 키 발급과 OAuth Provider 활성화
6. 실제 AI 의류 탐지·이미지 유사도 분석 PoC
