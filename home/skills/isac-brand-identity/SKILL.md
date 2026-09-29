---
name: isac-brand-identity
description: Use when preparing an open-source project's visual identity for promotion — name/trademark/domain/registry/handle clearance sweep, logo/wordmark/icon/mascot/palette design through impeccable with in-context size-ladder previews and a critique rubric, owner picks from comparison pages, SVG-first brand kit with a generator (favicons, web manifest, app/store/registry icons, GitHub social preview, OG image, avatar, usage rules), third-party trademark hygiene, and atomic rebrand/recolor with re-verification of every copy; including "로고 만들어", "로고 다시", "아이콘 만들어", "브랜드 만들어", "브랜딩 해줘", "색상 바꿔", "파비콘", "소셜 이미지", "브랜드 킷", "이름 괜찮은지 확인해", "상표 확인". Not for positioning/tagline/keywords (isac-positioning), landing/docs site build and head tags (isac-project-site), README/repo settings/registry listing text and uploads (isac-discovery-surfaces), screenshots/recordings (isac-demo-media), the overall promo-readiness run (isac-e2e-promo-readiness), or any promotional writing or posting — launch posts, channel copy, press kits, fact sheets, outreach, social account creation (separate marketing agent).
---

# Brand Identity

오픈소스 프로젝트의 시각 정체성을 홍보 가능한 상태로 준비한다: 이름 clearance, 로고·워드마크·아이콘·마스코트·팔레트, SVG-first 브랜드 킷과 생성기, 파생 이미지 전부, 리브랜드 시 전 표면 동기화. 디자인 판단은 전부 `impeccable` 스킬에 위임한다(BRD-09). 입력인 positioning source(태그라인, 메커니즘, 청중, never-say)는 `isac-positioning`이, 사이트 head 태그·manifest 연결·공개 브랜드 페이지 빌드는 `isac-project-site`가, 소셜 프리뷰 업로드·레지스트리 등록·네임스페이스 claim은 `isac-discovery-surfaces`가, 스크린샷·영상은 `isac-demo-media`가, 오너 preview·승인 게이트와 steering report page는 `isac-e2e-promo-readiness`가 소유한다. 사용자 질문은 `isac-decision-brief`, 다관점 토론은 `isac-multi-agent-consensus`를 따른다. 홍보 글·게시·계정 생성은 이 스킬 범위 밖이다.

`[U]` = 사용자 지시·교정·승인에서 온 규칙(사용자 승인 없이 완화·삭제 불가). 태그 없음 = 바꿀 수 있는 기본값. 평가 rubric은 `references/logo-critique.md`, 킷 구조·생성기·파일/크기 매트릭스·리브랜드 표면 목록은 `references/brand-kit.md`에 있다.

## 순서

1. 입력·질문(BRD-01~04) → 2. 이름 clearance(BRD-05~08) → 3. impeccable context·concept(BRD-09~17) → 4. 맥락 preview·critique·오너 선택(BRD-18~25) → 5. 색(BRD-26~29) → 6. 제3자 상표(BRD-30~31) → 7. 마스터+생성기 커밋 후 킷 fan-out(BRD-32~38) → 8. 리브랜드·재검증(BRD-39~42) → 9. 보고(BRD-43).

## 1. 입력과 첫 질문

- **BRD-01** 시작 전에 positioning source(`positioning.yml`, 스키마와 위치 규약은 `isac-positioning` 소유, 없으면 그 스킬을 먼저 돌린다)와 기존 브랜드 자산(커밋된 SVG, 소셜 카드, 레거시 페이지)을 읽는다. 이미 출하된 브랜드가 있으면 토큰·형상은 **출하된 SVG 원본에서 추출**하고 다시 만들어내지 않는다. 레거시 자산은 salvage/avoid 목록(가져갈 개념, 버릴 색·모노그램·폰트·이모지)으로 정리한다.
- **BRD-02** [U] 그리기 전에 한 번에 묶어 묻는다(`isac-decision-brief` DBR-12): 어떤 브랜드 요소가 고정이고 어떤 것이 확장 가능한지, 원하는 스타일 계열(다중 선택 + 자유 입력: 미니멀 기하 심볼 / 워드마크 중심 / 생태계풍 컬러 아이콘 / 일러스트·마스코트 등), 이름을 얼마나 문자 그대로 그려도 되는지(literalness), 레거시 자산 처리. 각 선택지에 비슷한 프로젝트 선례를 붙인다.
- **BRD-03** [U] 에이전트가 스스로 만든 제약(예: "이름 속 사물을 그대로 그리지 않기", "글자 모노그램 금지")을 오너 의도보다 우선하지 않는다. 오너가 "이름에 맞는 그래픽"을 원하면 그 제약을 즉시 풀고 brief를 고친다.
- **BRD-04** 오너가 확정한 디자인 절차 선호(스킬 의무, 요구사항만으로 재빌드, 선택한 팔레트 이름)는 long-term memory에 남겨 다음 프로젝트가 거기서 시작하게 한다. 프로젝트별 값(색, 이름)은 스킬에 굽지 않는다.

## 2. 이름·상표·네임스페이스 clearance

- **BRD-05** 프로모션 전 1회, 이름 clearance sweep을 한다: 상표 DB(USPTO, WIPO Global Brand DB, TMview), 같은 이름의 OSS 프로젝트(GitHub 검색, 검색엔진), 패키지·레지스트리 네임스페이스(프로젝트 유형별: PyPI, npm, crates.io, Go module path, Docker Hub/GHCR org, Helm/Artifact Hub, OperatorHub, Flathub app id, AUR/COPR, MCP registry 네임스페이스, VS Code publisher 등), 도메인, GitHub user/org, 주요 소셜 handle(sherlock류 도구로 가용성만 확인). 결과는 표(대상, 상태, 점유자, 충돌 위험, 조치)로 남긴다.
- **BRD-06** 이름이 이미 다른 곳에서 쓰이면 전 표면에서 일관된 qualifier(예: `<name>-dock`, `<name>-csi`, `<name> for <platform>`)를 쓰도록 권고하고, 개명·qualifier·유지 중 선택을 오너에게 묻는다. 결정된 qualifier는 `positioning.yml`의 `identity.qualifier`로 넘긴다. 상표 충돌 가능성이 있으면 법적 판단을 내리지 않고 근거와 함께 오너 결정으로 넘긴다.
- **BRD-07** 개인 계정 vs 전용 org 같은 repo 정체성 결정은 URL이 레지스트리·릴리스 메타데이터·배지에 박히기 **전에** 오너에게 묻는다. 이전 비용이 가장 싼 시점이 지금임을 적는다.
- **BRD-08** clearance는 확인·보고까지다. 레지스트리 네임스페이스 claim과 canonical 메타데이터 게시는 `isac-discovery-surfaces`, 소셜 계정 생성·handle 예약은 마케팅 쪽 준비 목록으로 넘긴다(목록만 전달).

## 3. impeccable 절차와 컨셉

- **BRD-09** [U] 로고·워드마크·아이콘·팔레트·마스코트·카드 디자인은 전부 `impeccable` 스킬을 끝까지 거친다: `impeccable context`(cwd = repo) → PRODUCT.md가 없으면 init → `reference/new-work.md`(visual world) → `concept-seed --scope direction` → `reference/craft-floor.md` → 제작 → critique/`detect` → 한정된 검증(빌드 → 한 번 검사 → 한 번에 수정 → 한 번 확인). impeccable 없이 그린 시안은 제출하지 않는다.
- **BRD-10** [U] 보고와 모든 비교 페이지에 impeccable의 어느 단계를 실행했고 어느 단계를 건너뛰었는지 명시한다. 건너뛴 단계가 있으면 그 사실과 전체 절차로 다시 할지를 먼저 묻는다.
- **BRD-11** [U] 재디자인이 계속 기존 작업으로 수렴하면("anti-reference"로 줘도 끌려감) 오너 발언만 담은 요구사항 파일을 새로 쓰고, 기존 시안·자산 접근을 막은 새 디자이너로 blank-slate 라운드를 돌린다.
- **BRD-12** visual world는 제품 메커니즘과 청중의 문화(그들이 매일 보는 표기법, 문서 양식, 도구 UI, 도면, 차트)에서 끌어온다. 카테고리 기본값(예: devtool의 다크 네온, 스토리지의 아이소메트릭 큐브, AI 도구의 스파클·그라디언트 blob)과 그 뻔한 반대(무난한 enterprise SaaS)는 후보에서 뺀다.
- **BRD-13** [U] 이름의 문자 그대로 해석은 기본적으로 후보 중 최대 1개로 제한한다. 단 BRD-02에서 오너가 literal을 원했다면 literal 계열을 여러 스타일로 탐색한다.
- **BRD-14** [U] 워드마크·마크는 이름만이 아니라 제품의 시그니처 메커니즘에서 도출한다(예: dock → 확대·활성 표시, CLI → 커서·프롬프트, gateway·proxy → 흐름 화살표·문, storage → 적층, library → 조합 블록, MCP 서버 → 연결 포트·핸드셰이크, 웹 서비스 → 핵심 사용자 동작).
- **BRD-15** 마스터는 코드로 작성한 SVG다(생성기 스크립트, 짝수 좌표 그리드). 이미지 생성 모델 산출물을 마스터로 쓰지 않는다. 텍스트는 처음부터 path로 만든다.
- **BRD-16** 라운드당 후보는 N개 방향 × 2 후보, 각 디자이너가 ≥1회 자체 수정("디자이너가 이걸 출하할까?")을 거친 뒤에만 critique로 넘긴다.
- **BRD-17** 마스코트를 만들면 라이선스(CC-BY 또는 CC0 권장)를 먼저 정해 커뮤니티 재사용 조건을 킷 문서에 적는다.

## 4. 맥락 preview, critique, 오너 선택

- **BRD-18** [U] 후보는 스와치나 단독 캔버스가 아니라 **제품 자신의 맥락** 안에서 보여 준다: 실제 앱 런처·dock·패널, 브라우저 탭 favicon, 둥근 avatar crop, README 헤더(GitHub 다크·라이트), 사이트 nav lockup, 소셜 카드. 프로젝트 유형별 맥락 목록은 `references/logo-critique.md` §2.
- **BRD-19** 모든 후보를 전 목표 크기 ladder(16/24/32/48/128/256 px, nav lockup 28 px 높이)와 다크·라이트 양쪽에서 한 장의 contact sheet로 렌더한다(resvg). 소형용 별도 small 마스터(16–24 px)를 항상 포함한다.
- **BRD-20** [U] 아이콘은 실제로 옆에 놓일 이웃(같은 생태계 앱 아이콘, 같은 카테고리 프로젝트 로고, 배지 줄)과 나란히 놓은 생태계 mock에서 구별되는지 판단한다. 손으로 그린 이웃 아이콘은 "근사치"라고 표시한다.
- **BRD-21** 평가는 서로 독립된 두 critic(브랜드 관점 vs craft·가독성 관점)이 `references/logo-critique.md` rubric으로 전 후보 순위를 매긴다. critic은 유사 기호(전원 버튼 IEC 5009, 플러그, 벽, 재생 버튼 등) look-alike를 반드시 표시하고, 병합 선택에 정확한 형상 수정 ≤3개를 준다.
- **BRD-22** 브랜드 의도를 렌더된 결과로 검증 가능한 8–12개 체크(마크 크기, 모티프 반복, 금지된 제3자 색 0개, favicon·OG가 마크에서 파생, 양 테마 대비 등)로 적고, 취향 논쟁 대신 그 체크로 방향을 채점한다.
- **BRD-23** [U] 오너에게 보이기 전에 에이전트가 먼저 시각 QA를 한다. "싸 보임", 흐린 소형 렌더, 제네릭 AI 템플릿 징후는 결함이다.
- **BRD-24** [U] 오너는 비교 페이지에서 고른다: 오너가 접근할 수 있는 URL로 서빙한 index 페이지(방향별 contact sheet + 맥락 mock + critic 점수 + 사용한 impeccable 단계). 호스팅·approval 게이트는 `isac-e2e-promo-readiness` 규칙을 따른다. 이전 라운드와 변형은 지우지 않고 남겨 되돌아갈 수 있게 한다. `/tmp` 경로만 던지지 않는다.
- **BRD-25** [U] 오너가 전부 거절하면 같은 방향을 다듬지 말고 BRD-02의 스타일·literalness 질문으로 돌아가 다음 라운드 전제를 바꾼다.

## 5. 색

- **BRD-26** [U] 브랜드 색은 이름의 의미와 제품 성격에서 도출한다. 플랫폼·생태계의 기본 accent(데스크톱 환경 기본 파랑, 클라우드 벤더 주황, K8s 파랑 등)를 브랜드 색으로 쓰지 않는다. 생태계 accent는 focus ring·활성 표시 같은 플랫폼 affordance에만 남긴다.
- **BRD-27** 팔레트는 역할이 붙은 5–7색(ink, ground, primary, accent 하나, 보조)과 다크·라이트 변형으로 정의한다. 모든 전경·배경 쌍의 대비를 양 테마에서 계산한다: 본문 텍스트 WCAG 4.5:1, 큰 텍스트·그래픽·UI 3:1 이상, APCA Lc는 보조 지표로 함께 기록. 텍스트에 실패하는 색은 "그래픽 전용"으로 명시하고, 필요하면 라이트 잉크 워드마크 변형을 만든다.
- **BRD-28** [U] 팔레트는 스와치가 아니라 맥락 mock(사이트 히어로 다크, README 헤더 라이트, 생태계 패널, 아이콘 ladder)에서 판단한다. 2–3개 팔레트를 각각 사이트·아이콘 사본에 입혀 비교 페이지로 낸다.
- **BRD-29** 팔레트 확정 후 impeccable documenter로 빌드된 코드에서 DESIGN.md(토큰 + 이름 붙은 규칙)를 쓰고, `positioning.yml`의 `brand:` 블록(이 스킬이 채움: 팔레트, 자산 경로, 컨셉 한 줄, 소셜 프리뷰 경로, 사용 문서 경로)을 갱신해 docs·consistency gate가 읽게 한다.

## 6. 제3자 상표

- **BRD-30** 플랫폼·재단 제품을 대상으로 하는 프로젝트면(예: 특정 클라우드용 operator, 특정 데스크톱 환경용 앱, 특정 AI 클라이언트용 서버) 그 상표 가이드라인을 가져와 규칙으로 옮기고 `positioning.yml`의 `third_party_marks`와 맞춘다: 참조형 표현("X for <Platform>")만, 소유격 금지, 첫 렌더 사용에 ®/™, 상대 로고·로고 색 사용 금지, 메타 태그·키워드에는 참조 한 문장까지, 제휴를 암시하는 로고 병치 금지, 모든 페이지 비제휴 문구(렌더는 `isac-project-site`).
- **BRD-31** 마크가 플랫폼 마크와 닮았으면(같은 형상 모티프, 같은 hex) 해당 가이드라인 기준으로 critique에서 결함 처리하고, 빌드 CSS·SVG에 금지 hex가 0개인지 스캔한다.

## 7. SVG-first 브랜드 킷과 생성기

- **BRD-32** [U] 확정 자산은 git 안 한 폴더에 SVG 우선으로 모은다. 저장소 규약이 없으면 `assets/brand/`. 나중에 어디서든 재사용할 수 있게 원본 SVG + 생성기 + 사용 규칙을 함께 커밋한다.
- **BRD-33** 마스터(아이콘, small 아이콘, 워드마크, lockup)와 생성기를 먼저 리뷰·커밋한 뒤에야 파생 작업(앱 아이콘 통합, 소셜·스토어 이미지, README 헤더, 사이트 복사본)을 병렬로 나눈다. 모든 파생물은 하나의 생성기와 하나의 상수 파일에서 나온다.
- **BRD-34** 생성기는 결정적이다: 브랜드 상수 한 곳, 텍스트는 path로 bake(usvg), PNG는 resvg로 렌더 후 oxipng로 압축, 사이트가 서빙하는 복사본도 byte-identical로 써 준다. 재실행 시 다른 파일이 바뀌지 않아야 한다. 명령·게이트는 `references/brand-kit.md` §2.
- **BRD-35** 킷은 `references/brand-kit.md` §3 매트릭스를 채운다: mark/logo(horizontal·stacked)/wordmark × color·mono·`currentColor` × dark·light, 앱 아이콘, favicon.svg/ico, apple-touch-icon, manifest 아이콘 192/512/maskable, site.webmanifest + theme-color, GitHub 소셜 프리뷰 1280×640 <1 MB, OG 1200×630, avatar, README 배너, 해당 레지스트리·스토어 아이콘. favicon 세트는 manifest까지 있어야 완성이다.
- **BRD-36** 앱 아이콘은 플랫폼 관례로 통합한다: 아이콘 이름 = reverse-DNS app id, 전체 크기 ladder + scalable SVG, 창 아이콘, About 메타데이터. 웹·CLI 프로젝트의 대응물은 favicon/PWA 세트와 터미널 배너다. 패키징 검증기(`desktop-file-validate`, `appstreamcli validate` 등)는 깨끗한 컨테이너에서 돌린다.
- **BRD-37** 킷에 사용 문서(`assets/brand/README.md`)를 둔다: 컨셉, 파일별 배경 용도, 팔레트·대비, 서체, clear space, 최소 크기, do/don't, 제3자 마크 규칙, 자산 라이선스·상표 문구, 재생성 명령. 공개 브랜드 페이지는 이 문서를 원본으로 `isac-project-site`가 만든다.
- **BRD-38** 킷 게이트: 재생성 후 SVG byte-identical, 래스터는 동일 또는 RMSE 허용치 이내, 어떤 SVG에도 `<text>` 없음, `file`로 크기 확인, 소셜 <1 MB, manifest JSON 유효, 서빙 복사본 `cmp` 동일, 에이전트가 모든 PNG를 직접 본다.

## 8. 리브랜드·재색상

- **BRD-39** 색이나 형상을 바꾸기 전에 기존 SVG를 다시 렌더해 커밋된 PNG와 diff(AE=0)해 정확한 레시피를 복원한다. 그다음 생성기 상수만 바꿔 전체를 재생성한다.
- **BRD-40** [U] 변경은 한 번에 **모든** 표면에 적용한다: 사이트 로고, 설치되는 앱 아이콘, favicon·ico 프레임, PWA 아이콘, 소셜·OG, README 배지 색, AppStream `<branding>`·패키지 메타데이터, DESIGN.md·positioning `brand:` 블록. 옛 hex grep과 픽셀 스캔으로 옛 팔레트가 0임을 증명한다.
- **BRD-41** [U] 리브랜드 뒤에는 저장소 밖에 **업로드된 사본**을 전부 다시 확인한다: GitHub 소셜 프리뷰, 레지스트리·스토어 아이콘과 스크린샷, 릴리스 배너, avatar, 외부 README 이미지 링크. 표면 목록은 `references/brand-kit.md` §5. 재업로드·레지스트리 재게시는 `isac-discovery-surfaces`가 수행하고, 이 스킬은 누락 없는 목록과 새 파일을 넘기고 결과를 live로 재확인한다.
- **BRD-42** 레지스트리는 게시된 패키지에서 메타데이터를 읽으므로, 아이콘·브랜드 메타데이터 반영에 no-behavior-change 릴리스가 필요하면 그 사실을 오너에게 알리고 결정을 받는다(`isac-discovery-surfaces`).

## 9. 보고

- **BRD-43** 최종 보고: clearance 표 요약과 오너 결정 대기 항목, 실행한/건너뛴 impeccable 단계, 비교 페이지 URL과 선택 결과, 팔레트 대비 표, 킷 파일 목록과 재생성 명령, 게이트 결과(실행한 것만), 넘긴 외부 업로드 목록과 live 재확인 상태.

## 교정 루프

결과가 기대와 다르면 사용자는 `isac-skill-correction`으로 이 스킬을 교정할 수 있다. 실행 중 사용자가 브랜드 절차를 교정했다면 따로 묻지 말고 최종 보고에 한 줄로 안내한다. `references/cases.md`(첫 교정 때 생성)는 교정할 때만 읽는다.
