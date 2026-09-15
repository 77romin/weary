# WEARy 프로토타입 최신 빌드·서버 검증 보고서

## 빌드 결과

| 항목 | 결과 |
| --- | --- |
| 빌드 일시 | 2026-09-14 |
| 기준 | 2026-09-14 인증 복구·소셜 데이터 모드 작업 트리 |
| 최신 테스트 갱신 | 2026-09-15 안내·인증·캐시 경계·저장 실패 회귀 검증 |
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

- 2026-09-15 최신 로컬 단위 테스트 32개 전체 통과
- 2026-09-15 실제 iPhone에서 Vision 비교 테스트 통과: Mock fallback 없이 `.vision` 경로 확인
- 2026-09-15 최신 Debug 앱 빌드·설치·실행 성공, 기존 앱을 삭제하지 않고 갱신
- 2026-09-15 최신 시뮬레이터 UI 테스트 13개 전체 통과
- 실제 Supabase 왕복 통합 테스트 15개는 이전 실서버 실행에서 통과했으며 이번 로컬 회귀 실행에서는 재검증하지 않음
- 독립 사용자 A/B 세션에서 게시물 노출, 팔로우·댓글, 매물 노출과 양방향 채팅 확인
- 로컬·원격 마이그레이션 21개 일치 및 계정 제재·거래 채팅 차단 트리거·Storage RLS 검증
- Supabase DB 린트 오류 0건
- Xcode 정적 분석 통과
- 실제 iPhone Release 빌드·설치·실행 성공
- 이전 실제 iPhone 전체 사용자 흐름 확인 완료
- Release 앱 설치 후 시작 직후 비정상 종료 없음, 코드서명 문제 없음
- 옷 등록, 착장 기록, MY 캘린더, 피드, 마켓의 핵심 시연 흐름 확인 완료
- 기존 통합 `default.store`를 개인 저장소와 서비스 캐시로 분리한 뒤 개인 데이터 승계 및 UI 회귀 테스트 완료

이메일 가입 확인 Site URL과 Redirect URL은 `weary://auth-callback`으로 원격 Supabase에 등록했다. 이메일 또는 아이디 로그인, 이메일·아이디·닉네임 중복 확인과 닉네임 유일성도 서버에 연결했다. 아이디 찾기는 가입 이메일로 매직 링크를 보내 본인 확인 후 앱에서 아이디를 안내하며, 비밀번호 재설정·이메일 인증도 같은 앱 콜백에서 목적별로 처리한다. 메일 수신함에서 링크를 누르는 과정은 외부 메일 클라이언트 조작이 필요해 자동화 범위에서 제외한다.

### 2026-09-15 품질 점검 추가 결과

- 최신 전체 결과 번들: `/tmp/weary-quality-derived/Logs/Test/Test-WEARy-2026.09.15_14-51-48-+0900.xcresult`
- Xcode 표시 60개 통과·실패 0개: 로컬 단위 32개 + UI 13개 + 서버 작업 없이 반환한 선택형 통합 15개. 실서버 통합 재실행과는 구분한다.
- 로그인·가입 요청 중 입력 화면 유지, 늦은 인증 응답의 로그아웃 복원 방지, 계정 변경 시 원격 캐시만 삭제하는 경계와 실패 시 진입 차단을 추가했다.
- 단일 Vision 후보의 수동 선택, 옷 저장 실패 복원·새 삽입 취소, 착장 중복 저장 방지를 수정했다. 업로드 실패 시 개인 착장 보존과 임시 원격 데이터 정리 경로는 코드 점검했다.
- 데모 프로필 UI 검증에서 인증되지 않은 서버 요청이 오류 팝업을 띄우던 의존성을 제거하고 전체 테스트를 재실행했다.
- 최종 Debug 빌드·아이폰 갱신 설치 성공. 잠긴 아이폰 때문에 최종 자동 실행은 차단됐으며, 위의 이전 실행 성공과 구분한다.
- 실제 메일 클릭·OAuth·강제 세션 만료·통신 단절의 모든 실기기 시나리오를 자동 검증한 것은 아니다.

재현 명령:

```bash
xcodebuild -quiet -project WEARy.xcodeproj -scheme WEARy \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_ID>' \
  -derivedDataPath /tmp/weary-quality-derived test
```

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

- 착장 의류 추천은 Apple Vision의 이미지 특징값으로 카테고리별 신체 영역과 옷장 사진을 기기 안에서 비교하며, 분석을 사용할 수 없으면 `DemoOutfitAnalyzer`로 fallback한다. 실제 의류 영역 탐지·세분화 모델은 아직 포함하지 않았다.
- 새 착장부터 Vision 후보 채택률, 첫 후보 유지율, 수정 필요율과 fallback 횟수를 개인 저장소에만 기록하고 MY에서 확인할 수 있다.
- 개인 옷장·착장은 SwiftData `default.store`, 피드·마켓 캐시는 재생성 가능한 `service-cache.store`로 분리했다. 일반 Debug는 로컬 전용이며, 실제 CloudKit 동기화는 유료 개발자 팀의 컨테이너 등록 후 `CloudKitDebug`에서 검증해야 한다.
- 이메일 계정, 프로필, 피드 게시·소셜 상호작용·Realtime·페이지네이션은 Supabase에 연결되어 있다.
- 마켓 매물·이미지·관심·상태 변경·상품별 1:1 채팅은 Supabase에 연결되어 있다.
- 신고·차단·운영자 검토·콘텐츠 숨김 제재·앱 내 처리 알림·계정 탈퇴는 Supabase에 연결되어 있다.
- MY에서 실서버/데모 소셜 데이터 모드를 선택하며 피드·마켓·팔로우 목록에 두 출처가 섞이지 않는다.
- 활성 이용 제한·정지 계정은 커뮤니티·마켓 쓰기와 공유 이미지 업로드가 서버에서 차단되며, 이의 제기·신고·삭제·탈퇴는 유지된다.
- 실서버가 비어 있으면 첫 게시·판매를 안내하고, 데모 모드는 발표용 샘플과 로컬 동작을 유지한다.
- 백업용 화면 녹화는 발표 방식 결정에 따라 생략했다.

## 다음 단계

1. 이메일 인증을 완료한 최초 운영 계정에 안전하게 `admin` 역할 부여
2. 친구 기기 2대에서 이메일 계정으로 최종 사용성 스모크 테스트
3. 운영 계정으로 제재 생성·이의 제기 심사 성공 경로 최종 확인
4. CloudKit private database와 SwiftData 동기화 검증
5. Google·Kakao·Apple 운영 키 발급과 OAuth Provider 활성화
6. Vision PoC를 실제 착장 데이터셋으로 측정하고 의류 영역 탐지·세분화 모델 검증
