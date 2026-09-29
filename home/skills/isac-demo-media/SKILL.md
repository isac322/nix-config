---
name: isac-demo-media
description: Use when producing or refreshing an open-source project's screenshots, demo videos, terminal recordings, code-snippet cards, before/after PR media, or store/registry screenshots — reference research for signature visuals, scripted reproducible capture from the latest default branch, real-time timing validation, reuse of existing hardware, time-boxed pipeline optimization, background approval, frame inspection, stability metrics, format rules, and per-surface specs; including "데모 영상 찍어", "스크린샷 다시 찍어", "gif 만들어", "영상으로 보여줘", "비포/애프터 영상", "스토어 스크린샷", "터미널 녹화". Not for positioning or claims (isac-positioning), logo/palette/OG/social-preview design (isac-brand-identity), site layout or media gallery UI (isac-project-site), README structure or registry metadata fields (isac-discovery-surfaces), the overall promo-readiness run and owner approval gates (isac-e2e-promo-readiness), or any promotional writing or posting such as launch posts, channel videos, press kits, or outreach (a separate marketing agent owns those).
---

# Demo Media

공개 프로젝트의 스크린샷·녹화·카드·비교 영상을 **실제 제품**으로 재현 가능하게 만든다. 이 스킬은 캡처 방법, 형식, 검수, 규격, 변경 추적을 소유한다. 무엇을 보여 줄지(셀링 포인트, 금지 주장)는 `isac-positioning`의 포지셔닝 원본을, 배경·팔레트·로고·OG·소셜 프리뷰는 `isac-brand-identity`를, 사이트에 붙이는 갤러리 UI는 `isac-project-site`를, README 배치와 레지스트리 메타데이터 필드는 `isac-discovery-surfaces`를 따른다. 디자인·UI/UX 판단(스테이지 구성, 크롭, 캡션 레이아웃)은 반드시 `impeccable` 스킬을 거친다. 오너 승인 게이트와 리뷰 페이지 규약은 `isac-e2e-promo-readiness`, 질문 형식은 `isac-decision-brief`가 소유한다. 채널용 홍보 영상·게시·캡션 카피는 범위 밖이다(별도 마케팅 에이전트).

`[U]` = 사용자 지시·교정·승인에서 온 규칙(사용자 승인 없이 완화·삭제 불가). 태그 없음 = 바꿀 수 있는 기본값. 제품 유형별 캡처 절차는 `references/capture-pipelines.md`, 표면별 규격은 `references/media-specs.md`에 있다.

## 순서

1. 샷 리스트(MED-03) → 2. 시그니처 기능 레퍼런스 조사(MED-08) → 3. 기존 인프라 탐색(MED-14) → 4. 캡처 스크립트 작성·실시간 검증(MED-12, MED-15) → 5. 배경·스테이지 승인(MED-09~10) → 6. 본 촬영·인코딩(시간 박스, MED-18~19) → 7. 프레임 검수·안정성 지표(MED-20~22) → 8. 오너 리뷰 페이지(MED-11) → 9. 표면별 렌디션 배치(MED-26~29) → 10. 이후 변경마다 before/after·스윕(MED-30~31).

## 1. 실제 제품과 커버리지

- **MED-01** [U] 항상 실제 제품을 녹화한다. 현재 소스 트리에서 빌드한 실행물을 실제 세션에서 돌려 찍는다. HTML로 흉내 낸 화면, 손으로 합성한 프레임, 그려 낸 UI는 제품 미디어로 쓰지 않는다. 시뮬레이션은 레퍼런스 조사(MED-08)나 비교 검증(MED-23)의 보조 자료로만 쓰고 그렇게 표시한다.
- **MED-02** [U] 미디어는 **현재** 동작을 보여 준다. 최신 기본 브랜치(예: `origin/main`)를 빌드해 찍고, 촬영 SHA를 기록한다. 촬영 뒤 사용자 가시 동작이 바뀌면 해당 클립을 다시 찍는다(MED-31).
- **MED-03** [U] 샷 리스트는 포지셔닝 원본(`positioning.yml`, 저장소에 기존 규약이 있으면 그것)의 `selling_points`마다 최소 한 개의 클립 또는 스틸을 대응시키고(샷에 `SP` id 기록), 시그니처 기능과 핵심 흐름(설치 → 첫 성공 → 대표 기능)을 빠짐없이 덮는다. 한두 기능만 찍고 끝내지 않는다. `anti_claims`·`planned`에 걸리는 장면은 찍지 않는다. 각 샷에 목적, 보여 줄 동작, 길이, 대상 표면을 적는다.

## 2. 형식

- **MED-04** [U] 영상 우선. 사이트에는 MP4(H.264, `+faststart`)와 WebM(VP9 또는 AV1)을 함께 두고 poster 스틸을 붙인다. 기본 속성은 `muted loop playsinline preload="none"`이고, `prefers-reduced-motion`이면 poster만 보인다. 오디오 트랙은 넣지 않는다.
- **MED-05** [U] README에는 GitHub에 업로드한 영상(이슈·PR 편집기 업로드로 얻는 `user-attachments` URL을 한 줄에 단독 배치)과 저장소에 커밋한 스틸 PNG를 함께 둔다. 스틸은 영상이 재생되지 않는 뷰어(패키지 레지스트리 README 렌더러 등)를 위한 것이다.
- **MED-06** [U] GIF·APNG는 영상이 재생되지 않는 표면에서만 쓴다(`references/media-specs.md`의 표면별 열 참조). 같은 마스터 클립에서 파생하고, 짧게 자르며 용량 예산을 지킨다. "움직이니까 GIF"는 기본값이 아니다.
- **MED-07** 코드와 CLI 출력은 가능하면 텍스트로 둔다. 이미지로 만든 코드 카드(MED-13)는 복사 가능한 코드 블록과 짝지어 쓴다.

## 3. 사전 조사·승인

- **MED-08** [U] 브랜드나 사이트의 얼굴이 될 시그니처 시각 기능은 구현·촬영 전에 레퍼런스 조사 문서를 만든다. 사용자가 지정한 레퍼런스와 스스로 찾은 레퍼런스(오픈소스 구현, 공개 데모, 특허·논문)를 출처와 함께 모으고, 핵심 동작을 비교하며, 제품이 어디서 다르고 무엇을 따를지 적는다. 필요하면 레퍼런스 동작을 작은 스크립트로 시뮬레이션해 비교한다. "소스를 제대로 찾아본 거 맞아?"라는 교정이 다시 나오지 않도록 레퍼런스 목록을 오너 리뷰에 함께 보인다.
- **MED-09** [U] 배경(바탕화면, 터미널 테마, 브라우저 스테이지, 데모 데이터 톤)은 본 촬영 전에 승인받는다. 후보마다 실제 제품 스틸을 최종 크롭으로 합성한 비교 목업, 라이선스와 작성자, UI 주변 밝기·분산 같은 가독성 지표를 한 페이지에 두고, `isac-e2e-promo-readiness`의 승인 게이트로 고르게 한다. 승인 전 대량 촬영 금지.
- **MED-10** [U] 배경은 브랜드 팔레트를 따르고 라이선스가 깨끗해야 한다. 직접 생성한 원본(생성 스크립트 커밋)이나 재배포 가능한 라이선스의 자산만 쓰고, 라이선스·출처 표기를 자산 옆에 커밋한다. 촘촘한 선·노이즈처럼 인코딩에서 깨지는 패턴은 후보 단계에서 표시한다.
- **MED-11** [U] 오너 리뷰용 데모는 오너가 브라우저로 직접 열 수 있는 곳에서 서빙한다. 로컬 `/tmp` 경로를 건네지 않는다. 오너 네트워크에서 닿는 주소(예: 사설망·VPN IP의 정적 서버)나 PR 프리뷰 배포를 쓰고, 상대 경로의 `index.html`에 옵션별 클립을 나란히 두며 각 클립 옆에 안정성 지표(MED-21)를 적는다. 서빙 주소·포트 선택은 오케스트레이터의 리뷰 페이지 규약을 따른다.

## 4. 캡처 파이프라인

- **MED-12** [U] 캡처는 스크립트로 재현 가능해야 하고, 스크립트는 산출 자산 옆에 커밋한다(저장소 규약이 없으면 브랜드 킷 옆 `assets/media/`와 `assets/media/capture/`). 세션 기동, 입력 스크립트, 녹화, 인코딩, 포스터 추출, `NOTES.md`(재생성 명령, 필요 도구 버전, 촬영 SHA)를 포함한다. 한 명령으로 전체를 다시 만들 수 있어야 리브랜드·동작 변경 후 재촬영이 싸다.
- **MED-13** [U] 제품 유형별 기본 경로(세부는 `references/capture-pipelines.md`):
  - 데스크톱 GUI: 가상 컴포지터·디스플레이에서 스크립트 입력으로 녹화.
  - 웹 UI·웹 서비스: 헤드리스 브라우저 자동화의 영상 녹화, 시드된 데모 데이터.
  - CLI·TUI: 터미널 레코더(`vhs` tape 또는 `asciinema` + `agg`).
  - 라이브러리: 실행되는 예제 파일에서 만든 코드 스니펫 카드와 실제 실행 출력.
  - K8s operator·controller: 일회용 로컬 클러스터에서 터미널 녹화 + 리소스 상태 변화, UI가 있으면 브라우저 녹화.
  - MCP·AI 도구 서버: 실제 클라이언트에서 도구 호출과 그로 인한 실제 효과를 함께 녹화.
- **MED-14** [U] 캡처 환경을 새로 만들기 전에 오너가 이미 운영하는 인프라를 찾는다. IaC·홈 인프라 저장소의 GPU·하드웨어 인코더 장치 마운트, 기존 CI 러너, 원격 빌드 호스트 등이다. 같은 하드웨어 문제를 이미 푼 설정이 있으면 그 경로를 재사용하고, 접근이 필요하면 `isac-decision-brief`로 요청한다. 소프트웨어 렌더링이 목표 fps를 못 내면 그 사실을 보고하고 하드웨어 경로를 우선한다.
- **MED-15** [U] 본 촬영 전 길이를 아는 동작(예: 정확히 4.00 s 걸리는 스크립트 포인터 이동, 터미널의 `sleep 3` 후 출력)을 녹화해 결과 파일에서 실제 길이를 잰다(프레임 pts 기준, 기본 허용 오차 ±2 %). 통과해야 본 촬영에 들어간다. 시계를 늦추거나 조작하는 방식(`libfaketime` 류)으로 느린 환경을 감추지 않는다. 애니메이션 떨림과 속도 왜곡을 만든다.
- **MED-16** 고정 `sleep` 대신 준비 신호(창 등장, 첫 프레임, 로그 줄, readiness 프로브)를 기다린다. 세션은 한 번 띄우고 클립 사이에 상태를 초기화한다. 녹화는 무손실 중간 포맷으로 받고 인코딩은 병렬로 돌린다.

## 5. 시간 박스와 최적화

- **MED-17** 캡처·인코딩 단계마다(기동, 촬영, 인코딩, 검수) 소요 시간을 계측해 표로 남긴다.
- **MED-18** [U] 실험마다 시간 박스를 둔다(기본 15–20분). 넘기면 변형을 계속 바꿔 재시도하지 말고 멈춰서 단계별 시간, 병목, 다음 선택지를 보고한다.
- **MED-19** [U] 재촬영이 오래 걸리면 먼저 파이프라인을 최적화한 뒤 다시 찍는다. 계측으로 병목을 찾고(고정 대기, 직렬 인코딩, 매번 재기동), 고친 뒤 개선 전후 시간을 보고한다.

## 6. 검수

- **MED-20** [U] 모든 클립을 프레임 단위로 확인한다. 시작·중간·끝 프레임이나 컨택트 시트를 뽑아 **직접 보고**, 의도한 동작이 실제로 일어나는지(빈 화면, 엉뚱한 창, 입력 누락, 로딩 스피너만 있는 클립 아님) 확인한다. `ffprobe` 프레임 pts로 CFR과 드롭을 점검하고, 루프 클립은 첫 프레임과 끝 프레임이 이어지는지 본다. 앱 이름·아이콘이 제품 것인지도 본다.
- **MED-21** [U] 움직임이 핵심인 기능은 "동작한다"로 끝내지 않는다. 떨림이 보이면 반려 사유다. 수치 지표를 영상과 함께 낸다. 예: 가장자리 jitter(px), 방향 반전 횟수, 기대 대상과 실제 대상 일치율, 프레임 간격 중앙값·p95, 드롭 프레임 수.
- **MED-22** [U] 나란히 놓고 봐도 시각적으로 구분되지 않는 옵션은 데모와 설명에서 뺀다. 수식이나 구현 차이로 구분을 설명하지 않는다. 기본값 하나와 확실히 다른 대안만 남기고, 제품 설정에서 없앨지는 오너에게 묻는다.
- **MED-23** [U] 경쟁 제품·기준선 비교 미디어는 기준선을 실제로 캡처해 만들고 차이를 수치로 잰다(예: 동일 조건 재현의 평균 픽셀 오차 ≤ 1/255). 제품 쪽 시뮬레이션이 필요하면 제품 코드의 실제 수식을 그대로 옮기고 원본과 수치로 대조한다. 비교 주장 자체의 정직 기준은 `isac-positioning`이 소유한다.
- **MED-24** [U] 설정·구성 데모는 실제 존재하는 설정 키만 실제 라벨로 보여 준다. 스키마·설정 정의 파일·설정 UI 소스와 대조하는 독립 리뷰를 거친다.
- **MED-25** 미디어에 비공개 정보(실제 호스트명·IP, 사용자명, 토큰, 내부 클러스터·네임스페이스 이름)가 찍히지 않게 합성 데이터와 데모 계정을 쓴다. 공개 전 확인 기준은 `isac-github-publishing`의 sanitize를 따른다.

## 7. 규격과 배치

- **MED-26** [U] 스토어·레지스트리 스크린샷은 그 표면의 규격대로 만든다(비율, 최소 해상도, 개수, 창 그림자, 캡션). 표와 출처는 `references/media-specs.md`. 규격을 확인하지 못한 표면은 `[verify]`로 남기고 제출 전에 확인한다.
- **MED-27** 마스터는 필요한 가장 큰 규격으로 한 번 찍고(기본 2560×1280, 2:1, 60 fps CFR) 표면별 렌디션을 파생한다. 웹 클립 기본 예산은 파일당 ≤ 2 MB, 모바일용 1280 px 폭 변형, 표시 크기에 맞춘 poster·썸네일이다. 갤러리 로딩·디코딩 정책은 `isac-project-site`와 맞춘다.
- **MED-28** 저장소에는 웹 렌디션, poster, 스틸, 캡처 스크립트, 라이선스 표기만 커밋하고, 재생성 가능한 무손실 마스터와 QA 스크린샷은 커밋하지 않는다.
- **MED-29** 외부 표면이 저장소 raw URL로 미디어를 참조하면 머지 전에는 깨진다. 그런 교체는 머지 후 체크리스트로 넘기고(`isac-discovery-surfaces`), 머지 후 실제 URL이 200을 반환하는지 확인한다.

## 8. 변경 추적

- **MED-30** [U] 사용자 가시 시각 변경 PR마다 같은 스크립트로 찍은 before/after 미디어를 캡션과 함께 PR 본문에 첨부한다. 이 자산은 이후 README·릴리스 미디어로 재사용할 수 있게 보관 위치를 적는다.
- **MED-31** [U] 동작이 바뀌면 머지 전에 저장소가 관리하는 문서, README, 사이트 문구, 앱 메타데이터(metainfo 등), 미디어를 옛 동작 표현으로 검색해 고치고, 영향받는 클립을 다시 찍는다. 코드·문서·사이트 일치 규칙 자체는 `isac-discovery-surfaces`가 소유한다.

## 교정 루프

결과가 기대와 다르면 사용자는 `isac-skill-correction`으로 이 스킬을 교정할 수 있다. 실행 중 사용자가 미디어 방식을 교정했다면 따로 묻지 말고 최종 보고에 한 줄로 안내한다. `references/cases.md`는 교정할 때만 읽는다.
