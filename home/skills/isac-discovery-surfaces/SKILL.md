---
name: isac-discovery-surfaces
description: Use when preparing an open-source project's discovery surfaces for promotion — README and install contract, GitHub About/topics/homepage, social preview upload, repo settings via IaC, health files, trust signals (SECURITY.md, signed releases, SBOM, Scorecard, license detectability), registry and store listing metadata (pkg.go.dev, PyPI, npm, crates.io, Homebrew, MCP registry, etc.), and the code==docs==site==listings parity gate; including "README 정리해", "설치 섹션 검증해", "토픽 골라", "About 설명 바꿔", "소셜 프리뷰 올려", "레지스트리 메타데이터 채워", "pkg.go.dev 라이선스 안 보여", "배포 채널 정리해", "문서랑 코드 일치시켜", "외부 노출 위치 다 찾아서 반영해". Not for positioning or keyword research (isac-positioning), asset creation (isac-brand-identity), landing/docs site build and site SEO (isac-project-site), screenshots and recordings (isac-demo-media), orchestration and approval gates (isac-e2e-promo-readiness), or any promotional writing or posting — launch posts, channel copy, press kits, outreach submissions (the separate marketing agent).
---

# Discovery Surfaces

사람과 검색엔진·레지스트리가 프로젝트를 처음 만나는 **소유 표면**을 준비한다: README, GitHub 저장소 표면(About·topics·homepage·social preview·설정·커뮤니티 파일), 신뢰 신호, 레지스트리·스토어 listing 메타데이터, 그리고 이 모두가 코드와 일치하게 묶는 일관성 게이트. 태그라인·카테고리·키워드·anti-claim의 **내용**은 `isac-positioning`의 positioning source가 소유하고 이 스킬은 그것을 각 표면에 옮기고 동기화한다. 로고·social preview 이미지 제작은 `isac-brand-identity`, 사이트와 사이트 SEO는 `isac-project-site`, 스크린샷·영상은 `isac-demo-media`, 단계 순서·owner 승인 게이트·최종 감사는 `isac-e2e-promo-readiness`가 소유한다. 홍보 글 작성·게시(런치 포스트, 채널 문구, 프레스킷, fact sheet, 디렉터리·아웃리치 제출, 일정)는 범위 밖이며 산출물로 만들지 않는다. **code == docs == site == listings 패리티 규칙은 이 스킬이 소유**하고 다른 스킬은 DSC-43~50을 ID로 참조한다.

`[U]` = 사용자 지시·교정·승인에서 온 규칙(사용자 승인 없이 완화·삭제 불가). 태그 없음 = 바꿀 수 있는 기본값. 세부 체크리스트: `references/repo-surface.md`(GitHub 설정·README·커뮤니티·신뢰 신호), `references/registries.md`(생태계별 메타데이터).

## 순서

1. 표면 인벤토리·접근 확인(DSC-01~05) → 2. positioning source 확인, 없으면 `isac-positioning` 먼저 → 3. README(DSC-06~14) → 4. 저장소 표면(DSC-15~24) → 5. 커뮤니티·신뢰 신호(DSC-25~31) → 6. 레지스트리 메타데이터(DSC-32~42) → 7. 동기화·패리티 게이트(DSC-43~50) → 8. 머지·릴리스 후 라이브 검증과 보고(DSC-51~54).

## 1. 표면 인벤토리와 접근

- **DSC-01** [U] 이미 있는 곳만 고치지 않는다. 브랜드·SEO 요소가 들어가야 할 위치를 저장소 안팎에서 샅샅이 찾는다. 저장소 안: 추적 파일 전체를 사전에 고정한 rubric(`must_change` / `should_review` / `irrelevant` × 자산 종류: 앱 아이콘, 워드마크 배너, social 이미지, 스크린샷, 브랜드 색·문구)으로 bulk 분류하고 플래그된 파일만 사람이 읽는다. 전형적 대상: README, 패키지 매니페스트(`go.mod`, `pyproject.toml`, `package.json`, `Cargo.toml`, `Chart.yaml`, `*.metainfo.xml`, `.desktop`, spec/PKGBUILD/`debian/control`), About 대화상자, docs index.
- **DSC-02** 저장소 밖: 읽기 전용 scout가 각 외부 표면(GitHub About·social preview, 사이트, 레지스트리·스토어 페이지, 배포 채널 페이지)의 현재 상태, 필드, 이미지 규격, 쓰기 방법(API / CLI / IaC / 브라우저 전용), 필요한 자격증명의 **존재 여부**(값은 출력하지 않음)를 표로 남기고 P1~P4 우선순위를 매긴다. 생태계별 대상은 `references/registries.md` §0.
- **DSC-03** 모든 공개 표면을 코드와 대조하는 첫 감사를 한다: 설치 경로가 실제 배포 산출물인지, homepage URL이 살아 있고 공개 대상인지, 링크 대상 파일이 있는지, topics·social 이미지가 미출시 기능을 광고하지 않는지, 모듈 경로·패키지 이름이 저장소 URL과 맞는지. 결과는 파일:라인 근거가 있는 결함 목록이다.
- **DSC-04** [U] 에이전트가 자기 도구(브라우저 포함)로 할 수 있는 작업은 owner에게 넘기지 않는다. 토큰 권한이 부족하면 기존 fine-grained 토큰에 필요한 권한만 제자리에서 추가하고(재발급하지 않음) IaC 변수 설명에 새 scope를 적는다. 자격증명 요청 방법은 `isac-decision-brief` DBR-15~18.
- **DSC-05** 로그인이 필요한 표면은 먼저 세션을 읽기 전용으로 확인한다. 자격증명은 추측하지 않는다. 막힌 표면은 넣을 자산·문구·필드값을 모두 준비한 "blocked, assets ready" 목록으로 보고하고, owner가 로그인할 수 있게 통제 브라우저에 로그인 페이지를 열어 둔 뒤, 반영 후에는 서비스 API나 렌더된 페이지로 확인한다.

## 2. README

- **DSC-06** 평가자 우선 순서: 로고 헤더 → 한 줄 정의(무엇) → 왜(해결하는 문제와 메커니즘) → 지원 매트릭스(Shipped / Planned) → 대안 비교(있다면, 날짜·근거 포함) → 동작 방식 → quickstart → 사이트·문서 링크 → 기여·보안·라이선스. 세부 템플릿은 `references/repo-surface.md` §2.
- **DSC-07** [U] README 맨 위에 `<picture>`로 라이트/다크 로고 lockup 헤더(`prefers-color-scheme` source + 라이트 기본 `<img>`, 의미 있는 alt)를 두고, 그 아래 태그라인 한 줄, 링크 행(Website · Install · Docs · Changelog 등), 배지를 둔다. 스크린샷·영상은 첫 화면 아래에 둔다(형식 규칙은 `isac-demo-media`). 다크/라이트 렌더링은 GitHub에서 실제로 눈으로 확인한다.
- **DSC-08** 첫 ~160자(렌더된 첫 문단)는 검색 스니펫·레지스트리 요약으로 그대로 쓰인다. positioning source의 카테고리와 핵심 키워드를 담은 "X is a Y for Z" 형태로 쓰고, 사이트 첫 문단·About·레지스트리 요약과 같은 정의를 쓴다(DSC-45).
- **DSC-09** [U] 설치 섹션은 제품의 계약이다. 릴리스 전마다 README의 설치 명령을 **그대로** 깨끗한 환경(새 컨테이너·새 사용자 프로필, 저장소 checkout 없음, 로컬 빌드 산출물·wheel 없음, 우회 없음)에서 실행해 실제로 동작함을 본다. 실패하면 환경을 고치지 말고 멈춰 보고한 뒤 README와 패키지 메타데이터를 고친다. CI가 로컬 빌드 산출물로 설치해 통과하는 것은 README 경로의 증거가 아니므로 그렇다고 명시한다.
- **DSC-10** [U] 사용자 문서의 설치는 공개된 portable 산출물(레지스트리 패키지, OCI chart, 릴리스 바이너리, 스토어 패키지)만 쓴다. git checkout·로컬 빌드 절차는 CONTRIBUTING으로 보낸다. 버전은 하드코딩하지 않고 최신 버전을 확인하는 명령을 안내한다. sdist 전용 네이티브 의존성처럼 설치 전 준비가 필요하면 배포판별 "Build prerequisites"를 적고 패키지 이름을 배포판 인덱스에서 확인한다. MCP·플러그인처럼 등록 경로가 여러 개면 각 클라이언트 경로를 모두 적고 문서 간 byte 단위로 같게 유지한다.
- **DSC-11** [U] 소유 표면(README·사이트)에는 실제로 출시·사용 중인 것만 쓰고 "experimental", "not production", "PRELIMINARY" 같은 헤징 상태 블록을 넣지 않는다. 미구현은 "planned"로만 표시하고 제목·H1·메타·topics에 넣지 않는다. 성숙도 문구 자체는 `isac-positioning` 소유.
- **DSC-12** [U] 첫 공개 릴리스의 README·문서에는 변경 서사("이제 ~를 지원", "v0.x에서 바뀜", 이전 방식 대비 설명)를 쓰지 않는다. 변경 이력은 CHANGELOG와 릴리스 노트에만 둔다.
- **DSC-13** SEO에 쓰이는 헤딩과 표 행 키는 편집할 때 안정적으로 유지한다. 개수 같은 변동 수치는 본문에 쓰지 않는다("collects 99 tests" → "collects every test under tests/e2e"); 역사적 수치는 CHANGELOG에만 둔다.
- **DSC-14** README가 패키지 안에 실려 레지스트리에 렌더되면(chart README, PyPI/npm/crates long description) 이미지·링크를 절대 URL로 쓴다. 없는 파일·내부 문서(PRD, 에이전트 지침 파일) 링크를 남기지 않는다.

## 3. GitHub 저장소 표면

- **DSC-15** About description: ≤~160자, 카테고리 + 핵심 키워드 + 차별점 메커니즘 한 줄. 미출시 기능은 넣지 않는다(DSC-11). 경쟁 저장소 description을 `gh api`로 비교해 흔한 문구를 피한다.
- **DSC-16** topics 선택 방법: 후보를 positioning 키워드·생태계 용어·구현 기술·사용 맥락에서 뽑고, 각 topic 페이지의 저장소 수를 `gh api search/repositories -f q=topic:<t>`로 잰다. 큰 일반 topic(노출) 몇 개와 경쟁이 적은 niche 복합 topic(순위)을 섞어 ≤20개로 고른다. [U] 출시된 기능만 태그한다. 폐기 topic·오타·중복 변형은 제거한다. 절차와 예시는 `references/repo-surface.md` §3.
- **DSC-17** homepage는 프로젝트 자체 사이트(없으면 docs 또는 README 앵커)로 두고 살아 있는지 확인한다. 상속된 사용자 도메인·내부 문서 URL을 두지 않는다.
- **DSC-18** [U] social preview는 반드시 등록한다. 이미지는 `isac-brand-identity`가 만든 1280×640, <1 MB PNG. REST API가 없으므로 로그인된 브라우저 세션으로 Settings → Social preview에 업로드한다: (1) 편집 권한 세션 읽기 전용 확인 → (2) 업로드 전 이미지를 직접 본다 → (3) 업로드 → (4) GraphQL `usesCustomOpenGraphImage: true`와 새 `openGraphImageUrl`을 확인하고 새로고침 후에도 유지되는지 본다. 팔레트·이름이 바뀌면 다시 올린다(DSC-52).
- **DSC-19** [U] 저장소 설정(description, homepage, topics, features, Pages·custom domain, environments, 보안 기능, branch protection, Actions 변수)은 owner가 IaC를 운영하면 그 IaC로 바꾼다. UI 클릭이나 일회성 `gh api` PATCH는 IaC가 없거나 provider가 지원하지 않는 설정에만 쓰고, 그 경우 명령을 기록한다. IaC 적용 순서·권한·provider 함정은 `references/repo-surface.md` §1.
- **DSC-20** 브라우저 전용 설정(social preview, 일부 토큰 권한, 외부 콘솔 연동)은 IaC와 의존 순서를 맞춘다: IaC 적용 → 검증 → 브라우저 설정 → API로 재확인.
- **DSC-21** Discussions를 켜고 카테고리(Q&A, Show and tell, Ideas, Announcements)를 둔다. 이슈는 issue forms(YAML)로 받는다: bug(재현 단계·버전·환경 필수), feature, "tried it"(성공 / N단계에서 실패, 환경, 버전). 모든 form에 "어디서 알게 됐나" 선택형 필드를 넣고 `config.yml`에서 blank issue를 끄고 Discussions·보안 신고로 안내한다.
- **DSC-22** 기여자 입구: CONTRIBUTING에 dev setup quickstart, 라벨 체계(`good first issue`, `help wanted`), 파일 경로와 완료 기준이 적힌 실제 작업 3~8개를 `good first issue`로 준비한다(생성 여부는 owner 확인).
- **DSC-23** 공개 저장소 위생: 리뷰 스크린샷, `/tmp` 경로, 세션 산출물, 마케팅 상태·초안·지표는 커밋하지 않는다(필요하면 비공개 저장소). 사이트·표면 리뷰에서 발견하면 머지를 막는다.
- **DSC-24** 저장소 identity(개인 계정 vs 조직, 모듈 경로, 패키지 이름)는 레지스트리·배지 URL에 굳기 전에 확정한다. owner 결정이며 `isac-decision-brief` DBR-02로 묻는다.

## 4. 커뮤니티 파일과 신뢰 신호

- **DSC-25** GitHub Community Standards를 100%로 맞춘다: README, LICENSE, CODE_OF_CONDUCT(Contributor Covenant), CONTRIBUTING, SECURITY, SUPPORT, issue forms, PR template. 확인: `gh api repos/{o}/{r}/community/profile --jq .health_percentage`. 파일을 `docs/`나 `.github/`로 옮겨도 GitHub가 인식하는 위치인지 확인한다.
- **DSC-26** 보안: SECURITY.md(지원 버전, 신고 경로, 응답 목표), private vulnerability reporting 활성화(`PUT /repos/{o}/{r}/private-vulnerability-reporting` 또는 IaC), 사이트가 있으면 `/.well-known/security.txt`(RFC 9116, 사이트 배치는 `isac-project-site`).
- **DSC-27** 공급망: 릴리스 산출물에 SHA256SUMS, 서명(cosign keyless 등), SBOM(SPDX/CycloneDX), 빌드 provenance(GitHub artifact attestations, SLSA)를 붙이고 검증 명령(`gh attestation verify`, `cosign verify-blob`)을 문서에 적는다. 레지스트리 게시는 토큰 대신 OIDC trusted publishing을 쓴다(PyPI, npm `--provenance`, crates).
- **DSC-28** OpenSSF Scorecard 주간 workflow로 `api.scorecard.dev`에 게시하고 배지를 단다. 인프라 성격 프로젝트는 OpenSSF Best Practices 자가 인증을 검토한다. 전체 readiness를 CLOMonitor·repolinter 규칙으로 CI에서 점검할 수 있다(`references/repo-surface.md` §5).
- **DSC-29** 라이선스는 기계가 인식해야 한다. GitHub `license.spdx_id`와 레지스트리 판정(예: pkg.go.dev는 인식 못 하면 README·API 문서를 숨김)을 확인하고, `google/licensecheck`(또는 licensee, scancode)로 LICENSE 원문 일치율을 잰다. 조항이 빠지거나 바뀌어 인식되지 않으면 원인을 보이고 선택지(정본 텍스트로 교체 + 저작권 줄 유지 / 유지)를 제시해 owner가 고르게 한다. 법적 파일은 owner 선택 없이 바꾸지 않는다.
- **DSC-30** 연구·에이전트 사용자층이 있으면 `CITATION.cff`(`cffconvert --validate`)를 두고 필요 시 Zenodo DOI를 연결한다.
- **DSC-31** 거버넌스 신호(MAINTAINERS/CODEOWNERS, 1인 유지보수라면 정직한 진술, ROADMAP, CHANGELOG)를 둔다. ADOPTERS는 실제 외부 사용자가 1명 이상일 때만, FUNDING은 owner 결정 후에만 만든다.

## 5. 레지스트리·스토어 메타데이터

- **DSC-32** 모든 생태계 고유 매니페스트는 검색 listing이다. description, keywords/classifiers/categories, homepage, repository, documentation, issues, changelog URL, license(SPDX), icon, screenshots, brand color를 채우고 각 생태계 validator를 통과시킨다. 필드·validator·확인 방법은 `references/registries.md`.
- **DSC-33** 레지스트리 식별자(Go module path, npm/PyPI/crate 이름, chart·image 경로, app id)는 저장소 URL·namespace와 맞아야 한다. 맞지 않으면 레지스트리 페이지가 404가 된다. 경로 변경은 생성 코드를 재생성하는 방식으로 하고 손으로 고치지 않으며, API group·도메인 같은 다른 식별자는 건드리지 않는다. 경로 변경 자체는 owner 결정.
- **DSC-34** 레지스트리는 **게시된 패키지**의 메타데이터를 읽는다. 메타데이터만 바뀌어도 새 릴리스가 있어야 반영된다. 동작 변경 없는 metadata-only 릴리스가 필요하면 그 이유를 적어 owner 승인(`isac-e2e-promo-readiness`)을 받는다. 버전 문자열을 올릴 때 역사적 언급은 줄별 이유와 함께 남긴다. 태그 전에 다른 세션의 동시 릴리스와 태그 충돌이 없는지 확인한다. 이미 게시된 버전은 다시 태그하지 않는다(Go는 `retract`).
- **DSC-35** MCP 서버: 공식 MCP registry의 namespace(`io.github.<owner>/<name>` 또는 도메인 검증 namespace)를 먼저 확보한다. 포크나 제3자가 같은 이름의 listing을 갖고 있을 수 있으므로 검색해 확인하고, 해결은 takedown 요청이 아니라 자기 namespace 등록 + 패키지 소유 증명(`mcp-name:` 줄, `mcpName` 필드)이다. `server.json` 버전 = 패키지 버전.
- **DSC-36** 데스크톱 앱: AppStream metainfo를 소프트웨어 센터의 SEO로 다룬다(`<icon type="stock">` = reverse-DNS app id, `<branding>` light/dark 색, 16:9 스크린샷과 caption, homepage, `vcs-browser`, `<releases>`, OARS). `appstreamcli validate --pedantic`, `desktop-file-validate`, `flatpak-builder-lint`를 통과시키고 Flathub quality guidelines까지 맞춘다. 아이콘은 hicolor 전 크기 + scalable SVG를 설치하고 창 아이콘·About 메타데이터(homepage, bug URL)와 id를 일치시킨다.
- **DSC-37** 배포 채널 페이지(COPR, AUR, OBS, PPA, Homebrew tap 등)의 설명·지침·homepage·keywords도 브랜드 표면이다. 쓰기 후에는 API가 아니라 **렌더된 페이지**를 본다: 저장된 escape(`\n` 리터럴), 꺼진 인덱싱 플래그(예: COPR `appstream`), 비어 있는 keywords는 조용한 SEO 실패다. 레지스트리 캐시(AUR RPC 등)는 늦으므로 패키지 페이지나 새 clone으로 확인한다. 빌드에 영향을 주는 source URL은 바꾸지 않는다.
- **DSC-38** [U] 배포 대상 coverage 정책을 `AGENTS.md`(또는 동등한 지침 파일)에 쓴다: EOL은 대상을 제거하는 이유가 아니다. 빌드가 깨지거나 필수 의존성 상향이 막힐 때만 은퇴시키고, 플랫폼이 강제로 제거하는 경우(EOL chroot 자동 삭제, 구버전 series 거부)는 채널별로 결정한다. 한 생태계에 채널이 겹치면(예: 빠른 한 줄 설치 채널 + 여러 배포판을 한 spec으로 커버하는 채널) 비용이 싸면 둘 다 유지한다.
- **DSC-39** [U] 새 플랫폼 버전(배포판 릴리스, 런타임 버전)이 나오면 자동으로 이슈를 여는 scheduled workflow를 둔다: 누락된 (배포판, 버전)마다 하나의 idempotent 이슈, 숨은 marker, 전용 라벨, 본문 diff 편집, 모든 채널이 빌드되면 자동 종료. 데이터는 endoflife.date 같은 공개 API에서 얻는다.
- **DSC-40** README의 지원 배포판·설치 매트릭스는 실제 채널 대상과 일치해야 한다. 릴리스 단계에서 채널 대상(chroot, series, repository 목록)과 README 표를 비교하는 검사를 둔다. 광고하는 각 배포판에서 **설치된 패키지**를 테스트한다(소스 빌드만으로 대신하지 않는다).
- **DSC-41** 게시된 의존성 범위(상한 포함)도 설치 UX다. 상위 메이저 릴리스로 새 설치가 깨지면 범위를 고쳐 릴리스하고 영향받는 버전 구간을 정직하게 문서화한다.
- **DSC-42** awesome-list·카탈로그(CNCF Landscape, OperatorHub, 공식 드라이버·구현 목록, AlternativeTo 등)는 **준비 상태만** 만든다: 요구 조건(나이, star 수, CI, 라이선스, 적합성 보고서) 충족 여부 표, 해당 목록 형식의 한 줄 항목, 필요한 로고·메타데이터. 제출·아웃리치는 마케팅 에이전트 몫이다. 조건이 성립하지 않는 목록(예: 공식 적합성 보고서가 전제인 구현 목록)은 전제가 생길 때까지 보류로 둔다.

## 6. 단일 source와 패리티 게이트

- **DSC-43** [U] code == docs == site == listings 패리티 규칙을 저장소 `AGENTS.md`에 강한 필수 섹션으로 쓴다: 코드·문서·사이트·레지스트리 listing이 다르면 실패한 테스트와 같은 결함이고, 모든 PR은 머지 전에 패리티를 검사하며 불일치는 머지를 막는다. source of truth 위치(API 스키마, 생성 reference, ADR, positioning source)를 적는다. PR template에 패리티 체크박스와 문서·사이트 빌드·체크 명령 체크박스를 넣는다. 문구 예시는 `references/repo-surface.md` §6.
- **DSC-44** [U] 에이전트 지침 배치: 저장소 공통 규칙은 `AGENTS.md`(항상 적용) + `.agents/rules/*.md`(범위 한정)에 영어로 둔다. 개인·관리자 정책(예: 관리자 머지)은 저장소가 아니라 memory에 둔다. 중복 키워드 목록은 지우고 positioning source 하나만 남긴다.
- **DSC-45** positioning source(`isac-positioning` 산출물, 기본 저장소 루트 `positioning.yml`, 기존 규약 경로가 있으면 그것)의 `category.one_liner`·`about_description`·`registry_description`, `keywords.topics`·`registry_keywords`, `identity.homepage`·`license`, 코드에서 계산한 카운트·버전을 README, About, 사이트 메타, 패키지 매니페스트, 플러그인·마켓 매니페스트로 **생성하거나 동기화**하는 스크립트를 두고, `--check` 모드를 CI에서 돌려 drift가 있으면 실패시킨다. 한 줄 정의는 모든 표면에서 같게 하고, 긴 설명은 표면 형식에 맞게 따로 쓰되 같은 문단을 복붙하지 않는다.
- **DSC-46** 기계적 게이트 범위: 버전(매니페스트 전부), 카운트(도구 수 등 코드에서 계산), 키워드·description 길이, 금지 문구(미출시 기능, 헤징, 변경 서사, checkout 설치), 링크, 브랜드 자산 참조. 사이트 빌드 시 docs sync는 `isac-project-site`가 소유하고 여기서는 그 결과를 검사 대상에 포함한다.
- **DSC-47** [U] 사용자에게 보이는 동작이 바뀌면 머지 전에 저장소의 문서·미디어·metainfo·레지스트리 문구를 옛 용어로 grep해 모두 고친다(미디어 재촬영은 `isac-demo-media`).
- **DSC-48** 큰 변경 뒤에는 현재 코드 사실 목록(F1…Fn)을 먼저 고정하고, docs·chart·landing·listing 블록 전체를 그 목록에 대해 bulk 판정한 뒤 플래그된 블록을 사람이 전부 읽는다. 기존에 있던 불일치도 고친다. 판정이 애매한 코드↔문서 차이는 버그인지 의도인지 테스트로 결론 내고, 결정이 필요하면 선택지와 권장안으로 묻는다(`isac-decision-brief`). 공개 변경에 "의도인지 확실하지 않음" 같은 헤징을 남기지 않는다.
- **DSC-49** 패키징·메타데이터 validator(DSC-36의 validator, `rpmspec` parse, `twine check`, `helm lint`, `cffconvert`, `actionlint`, 저장소 자체 docs-SEO 검사)는 브랜드·표면 PR 전에 깨끗한 컨테이너에서 돌린다.
- **DSC-50** 공개 텍스트(README, About, listing 설명, 커뮤니티 파일)는 저장소 언어 규약을 따르고 없으면 영어로 쓰며 `writing-clearly-and-concisely`와 `humanizer`를 적용한다(`isac-github-publishing` GHP-02/03). 모든 사실 주장의 근거 규칙은 `isac-positioning` 소유.

## 7. 라이브 검증과 보고

- **DSC-51** 머지·배포·릴리스 뒤 모든 외부 사본을 메모리가 아니라 live로 다시 확인한다: `gh repo view --json description,homepageUrl,repositoryTopics,openGraphImageUrl,usesCustomOpenGraphImage`, community profile, 각 레지스트리 페이지·JSON API(버전, description, 로고, 링크, 라이선스), 배포 채널 페이지. 명령 목록은 `references/repo-surface.md` §7과 `references/registries.md`.
- **DSC-52** [U] 리브랜드·팔레트·이름 변경 뒤에는 저장소만이 아니라 업로드된 사본을 가진 모든 외부 표면(social preview, 레지스트리 이미지, 스토어 listing, 릴리스 배너, 배포 채널 설명)을 다시 검증하고 교체한다.
- **DSC-53** 외부 표면 교체는 머지 후에 한다: owner 승인 → 브랜치 최신화 → 리뷰 GREEN → 머지 → 배포 → 외부 표면 교체. 로그인이 필요한 표면은 DSC-05로 넘긴다.
- **DSC-54** 보고: 표면별 표(표면, 이전 → 이후, 쓰기 방법, 검증 명령과 결과, 남은 blocked 항목과 준비된 자산). 실행하지 않은 검증은 pending으로 적는다.

## 교정 루프

결과가 기대와 다르면 사용자는 `isac-skill-correction`으로 이 스킬을 교정할 수 있다. 실행 중 사용자가 이 스킬의 동작을 교정했다면 따로 묻지 말고 최종 보고에 한 줄로 알린다. `references/cases.md`는 교정할 때만 읽는다.
