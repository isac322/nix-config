---
name: isac-e2e-promo-readiness
description: Use when preparing an open-source GitHub project end to end so it is ready to be promoted and discovered — kickoff contract, batched identity questions, parallel research and multi-stance consensus, a steering report page reachable from the owner's device, phases from positioning through brand kit, site, README, repo surface, registries and demo media, IaC apply and deploy, replacement of every external copy, a live every-surface audit and metadata release, with owner approval gates and a final report; including "브랜딩하고 사이트 만들어", "홍보 준비해", "홍보할 수 있게 준비해", "SEO 준비", "브랜딩이랑 SEO 해줘", "랜딩이랑 문서 사이트 만들어", "모든 위치에 asset 설정됐는지 확인해", "브랜드 자료 전부 교체해". Not for one area alone (isac-positioning, isac-brand-identity, isac-project-site, isac-discovery-surfaces, isac-demo-media), release notes (the release process), or any promotional writing or posting — launch posts, channel copy, press-kit text, outreach, scheduling, campaigns, analytics reporting — which a separate marketing agent owns.
---

# E2E Promo Readiness

오픈소스 GitHub 프로젝트를 "홍보하고 발견될 준비가 된 상태"로 만드는 오케스트레이터. 이 스킬은 킥오프 계약, 정체성 질문, 병렬 리서치, 토론→합의, 스티어링 리포트 페이지, 단계 순서, 오너 프리뷰·승인 게이트, 머지 후 외부 사본 교체, 최종 라이브 감사, ledger와 최종 보고를 소유한다. 영역별 작업은 이름으로 위임한다: 포지셔닝·키워드·정직성 `isac-positioning`(POS), 로고·브랜드 킷 `isac-brand-identity`(BRD), 랜딩·문서 사이트·기술 SEO `isac-project-site`(SITE), README·repo 표면·레지스트리 메타데이터·일관성 게이트 `isac-discovery-surfaces`(DSC), 스크린샷·영상 `isac-demo-media`(MED). 토론 절차는 `isac-multi-agent-consensus`, 오너에게 묻는 형식은 `isac-decision-brief`, GitHub 공개 텍스트는 `isac-github-publishing`, 모든 디자인·UI/UX는 `impeccable`(BRD·SITE 규칙 경유)이 소유한다. PR 생성·머지·파괴적 작업·검증 보고의 승인 기준은 전역 가드가 소유하고 이 스킬은 완화하지 않는다.

`[U]` = 사용자 지시·교정·승인에서 온 규칙(사용자 승인 없이 완화·삭제 불가). 태그 없음 = 바꿀 수 있는 기본값. 단계별 입력·산출물·의존성은 `references/phases.md`, 리포트 페이지 사양은 `references/report-page.md`, 도구 목록은 `references/tools.md`, 조사한 외부 스킬과 흡수한 아이디어는 `references/external-skills.md`에 있다.

## 0. 범위

- **E2R-01** [U] 소유 표면만 준비한다: 브랜드와 에셋 킷, 랜딩·문서 사이트, README, GitHub repo 설정(About·topics·social preview·homepage·커뮤니티 헬스 파일), 기술 SEO, 도메인·호스팅·분석 연결, 데모 미디어, 레지스트리·스토어 리스팅 **메타데이터**, 라이선스·상표 위생, 신뢰 신호, 일관성 게이트. 사이트·README·About·리스팅 설명처럼 표면에 들어가는 글은 범위 안이다.
- **E2R-02** [U] 홍보용 글쓰기와 게시는 범위 밖이다: 런치 포스트, 채널별 카피, 보도자료·press kit 문구, fact sheet, 채널 규칙 표, 아웃리치, 일정, 캠페인, 분석 리포팅 운영. 이런 산출물을 만들지 않고, 요청이 섞이면 "마케팅 에이전트 몫"이라고 한 줄로 분리한다. 최종 보고에는 마케팅 에이전트가 쓸 입력(positioning source, 브랜드 킷, 사이트 URL)의 경로만 적는다.
- **E2R-03** [U] 릴리스 노트는 릴리스 절차 소유다. 이 스킬은 메타데이터 릴리스가 필요하다는 판단과 오너 승인까지만 다룬다(E2R-44).

## 1. 킥오프 계약

- **E2R-04** [U] 시작할 때 한 번에 계약을 고정한다: 대상 표면 목록, 순서(병렬 리서치 → 교차 검증 → 토론 → 목표·지표 → 작업 추출 → 리포트 페이지 → 오너 steering → 산출물별 owner 에이전트), 리포트가 승인 대기 중이어도 작업은 병렬로 계속된다는 점, 공개 글의 글쓰기 스킬(`writing-clearly-and-concisely`, `humanizer`) 의무, 제품 컨셉·방향처럼 모르는 것은 추측하지 않고 묻는다는 점. 계약은 ledger 머리(`references/phases.md` §Ledger)에 적는다.
- **E2R-05** [U] 사용자에게 보이는 모든 콘텐츠(카피, IA, 컨셉, 시각 방향)는 한 작성자가 아니라 여러 에이전트가 토론해 합의한 방향으로 정한다(`isac-multi-agent-consensus`). 합의가 오너의 명시 요구를 이기지 못한다.
- **E2R-06** [U] 오너가 모르는 표면까지 찾는다. 이미 있는 곳만 갱신하지 않고, 저장소·레지스트리·스토어·패키지 매니페스트·사이트 head를 훑어 에셋과 메타데이터가 들어가야 할 모든 위치를 표로 만든다(DSC의 표면 지도 + 고정 rubric 일괄 분류). 위치마다 어떤 이미지·문구가 맞는지도 정한다.

## 2. 정체성 질문

- **E2R-07** [U] 리서치 결과가 나오기 전에, 정체성 질문을 한 번에 묶어 묻는다(`isac-decision-brief` DBR-12): 브랜드 이름과 repo·패키지 이름의 관계, 도메인·서브도메인, 주 청중과 우선순위, 공개 언어, 사이트 호스팅과 소스 위치(같은 repo `site/` + Pages 또는 별도), 고정된 브랜드 요소와 확장 가능한 요소, 기존(레거시) 페이지 처리, 배포·머지 범위, 외부 설정을 누가 어떤 경로(IaC, 브라우저)로 적용하는지, 비용 한도, 오너가 실제로 쓰고 있는지(성숙도 표현의 근거). 질문 템플릿은 `references/phases.md` §Intake.
- **E2R-08** [U] 브리프와 저장소가 모순되면(도메인 오타, 다른 프로젝트 이름, 이미 존재하는 설정) 추측하지 않고 묻는다. 답은 binding이며, 실행 중인 모든 scout·owner 에이전트에 즉시 전파한다(MAC-07).
- **E2R-09** [U] 사이트 스택 기본값은 Astro + Starlight + Bun(node/npm/npx 없음)이다. 묻지 않고 계약에 적는다. 오너가 다른 스택을 지시할 때만 바꾼다.
- **E2R-10** 저장소·도구·라이브 조회로 답할 수 있는 것(현재 About·topics·homepage, 레지스트리 등록 여부, 라이선스 감지 결과, DNS)은 묻지 않고 확인해 질문의 전제로 넣는다.

## 3. 리서치와 합의

- **E2R-11** [U] 리서치는 병렬 wave로 돌린다. 1차 wave는 서로 다른 고정 관점의 scout를 동시에 띄운다: repo 공개 표면 감사(모든 주장을 코드와 대조), 경쟁자·선례 랜딩, 검색 수요·키워드, 기술 SEO·플랫폼, 포지셔닝·브랜드 기준선, 문서 IA, 외부 표면 지도와 자격증명 감사(읽기 전용, 값 비노출), 이름·도메인·레지스트리 namespace clearance. 2차 wave는 1차가 드러낸 빈 곳만 좁혀 조사한다. 관점별 owner 스킬은 `references/phases.md` §Research.
- **E2R-12** 수백 개 이상의 동질 항목(문서 섹션, 파일 역할, 문장)은 rubric을 먼저 고정하고 judge로 일괄 분류한 뒤 flag만 사람(오케스트레이터)이 읽는다. rubric은 데이터를 보기 전에 고정한다.
- **E2R-13** 토론은 고정 입장 4개(예: 성장, 브랜드, 정확성, 유지보수 비용)로 2라운드 한다. 1라운드 주장은 코드·URL로 Confirmed/Refuted/Unverifiable 판정하고, 2라운드는 상호 반박이다. 절차 세부는 `isac-multi-agent-consensus`.
- **E2R-14** 합의 문서(`consensus.md`, 오너 언어) 하나로 모은다: 진단 → 포지셔닝 → 측정 가능한 목표 → 컨셉 → 시각 방향 → IA → owner가 붙은 작업 목록(P0–P2) → 오너 질문. 형식은 `references/phases.md` §Consensus.
- **E2R-15** [U] 목표 지표마다 조회 가능한 API 출처와 현재 baseline을 적는다(baseline → target, 출처). API로 측정할 수 없는 값은 north-star가 될 수 없다. 아무도 읽지 않을 수집 인프라(주간 아카이브 워크플로 등)는 목적을 설명하고 오너가 원할 때만 만든다. 지표의 정기 리포팅 운영은 마케팅 몫이다(E2R-02).
- **E2R-16** [U] 오너가 방향을 교정하면 결과를 revision brief(`revision-brief-N.md`)로 쓰고, 영향받는 모든 owner 에이전트에 전달한다. 새 주장은 코드로 검증하는 amend 패널을 거친 뒤 brief에 넣는다. 에이전트가 스스로 붙인 제약(금지 모티프 등)은 오너 입력보다 오래 살아남지 않는다. 오너 요구와 부딪치면 brief에서 지운다.

## 4. 스티어링 리포트와 병렬 실행

- **E2R-17** [U] 합의가 나오면 리포트 웹 페이지를 게시하고, 같은 시점에 모든 실행 owner를 시작한다. 승인을 기다리며 멈추지 않는다. 오너가 steering하면 진행 중인 작업을 brief로 고친다.
- **E2R-18** [U] 리포트·프리뷰·비교 페이지는 오너의 기기에서 열리는 URL로 준다(LAN·VPN 주소, 오너가 접근 가능한 호스트). `/tmp/...` 같은 서버 로컬 파일 경로나 에이전트 쪽 브라우저에서만 열리는 주소를 주지 않는다. 주기 전에 그 주소로 200과 렌더링(데스크톱·모바일 폭)을 확인한다. 사양은 `references/report-page.md`.
- **E2R-19** 리포트에는 목표·지표·방향 요약, 진단, 작업 목록과 status, 오너 질문, steering 라운드별 반영 절, 디자인 라운드별 비교 페이지가 있다. 라운드마다 갱신하고, 모든 승인 질문에 리포트 URL을 넣는다. 오래된 리포트는 결함이다.
- **E2R-20** [U] 영역마다 owner 에이전트를 하나씩 두고(로고, 사이트, README, repo 표면, 레지스트리, 미디어) 실제 의존성이 없는 것은 병렬로 돌린다(MAC-03). 공유 계약(토큰, 브랜드 경로, 카피 모듈, nav 데이터)과 파일 소유권을 먼저 정해 병렬 작업이 어긋나지 않게 한다.

## 5. 단계 순서

- **E2R-21** 순서와 의존성: 포지셔닝(POS) → 브랜드 아이덴티티(BRD) → 브랜드 킷(BRD, 기본 `assets/brand/`) → 사이트(SITE) · README와 repo 표면과 레지스트리 메타데이터(DSC) · 데모 미디어(MED) 병렬 → 게이트 → 오너 리뷰와 머지 → IaC apply와 배포 → 머지 후 모든 외부 사본 교체 → 라이브 "모든 표면 제자리?" 감사 → 레지스트리 갱신용 메타데이터 릴리스. 각 단계의 입력·산출물·게이트는 `references/phases.md` §Phases.
- **E2R-22** 병렬 단계 안에서도 선행 조건을 지킨다: README 헤더·social preview·favicon은 브랜드 킷 뒤, 레지스트리 설명은 positioning source 뒤, 미디어는 최신 main과 배경 승인 뒤(MED), 사이트 디자인은 선택된 브랜드 방향 뒤. 선행이 늦으면 그 조건과 무관한 부분(IA, 문서 동기화, 기술 SEO 배선)을 먼저 진행한다.
- **E2R-23** [U] 레포 공개 경로의 정체성 식별자(모듈 경로, 패키지 이름, 차트 이름)와 repo URL이 어긋나면 브랜드 작업 전에 고친다. 고칠 때는 생성 코드를 재생성하고, API group·도메인 식별자는 오너 결정 없이 건드리지 않는다(DSC 규칙).
- **E2R-24** 게이트 단계는 모든 영역 산출물에 적용한다: 일관성 게이트(DSC), impeccable critique·audit·detector와 겹침 스캔(SITE·BRD), 사실·문체 패널과 prose judge, 설치 계약의 clean 환경 verbatim 실행(DSC), 레디니스 lint, 공개 repo 위생을 포함한 코드 리뷰. 모두 GREEN이어야 오너 리뷰로 간다.

## 6. 오너 프리뷰·승인 게이트

- **E2R-25** [U] 시각·브랜드·카피 결정은 텍스트 요약이나 에이전트 점수가 아니라 실제 렌더링된 결과물로 오너에게 보인다. 적용 전에 비교 가능한 프리뷰 페이지를 만든다.
- **E2R-26** [U] 반복할 때 이전 변형(variant)을 지우지 않는다. 변형마다 고정 URL을 두고 인덱스 페이지에서 나란히 비교하게 해서 되돌릴 수 있게 한다.
- **E2R-27** [U] 머지 승인 요청은 정보를 갖춘다: 변경 요약(무엇이 왜 바뀌었는지), diff·PR 링크, 라이브 프리뷰 URL, 검증 결과, 남은 결정. 보여 주지 않고 머지를 묻지 않는다. 브랜드·사이트 작업의 머지는 오너가 승인했을 때만 한다. 각 PR이 무엇을 담는지 한 줄씩 적는다.
- **E2R-28** [U] 큰 변경(구조 개편, 코드 수정이 필요한 코드↔문서 불일치 해결, 대규모 재작성)은 하기 전에 크기(파일·줄 수, 영향 표면, 소요 시간)를 보고하고 선택지로 묻는다. 불일치는 항목별 선택지와 권장안으로 올린다.
- **E2R-29** [U] 공개 변경에 애매한 발견("의도한 동작인지 확실하지 않음")을 남기지 않는다. 테스트·코드로 버그인지 의도인지 정한 뒤, 버그면 고쳐서 같은 PR에 넣고 아니면 그대로 진행한다.
- **E2R-30** [U] 디자인이 계속 이전 작업을 닮아 가면(anti-reference로 둬도 수렴하면) 백지에서 다시 만든다: 오너가 한 말만 담은 요구사항 파일을 쓰고, 새 디자이너 에이전트에게 이전 사이트·git 이력·리포트·scratch 디렉터리 접근을 금지한다. 문서 본문은 그대로 두고 표현만 새로 만든다. 두 개 이상의 독립 재구성을 비교 페이지로 보인다.
- **E2R-31** [U] 오너의 스타일 선호(스타일 계열, 문자 그대로의 상징을 원하는지)는 시안을 그리기 전에 묻는다(BRD). 디자인 스킬 절차 중 건너뛴 단계가 있으면 밝힌다.

## 7. 작업 방식

- **E2R-32** [U] 에이전트가 자기 도구로 할 수 있는 일을 오너에게 넘기지 않는다: 브라우저 자동화로 가능한 설정 변경, 기존 토큰에 권한 추가(재발급 없이, 범위는 IaC 변수 설명에 기록), 업로드, API 호출. 로그인은 비밀번호 인증 경로를 쓰고 모바일 2FA를 전제하지 않는다. 시크릿 값 요청·저장은 `isac-decision-brief` §4.
- **E2R-33** 로그인 벽이 있는 표면(스토어, 레지스트리 콘솔)은 읽기 전용 세션 확인부터 한다. 자격증명을 추측하지 않는다. 막히면 에셋과 문구를 준비해 둔 채 "blocked" 목록에 올리고, 통제 브라우저에서 로그인 페이지를 열어 오너에게 넘긴 뒤, 변경은 서비스 API로 다시 읽어 확인한다.
- **E2R-34** [U] 오너가 repo·DNS·Pages 설정을 IaC로 관리하면 그 설정은 IaC로만 바꾼다(UI 클릭 금지). IaC가 없는 설정만 API·브라우저로 적용하고 URL과 before/after로 보고한다. 코드 변경은 PR로 하고, 그 외 설정은 직접 적용한 뒤 무엇을 어디서 바꿨는지 URL과 함께 보고한다.
- **E2R-35** [U] 긴 작업과 실험은 시간 상한(기본 15–20분)을 두고 단계별 시간을 잰다. 실패하면 변형을 계속 바꿔 재시도하지 않고 멈춰서 측정값과 함께 보고한다. 최적화는 재촬영·재빌드 전에 먼저 한다(MED).
- **E2R-36** [U] 진행 상황을 투명하게 알린다: 오너가 물으면 현재 단계, 경과 시간, 남은 단계, 막힌 이유를 수치로 답한다. "기다리는 중" 같은 거의 같은 보고를 반복하지 않는다. 대기 중에는 독립 작업을 계속하고, 할 일이 없으면 남은 결정을 한 번에 묶은 decision brief 하나로 턴을 끝낸다.
- **E2R-37** [U] 다른 세션이 같은 코드를 고치고 있을 수 있는 앱 버그는 직접 고치지 않고 이슈로만 남긴다(`isac-github-publishing`, 재현 절차와 pinned SHA 포함).
- **E2R-38** [U] 공개 repo 위생: 리뷰 스크린샷, 로컬 덤프, `/tmp` 경로, 세션 산출물, 리포트·ledger, 마케팅 상태, 시크릿을 커밋하지 않는다. scratch는 repo 밖에 두고, 도구가 repo 안에 만드는 리뷰 산출물은 `.gitignore`에 넣는다. 코드 리뷰가 위생 위반을 BLOCKING으로 판정하면 GREEN까지 머지하지 않는다.
- **E2R-39** 사용자의 새 규칙·교정은 실행 중인 owner에 즉시 전파하고 ledger의 결정 로그에 원문과 함께 남긴다.

## 8. 마감

- **E2R-40** [U] 머지 후 모든 외부 사본을 교체한다: GitHub social preview, homepage URL, About, 레지스트리·스토어 아이콘과 설명, 패키지 메타데이터, 최신 릴리스의 배너, 커뮤니티 프로필. repo 호스팅 에셋 URL(`raw.githubusercontent.com/.../main/...`)은 머지 뒤에야 해석되므로 이 교체는 머지 후 체크리스트다. 리브랜드·재색상 뒤에는 repo만이 아니라 업로드된 사본을 가진 모든 외부 표면을 다시 확인한다.
- **E2R-41** 배포 순서는 IaC(DNS, 도메인 검증, Pages, repo 설정) → 도메인 검증 → 사이트 배포 → HTTPS 강제 → sitemap 제출 → 모든 SEO 파일 라이브 smoke다(SITE 세부). IaC apply는 전역 가드와 IaC 저장소의 승인 절차를 따른다.
- **E2R-42** [U] "다 됐다"고 말하기 전에 기억이 아니라 라이브로 모든 표면을 다시 조회한다: 페이지별 head 태그(title, description, canonical, og:image, twitter:card, JSON-LD, manifest, icons), manifest와 아이콘 200, repo 메타데이터와 custom OG, 각 레지스트리·스토어 페이지, README 렌더링. 표면 × 기대값 × 관측값 × 증거 URL 표로 남긴다. 체크리스트는 `references/phases.md` §Live audit.
- **E2R-43** 감사에서 빈 곳이 나오면 소유 스킬로 되돌려 고치고, 고친 뒤 같은 조회를 다시 한다. 리포트 페이지도 최종 상태로 갱신한다.
- **E2R-44** [U] 레지스트리가 새 버전에서만 메타데이터를 다시 읽으면(차트·패키지 인덱스 등) 동작 변화 없는 메타데이터 릴리스가 필요하다고 말하고 오너에게 묻는다. 승인되면 버전 문자열을 전부 grep해 올리고, 남기는 과거 버전 언급은 줄마다 이유를 적는다. 재릴리스 직전에 다른 세션의 태그·릴리스와 경합하지 않는지 확인한다. 릴리스 노트 작성은 릴리스 절차 몫이다.
- **E2R-45** ledger(`references/phases.md` §Ledger)는 repo 밖에 두고 단계마다 갱신한다: 계약, 결정 로그(`[U]` 원문 포함), 작업 목록과 owner·status·증거, 외부 표면 표, blocked 목록, 승인 기록.
- **E2R-46** 최종 보고(한국어)는 결론 먼저: 모든 표면의 라이브 상태 표, 머지한 PR과 적용한 외부 설정(URL), blocked 항목과 오너가 할 정확한 절차, 기록된 오너 결정, 남은 위험, 마케팅 에이전트용 입력 경로(E2R-02). 실행하지 않은 검증은 통과로 쓰지 않는다(전역 `verification`). 템플릿은 `references/phases.md` §Final report.
- **E2R-47** 오너가 보인 지속 선호(디자인 스킬 의무, 요구사항만으로 재구성, 설정은 IaC, star 수 표시 기준 등)는 다음 프로젝트가 거기서 시작하도록 memory에 남긴다. 프로젝트별 값은 스킬에 굽지 않는다.

## 교정 루프

결과가 기대와 다르면 사용자는 `isac-skill-correction`으로 이 스킬을 교정할 수 있다. 실행 중 사용자가 이 스킬의 동작을 교정했다면 따로 묻지 말고 최종 보고에 한 줄로 안내한다. `references/cases.md`는 교정할 때만 읽는다.
