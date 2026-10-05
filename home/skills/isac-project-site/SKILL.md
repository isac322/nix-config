---
name: isac-project-site
description: Use when building, rebuilding, or hardening an open-source project's landing + docs website — Astro/Starlight/Bun scaffold, impeccable design loop with live previews, sitemap/IA and story order, owned-surface site copy, docs sync from repo Markdown, technical SEO (meta/OG/JSON-LD/sitemap/robots/llms.txt), custom subdomain + GitHub Pages via IaC, analytics, star/CTA nudge, and visual/a11y/perf QA; including "랜딩 페이지 만들어", "프로젝트 사이트 만들어", "문서 사이트 만들어", "사이트맵이랑 순서 정해", "사이트 SEO 세팅해", "커스텀 도메인 연결해", "스타 버튼 눈에 띄게 해", "사이트 검수해", "모바일에서 끊겨". Not for positioning, keywords, or claim evidence (isac-positioning), logo/palette/favicon/OG-image production (isac-brand-identity), README, GitHub About/topics, registry listings, or the parity gate (isac-discovery-surfaces), screenshots and recordings (isac-demo-media), orchestration and approval gates (isac-e2e-promo-readiness), or any promotional writing or posting — launch posts, channel copy, press kits, outreach (the separate marketing agent).
---

# Project Site

오픈소스 프로젝트의 랜딩 + 문서 사이트를 만들고 발견 가능하게 준비한다. 이 스킬은 사이트 스택, IA, 사이트 카피 절차, UI 디자인 루프(impeccable 위임), 문서 동기화, 기술 SEO, 도메인·호스팅 IaC, 분석 배선, star/CTA nudge, 사이트 QA 게이트를 소유한다. 다른 소유자:
- 태그라인·카테고리 전제·셀링 포인트·anti-claims·키워드·검색 의도 지도·성숙도 문구와 "주장은 `file:line` 근거, 수치는 증거이지 셀링 포인트가 아니다" 정직 규칙 → `isac-positioning`(POS). 단일 원본은 `positioning.yml`(저장소의 기존 규약 경로가 있으면 그것)이다. 사이트는 이를 읽기만 하고 새 주장을 만들지 않는다.
- 로고·팔레트·favicon·web manifest 아이콘·OG 이미지·브랜드 킷 → `isac-brand-identity`(BRD). 사이트는 킷을 배선만 한다.
- 스크린샷·녹화·포스터 → `isac-demo-media`(MED). README·GitHub About·레지스트리·code==docs==site parity 규칙 → `isac-discovery-surfaces`(DSC).
- 소유자 프리뷰·승인 게이트, steering report 페이지, 단계 순서 → `isac-e2e-promo-readiness`(E2R). 질문 형식 → `isac-decision-brief`. 토론 → `isac-multi-agent-consensus`. 공개 텍스트 언어·sanitize → `isac-github-publishing`. 문체 → `writing-clearly-and-concisely`, `humanizer`.
- 홍보 글쓰기·게시(런치 포스트, 채널 카피, 프레스킷, fact sheet, 아웃리치, 일정)는 범위 밖이다. 이 스킬은 그런 산출물을 만들지 않는다.

`[U]` = 사용자 지시·교정·승인에서 온 규칙(사용자 승인 없이 완화·삭제 불가). 태그 없음 = 바꿀 수 있는 기본값. SEO 세부는 `references/seo-checklist.md`, QA 세부는 `references/site-qa.md`에 있다.

## 순서

1. 범위 질문 한 번(SITE-01) → 2. PRODUCT.md·DESIGN.md(SITE-06) → 3. concept seed·세계 후보·토론(SITE-07~09) → 4. 라이브 프리뷰에서 소유자 선택(SITE-10) → 5. surface brief 동결(SITE-12) → 6. 사이트맵·순서 먼저(SITE-15~20) → 7. 내용·전달 방식 토론(SITE-21) → 8. 작성자 병렬 집필·패널 검토(SITE-22~31) → 9. 문서 동기화·SEO·도메인·분석(SITE-32~48) → 10. QA 게이트(SITE-53~60) → 11. 변경 보고·승인 후 머지(E2R) → 12. 배포 후 라이브 검증(SITE-61).

## 1. 범위와 스택

- **SITE-01** [U] 사이트 작업을 시작하기 전에 한 번에 묶어 묻는다: 공개 언어, 호스팅·도메인, 배포·머지 범위, 브랜드 중 고정 요소와 확장 가능 요소, 기존(legacy) 페이지 처리. 저장소·memory로 답할 수 있는 것은 묻지 않는다.
- **SITE-02** [U] 스택은 Astro + Starlight, 툴체인은 Bun만 쓴다. `node`·`npm`·`npx`를 쓰지 않는다: `bun install`, `bun run build`, `bunx astro check`, `bunx --bun serve`. CI도 Bun으로 빌드한다. 다른 SSG로 바꾸려면 사용자 승인이 필요하다.
- **SITE-03** 사이트 소스는 제품 저장소의 `site/`에 둔다(유지 부담이 더 크다는 증거가 있을 때만 분리). `package.json` 스크립트는 `sync`, `dev`, `build`, `preview`, `check`. 폰트는 `@fontsource`로 self-host하고 CDN을 쓰지 않는다. 검색은 Starlight 기본 Pagefind.
- **SITE-04** [U] 랜딩은 SaaS식 index 페이지(`src/pages/index.astro`, Starlight 밖의 자유 레이아웃)이고, 문서는 `/docs/<section>/<slug>/` 아래 Starlight 탭으로 둔다. index 페이지가 브랜드의 가장 중요한 표면이다. Starlight override(Header, SiteTitle, Sidebar, Pagination)로 탭별 sidebar와 탭 범위 pagination을 만들고, 사용자 정의 `404.astro`(`disable404Route: true`)와 edit link를 둔다.
- **SITE-05** [U] 기존 사이트를 대체할 때는 새 사이트로 바꾸고 옛 파일을 삭제한다. 개념만 salvage하고 코드는 가져오지 않으며, 가져오지 않을 것(서드파티 색·로고, 옛 폰트, 낡은 주장)을 avoid 목록으로 남긴다. 두 공개 사이트를 병존시키지 않는다.

## 2. 디자인 루프 (impeccable 필수)

- **SITE-06** [U] 모든 UI·UX 작업은 `impeccable` 스킬을 거친다: `impeccable context --target <page>` → PRODUCT.md(`init`, `positioning.yml`에서 파생한 서사만 담고 사실·키워드를 중복하지 않음) → DESIGN.md(BRD 토큰 시드 또는 `document`) → new-work·craft floor → critique·audit → detector. 랜딩은 Persuade 모드, 문서는 Read 모드. 이 절차 없이 디자인하지 않고, 일부만 썼다면 그 사실을 밝히고 전체 절차로 다시 하겠다고 제안한다. PRODUCT.md는 코드와 동기화한다(낡은 제품 문서는 옛 주장을 다시 주입한다).
- **SITE-07** 방향은 재현 가능한 random concept seed와 N개(기본 7) 후보로 시작해 모델의 순위 습관을 깬다. seed key를 기록한다. seed는 방향만 정하고 소유자의 라이브 프리뷰 선택이 우선한다.
- **SITE-08** 시각 "세계" 후보는 청중의 물질 문화(그들이 쓰는 차트·명세서·양식·장비·작업 공간)에서 끌어낸다. 카테고리 기본값(예: devtool의 어두운 네온, 스토리지의 네이비+아이소메트릭 큐브), 그 뻔한 반대(무난한 엔터프라이즈 SaaS), 이름을 글자 그대로 그린 이미지를 명시적으로 제외한다. 경쟁 랜딩 조사의 클리셰 목록(POS)을 금지 목록으로 쓴다.
- **SITE-09** [U] 랜딩 컨셉은 토론으로 정한다: 전략·세계·브랜드 렌즈의 독립 제안 → advocate 간 교차 반박 → BRD의 검증 가능한 브랜드 체크리스트와 방문자 모델로 채점. 취향 논쟁 대신 렌더링 결과에 대해 돌릴 수 있는 점검으로 점수를 낸다.
- **SITE-10** [U] 소유자는 렌더링된 라이브 프리뷰를 보고 고른다. 브라우저로 열 수 있는 URL(소유자가 접근 가능한 호스트의 정적 서버와 index 페이지, 데스크톱·모바일·다크 스크린샷)을 주고 `/tmp` 경로를 건네지 않는다. 변형은 지우지 않고 누적하며, 권하는 대안과 조합은 모두 실제로 만들어 비교 가능하게 한다. 아무도 만들지 않은 조합을 권하지 않는다.
- **SITE-11** [U] 랜딩의 인터랙션은 제품의 핵심 은유에서 가져온다. 예: CLI → 터미널처럼 동작하는 페이지, DB 도구 → 쿼리 콘솔, 게이트웨이·프록시 → hover 가능한 요청 흐름도, K8s operator → reconcile 루프, 데스크톱 GUI 앱 → 페이지 자체가 앱의 한 세션, 라이브러리 → 실행되는 API 스니펫, MCP 서버 → tool-call 기록. 설치 명령은 첫 화면에서 가리지 않고 한 화면 안에 둔다. 인터랙티브 데모는 제품에 실제로 있는 옵션·키만 노출하고 소스와 대조한다. 기존 제품과 비교하는 시각물은 실제 캡처와 제품의 실제 계산을 옮겨 만들고 측정된 차이로 검증한다.
- **SITE-12** 방향을 고르면 surface brief(범위, 청중·과업, 선택한 방향, 고정 토큰, 모티프 규칙, 첫 화면 계약, 금지 패턴)를 `site/.impeccable/surfaces/*.md`에 쓰고, 병렬 빌더가 공유할 작은 계약 파일(토큰 CSS, 브랜드 경로 모듈, 법적 고지 컴포넌트, nav 데이터)을 먼저 만든다. 그 다음에만 빌더를 병렬로 띄우고, 빌더는 서로 겹치지 않는 블록·파일을 소유하며 한 integrator가 합친다.
- **SITE-13** [U] 새로 만들라는 지시에 옛 사이트를 anti-reference로 두면 여전히 옛 모습에 묶인다. 재구축은 소유자가 말한 요구만 담은 문서에서 시작하고, 빌더가 옛 사이트·git 기록·이전 산출물을 열지 못하게 한다. 에이전트가 만든 brief는 소유자 입력보다 넓은 제약을 추가하지 않는다.
- **SITE-14** 배포 뒤 DESIGN.md와 `.impeccable/design.json`을 계획이 아니라 실제 토큰에서 다시 쓰고 drift를 확인해 이후 표면이 상속하게 한다.

## 3. IA: 사이트맵과 순서 먼저

- **SITE-15** [U] 어떤 내용을 어떤 순서로 전달할지가 가장 중요하다. 글을 쓰기 전에 사이트맵과 페이지 순서를 확정한다: 셀링 포인트·anti-claims(POS) → 검색 의도 지도 → 사이트맵·순서 → 페이지별 명세 → 집필.
- **SITE-16** story spine: 방문자가 순서대로 얻어야 할 아이디어 8~12개를 정하고, 각 아이디어에 주 담당 페이지를 하나 배정한다.
- **SITE-17** 문서는 Diátaxis(tutorial / how-to / reference / explanation)로 나누되 탭은 방문자 여정 순서로 둔다. 기본: Overview → Concepts → Get started → Operations(how-to) → Reference → Project. 무엇·왜·한계를 설치 전에 둔다. 각 탭의 마지막 페이지는 다음 탭으로 넘기는 링크를 가진다. Community·기여 문서는 CONTRIBUTING에 링크하고 내부 문서(PRD, 테스트 케이스, 감사 기록)는 공개하지 않는다.
- **SITE-18** tutorial은 안전한 sandbox(로컬 kind·k3d 클러스터, 컨테이너, 임시 디렉터리, 브라우저 playground)가 있을 때만 쓴다. 없으면 첫 실습 페이지는 how-to다. [U] tutorial 중간에 호스트 준비(패키지 설치 등)가 필요하면 왜 필요한지 설명하고 접을 수 있는 블록으로 둔다.
- **SITE-19** 페이지별 명세: H1(`H1 | Project` 형태의 `<title>`이 60자 이하가 되도록, 대개 49자 이하), 첫 문단은 평문 155자 이하(meta description이 된다), 목적, 순서 있는 개요, 사실 출처, 버릴 내용. 경로↔소스 표(`PAGES`: route, source, order, sidebar label)를 IA 산출물로 만든다.
- **SITE-20** 검색 의도 cluster마다 canonical 페이지 하나를 두고 그 페이지의 title·meta·H1에 방문자의 실제 표현을 쓴다. 출처는 `positioning.yml`의 `intent_map`(cluster, canonical_page, title, h1, meta)이며, 사이트에서 값을 바꿔야 하면 원본을 고친다.

## 4. 사이트 카피

- **SITE-21** [U] 어떤 내용을 어떤 방식으로 전달할지는 글을 쓰기 전에 토론으로 정한다. 독립 렌즈(전환, 엔지니어, 브랜드 또는 방문자 페르소나)가 각자 초안을 쓰고, 초안을 쓰지 않은 편집자가 슬롯마다 판정한다: 한 번에 읽히는가, 슬롯에 맞게 짧은가, 요점이 있는가, 인용한 `file:line`에 대해 정확히 참인가.
- **SITE-22** [U] 합의된 내용을 작성자들이 `writing-clearly-and-concisely`와 `humanizer` 스킬로 쓴다. 작성자는 서로 겹치지 않는 파일을 소유하고, 파일 이동은 `git mv`로 하며, 각자 금지 패턴 grep을 자기 파일에 돌린다.
- **SITE-23** 랜딩 문자열은 전부 타입이 있는 카피 모듈 하나(예: `site/src/data/landing-copy.ts`의 `LandingCopy` interface)에 두고 레이아웃은 렌더링만 한다. 사실을 말하는 필드는 `evidence`(코드 경로, GitHub blob 링크로 렌더링)를 가진다. `tsc --noEmit --strict`로 검사한다.
- **SITE-24** 두 렌즈 패널로 검토한다. Truth 패널: 모든 필드를 코드·API·차트·명세와 대조해 `field | 문제 | 증거 file:line | 대체 문구 | 판정` 표를 낸다. Voice 패널: 길이 예산, humanizer 신호, "같은 카테고리 랜딩 10개를 본 사람이 이걸 기억할까?". 작성자는 항목마다 이유를 달아 반영하거나 거절하고, 재빌드 뒤 다시 돌린다.
- **SITE-25** [U] 간결함은 숫자로 관리한다: 섹션별 단어 예산과 뷰포트별 렌더링 페이지 높이 예산(기본 데스크톱 ≤3600px, 360px 폭 모바일 ≤5500px, 랜딩 전체 ≤450단어). 측정값을 보고한다.
- **SITE-26** 브랜드 은유는 최대 두 번, 브랜드·다이어그램 표면에만 쓴다. 주장, H2, meta/OG, CTA, alt 텍스트에는 은유를 쓰지 않는다. 과장 형용사, eyebrow kicker, 섹션 번호, 가짜 숫자, 추천사, 가격 표기를 쓰지 않는다. 수치(테스트 수, 적합성 점수)는 셀링 포인트가 아니라 증거 페이지에만 둔다(POS).
- **SITE-27** [U] 성숙도 표현은 POS가 정한 문구만 쓴다. "experimental", "not production", "preliminary" 같은 hedging을 사이트 크롬·랜딩·문서에서 지우고, 미구현 기능은 "planned"로만 표시하며 title·meta·H1에 넣지 않는다.
- **SITE-28** [U] 첫 공개 릴리스에서는 사이트와 문서에 변경 서사("이제 ~를 지원", "v2에서 바뀜", 마이그레이션 절차)를 쓰지 않는다. 변경 이력은 릴리스 노트에만 있고 문서는 그곳을 가리킨다(릴리스 노트 작성은 이 스킬 범위 밖).
- **SITE-29** [U] 설치 문서는 게시된 portable artifact로만 설명한다(예: OCI 차트, 패키지 레지스트리, Homebrew tap, 배포판 패키지, 컨테이너 이미지). `git clone` 후 빌드·로컬 checkout 설치는 CONTRIBUTING에만 둔다. 버전을 하드코딩하지 않고 최신 버전을 확인하는 명령을 보여 준다.
- **SITE-30** 첫 공개 전 문서·랜딩 전체에 대해 rubric을 먼저 동결하고(변경 서사, 버전 절차, checkout 설치, hedging, 과장) 블록 단위로 bulk judge한 뒤 표시된 블록을 사람이 전부 읽는다.
- **SITE-31** guide는 독자처럼 실제로 실행해 검증한다(플래그 vs `--help`·`helm show values`, 매니페스트 vs 스키마, 출력 컬럼 vs 실제 출력). 구조·spine 검토 하나를 더해 GREEN이 될 때까지 반복한다.

## 5. 문서 동기화와 라우트

- **SITE-32** 문서는 저장소 Markdown이 단일 원본이다. `site/scripts/sync-docs.ts`가 빌드마다 `PAGES` 표대로 Starlight content collection에 복사하고(출력은 gitignore), 저장소 상대 링크를 사이트 라우트로 바꾸고, 원본 H1을 title로, 첫 평문 문단을 description으로 만들고, 이미지를 복사한다. "could not be mapped" 경고는 0이어야 한다. 특수 경우 목록이 늘면 원본 구조를 고친다.
- **SITE-33** 틀린 내용은 생성된 출력이 아니라 원본을 고친다. API·CRD·CLI help·설정 스키마 reference는 코드에서 생성하고, CI에서 생성 후 `git diff --exit-code`로 drift를 막는다. 사이트 밖으로 배포되는 문서(패키지 안 README 등)는 절대 URL을 쓴다.
- **SITE-34** 라우트를 옮기면 Astro `redirects`로 옛 경로를 새 경로로 보낸다(GitHub Pages에서는 meta-refresh). redirect 경로가 sitemap에 없는지, 옛 URL이 새 페이지로 가는지 확인한다. 저장소 전체의 옛 링크를 grep으로 0건으로 만든다.

## 6. 추가 페이지

해당 의도나 근거가 있을 때만 만든다. 가짜로 채운 페이지는 없는 것보다 나쁘다.
- **SITE-35** 비교·대안 페이지: 방문자가 이미 "X alternative", "X vs Y"로 검색하는 경우에만 만든다. 비교 대상의 이름을 쓸지는 소유자가 정한다. 쓰면 페이지당 한 비교, title/H1을 실제 질의대로, 확인 날짜(`checkedOn`)와 출처, 상대가 더 나은 경우를 정직하게 적는다. 쓰지 않으면 기준선(수동 설정, 기본 도구)과만 비교한다.
- **SITE-36** FAQ·반론 페이지: 실제 이슈·토론에서 반복된 질문(왜 X가 아닌가, bus factor, 라이선스, 업그레이드·호환 정책, 보안 태도, 비용)을 저장소 증거로 답한다.
- **SITE-37** Roadmap·Changelog 페이지: 저장소의 ROADMAP·CHANGELOG·GitHub Releases·Milestones를 동기화해 nav에 노출한다. 새 내용을 쓰지 않고 원본을 렌더링한다. 원본이 없으면 만들지 않는다.
- **SITE-38** Try-it 페이지: 가입 없이 5분 안에 체험하는 경로(로컬 sandbox 스크립트, devcontainer·Codespaces 배지, 브라우저 playground, 튜토리얼 환경)를 둔다. 무엇을 증명하지 않는지 적고, Linux·macOS에서 제한 시간 안에 실제로 돌려 본다.
- **SITE-39** 신뢰 페이지: 적합성·벤치마크 같은 수치 증거는 범위(로컬 실행인지, 상류 제출 여부)를 정확히 쓴 전용 페이지에 둔다. `/.well-known/security.txt`와 보안 정책 링크, 공개 언어 결정(i18n 여부와 이유)을 사이트에 반영한다. 신원 확인용 `rel="me"` 링크 자리를 사이트 템플릿에 둔다.

## 7. 기술 SEO

- **SITE-40** 페이지마다 고유한 title(≤60자, 키워드 먼저), meta description(150~160자, 최대 155 권장), 절대 URL canonical, OG·Twitter(`summary_large_image`, 절대 URL 1200×630 이미지), 랜딩 JSON-LD(`SoftwareApplication` + `SoftwareSourceCode`, 가격 0, `sameAs`)를 둔다. 세부와 검증 명령은 `references/seo-checklist.md`.
- **SITE-41** `aggregateRating`·`review`를 지어내지 않고, 리치 결과를 노려 FAQPage 마크업을 붙이지 않는다(실제 FAQ 콘텐츠가 있을 때만).
- **SITE-42** 첫날부터 sitemap(`@astrojs/sitemap`), `Sitemap:` 줄이 있는 robots.txt(검색·AI 검색 봇 허용), `llms.txt`, 404 페이지, web manifest·favicon·theme-color(BRD 킷 배선)를 배포한다.
- **SITE-43** 다른 회사 상표를 참조할 때는 참조형 표현("X for Y")만 쓰고, 첫 렌더링 사용에 표기, 소유격·로고·색 차용 금지, 모든 페이지에 비제휴 고지 컴포넌트를 둔다. 상표 조사 자체는 BRD가 소유한다.

## 8. 도메인·호스팅 IaC

- **SITE-44** [U] 프로젝트마다 자기 브랜드 subdomain을 준다. 사용자 계정의 기본 Pages 도메인 경로(`<user>.github.io/<repo>` 또는 그 위의 개인 도메인)를 상속하지 않는다. 도메인은 소유자의 기존 IaC 저장소에서 기존 프로젝트 패턴을 따라 관리한다.
- **SITE-45** [U] 저장소 Pages 설정·DNS·검증 레코드는 UI 클릭이 아니라 IaC로 한다: repository pages 리소스(`build_type = workflow`, `cname`), 보호 브랜치 전용 `github-pages` environment, `homepage_url`, `<owner>.github.io`로 가는 CNAME(CDN 프록시 끔), Search Console TXT. 기존 리소스는 import하고 `prevent_destroy`를 건다. plan의 import/add/change/destroy 수를 보고하고 독립 리뷰어가 검토한다.
- **SITE-46** HTTPS 순서: DNS·도메인 검증 apply → 계정·조직 수준 verified domain(takeover 방지) → 사이트 배포 → `cname`이 인증서를 받은 뒤 `https_enforced` → http→https 301 확인. 일부 provider 버전은 `cname`과 `https_enforced`를 따로 설정하면 서로를 해제하므로 한 요청에 함께 설정하고 apply 뒤 Pages API로 두 값을 다시 읽는다. IaC가 관리하지 못한 값은 남은 위험으로 보고한다.
- **SITE-47** [U] 에이전트가 자기 도구(브라우저 포함)로 할 수 있는 설정은 소유자에게 넘기지 않는다. 예: 기존 fine-grained token에 필요한 권한(Pages, Administration 등)을 브라우저에서 제자리 추가하고 그 범위를 IaC 변수 설명에 적는다. 2차 인증은 소유자가 지정한 방식을 따른다. 비밀값 처리는 `isac-decision-brief`의 DBR-15~18.
- **SITE-48** Pages 워크플로: PR에서 타입 검사·빌드, 기본 브랜치에서만 배포, action은 SHA 고정, 최소 권한, `pull_request_target` 금지, path filter는 사이트가 import하는 문서·샘플 디렉터리까지 포함. 빌드 타임 외부 fetch(star 수 등)는 timeout과 선택적 토큰을 두고 실패해도 빌드가 깨지지 않는다.

## 9. 분석과 Search Console

- **SITE-49** [U] 분석은 무료·쿠키 없는 도구만 쓰고(예: 호스팅 제공자의 웹 분석 beacon, GoatCounter, 자체 호스팅 Umami), beacon은 빌드 환경 변수가 있을 때만 넣어 fork·PR 빌드에서 빠지게 한다. UTM을 지원하지 않는 도구면 referrer로 귀속한다.
- **SITE-50** Search Console은 Domain property(DNS TXT, IaC)로 검증하고 sitemap을 제출한다. Bing Webmaster는 GSC import로 연결한다. 기준선을 쌓도록 공개 전에 충분히(기본 7일 이상) 먼저 배선한다.
- **SITE-51** [U] 측정 지표마다 API 출처와 기준선이 있어야 하고, 아무도 읽지 않을 수집 자동화(새 토큰이 필요한 주기 archive 워크플로 등)는 소유자 승인 없이 추가하지 않는다. 지표 목표 설정과 보고 운영은 이 스킬 범위 밖이다.

## 10. Star·CTA nudge

- **SITE-52** [U] GitHub star CTA는 소유 표면(랜딩·문서 헤더·푸터)에서 눈에 띄게, 이유를 붙여 둔다. 강도는 사다리(S0 현재 → S1 채워진 헤더 pill → S2 의도 신호 뒤 1회 알림 → S3 실제 stargazer 표시 → S4 설치 명령 복사 뒤 sticky 배너)로 lab에 만들어 소유자가 비교해 고른다. 고른 변형의 차이만 이식하고 재검토한다. 한계: 실제 GitHub API 데이터만, 가짜 수·활동·긴박감 없음, 미리 체크된 동작·콘텐츠 가림·차단 모달 없음, dismiss 가능하고 방문당 1회, 키보드·스크린리더·reduced-motion 대응, 트리거는 의도 신호(설치 명령 복사, 데모 조작). [U] star 수는 임계값(기본 100) 미만이면 숨기고 이상이면 실시간으로 보여 준다. 여러 곳의 요청이 과해지면(critique의 "star-ask saturation") 통합한다.

## 11. QA 게이트

- **SITE-53** [U] 소유자에게 보여 주기 전에 모든 페이지를 직접 시각 QA한다: 1440·1024·768·390·360px, 라이트·다크, 전체 페이지. 일반적인 AI 템플릿 신호(왼쪽 테두리 강조, 빽빽한 표, 장식 카드)를 찾는다. 세부는 `references/site-qa.md`.
- **SITE-54** [U] 텍스트 겹침과 가로 overflow를 자동 스캔한다(형제 bounding-box 충돌, `nowrap` span, 스크롤 단계별 검사, 여러 폭). 결과 0이 게이트다.
- **SITE-55** [U] 피드백 라운드마다 지적된 항목만이 아니라 전체 페이지를 다시 감사한다. 결함 행은 파일 소유자에게 보내고 fixed / still broken / accepted로 닫는다.
- **SITE-56** `impeccable detect --json`을 소스와 빌드 출력에 돌리고, critique와 audit를 서로 격리된 평가자 둘(디자인 리뷰 / detector+브라우저)에게 맡기고, 승인된 surface brief와 craft floor 기준으로 finish reviewer가 ship 판정을 낼 때까지 재채점한다. 검증은 impeccable의 bounded pass 원칙을 따른다.
- **SITE-57** 링크(`lychee`, PR은 내부만, 주기 실행은 외부 포함), HTML 유효성(`vnu --errors-only`), 필수 head 태그 스크립트를 CI에서 돌린다.
- **SITE-58** 접근성 게이트: axe·pa11y CI(WCAG 2.2 AA), 키보드 순회, 포커스 표시, dismiss 뒤 포커스 복원, 모든 애니메이션의 `prefers-reduced-motion`, 44px 터치 타깃, 두 테마 대비.
- **SITE-59** [U] 모바일 성능 예산을 공개 전에 건다: 에뮬레이션된 중급 휴대폰 + CPU throttling으로 프로파일하고, 반응형 미디어 변형(포스터·썸네일 크기, 모바일용 저해상도 영상), 우회되지 않는 lazy loading, 프레임마다 다시 계산되는 blur 금지. 부분 수정으로 예산을 못 맞추면 아키텍처 수준의 대안 프로토타입을 나란히 만들어 비교한다.
- **SITE-60** 사이트 리뷰에 공개 저장소 위생을 포함한다: 리뷰 스크린샷·로컬 dump·`/tmp` 경로·비밀값을 커밋하지 않는다(`.impeccable/review/` 등은 gitignore). 리뷰가 GREEN일 때까지 머지하지 않는다. 머지 전 변경 요약·diff·라이브 프리뷰 제시와 승인은 E2R 게이트를 따른다.
- **SITE-61** 배포 뒤 라이브 사이트를 확인한다: `/`, 문서 한 페이지, sitemap, robots, llms.txt, OG 이미지, favicon·touch icon, manifest가 200이고 없는 경로가 404이며 http→https 301, 인증서 상태, sitemap `<loc>` 수, 페이지별 head 태그. 기억이 아니라 실제 응답으로 보고한다.

## 교정 루프

결과가 기대와 다르면 사용자는 `isac-skill-correction`으로 이 스킬을 교정할 수 있다. 실행 중 사용자가 사이트 작업 방식을 교정했다면 따로 묻지 말고 최종 보고에 한 줄로 안내한다. `references/cases.md`는 교정할 때만 읽는다.
