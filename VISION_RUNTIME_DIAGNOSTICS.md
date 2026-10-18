# Vision 런타임 진단

## 목적

인식 결과가 비어 있을 때 추천 정책의 누락인지, Apple Vision 자체의 실행 오류인지 구분한다. 실제 사용자 사진 대신 메모리에서 만든 단색 이미지를 사용한다. 이 검사는 옷 인식 정확도나 실제 착장 처리 속도를 측정하지 않는다.

## 재현

```bash
xcodebuild -quiet -project WEARy.xcodeproj -scheme WEARy \
  -configuration Debug -destination 'platform=iOS Simulator,id=<SIMULATOR_ID>' \
  CODE_SIGNING_ALLOWED=NO \
  -resultBundlePath /tmp/weary-vision-probe.xcresult \
  -only-testing:WEARyTests/OutfitFlowTests test

xcrun xcresulttool get log --type action --path /tmp/weary-vision-probe.xcresult \
  | jq -r '.. | objects | .emittedOutput? // empty' \
  | rg '^VISION_RUNTIME' | sort -u
```

실기기에서는 연결 장치 ID와 유효한 개발 서명을 사용한다. 기본 선택과 CPU 명시 선택으로 이미지 분류·인체 포즈·이미지 특징 추출을 각각 실행하며 `VISION_RUNTIME` 행에 단계·모드·성공 여부·오류 domain/code만 기록한다. 사진, 옷 이름, 원문 오류 설명과 userInfo는 기록하지 않는다.

진단 테스트의 통과는 진단 코드가 실행됐다는 뜻이다. 모델 실행 성공을 의미하지 않으므로 반드시 여섯 단계별 결과를 확인한다. 단색 이미지에서 포즈 관측이 0개인 것은 정상 실행 결과일 수 있다.

## 2026-10-18 관찰

- 환경: Xcode 27.1, iOS 26.5 (23F77) 시뮬레이터.
- WEARy의 시뮬레이터 로그에서 `Missing weights path cnn_human_pose.espresso.weights status=-2`와 `Failed to create espresso context`를 확인했다.
- 이는 현재 실행 환경의 Vision 모델/컨텍스트 오류에 대한 근거다. 앱의 의류 분류 정확도가 낮다는 근거로 사용하지 않는다.
- 오류 로그만으로 런타임 설치 손상, Xcode/런타임 조합 문제 등 근본 원인을 확정하지 않는다. Apple 런타임 파일을 수동으로 복사하거나 수정하지 않는다.

iPhone 17 시뮬레이터에서 기본/CPU를 분리한 진단 결과:

| 요청 | 기본 실행 | CPU 명시 실행 |
| --- | --- | --- |
| 이미지 분류 | 실패: NSOSStatusErrorDomain -1 | 성공: 관측 1,303개 |
| 인체 포즈 | 실패: com.apple.Vision 9 | 실패: com.apple.Vision 9 |
| 이미지 특징 추출 | 실패: NSOSStatusErrorDomain -1 | 성공: 특징값 1개 |

관측 개수는 요청 실행 결과이지 인식 정확도가 아니다. 진단 결과 번들: `/tmp/weary-runtime-probe-suite-20261018.xcresult`. 핵심 테스트 69개 통과에 이 런타임 진단 1개가 포함되며, 그 자체가 여섯 요청 모두의 성공을 뜻하지 않는다.

## 적용 범위

`targetEnvironment(simulator)`일 때만 이미지 분류와 특징 추출의 main 계산 장치에 지원 목록의 CPU를 명시한다. 실기기는 자동 하드웨어 선택을 유지한다. 포즈 실패는 기존 화면 기준 영역으로 복구하며, 이 복구를 전신 포즈 검출 성공으로 간주하지 않는다. CPU 설정 자체가 불가능한 경우에도 임의 후보 대신 명시적 실행 오류를 유지한다.

적용 후 번들 상의 샘플은 실행 오류 대신 평가 완료로 표시되었다. 확인한 캡처에서는 오추천 1·누락 1이므로, 실행 경로는 복구했지만 단일 의류의 카테고리 판단 정확도는 해결하지 못했다. 다음 비교는 전신·부분 착장·단일 의류 사진을 분리해 수행해야 한다.

## 해석과 다음 검증

- 기본 모드는 실패하고 CPU만 성공하면 CPU 경로의 정확도·성능을 별도 확인한 뒤 적용을 검토한다.
- 둘 다 실패하면 정상 실행되는 실기기나 다른 공식 런타임에서 같은 진단을 비교한다. 임의 추천이나 점수 기준 완화로 실행 오류를 숨기지 않는다.
- 기존 데이터가 있는 시뮬레이터의 초기화·삭제는 자동으로 수행하지 않는다. 런타임 교체도 큰 다운로드와 개발 환경 변경이므로 별도 작업으로 다룬다.
- 카테고리 평가에서는 실행 오류를 정확도 집계에서 제외한다. 전체 실험 보고에는 시도·성공·실패 수를 함께 남긴다.
