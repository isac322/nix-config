---
name: isac-positioning
description: Use when preparing an open-source GitHub project's positioning before any site, README, brand, or listing work — repo content audit, competitor and precedent-landing research, search-intent and keyword map, visitor model, category premise vs selling points with file:line evidence, anti-claims and never-say list, per-surface maturity framing, trademark-referential phrasing, and the single positioning source file every other surface reads; including "포지셔닝 잡아", "셀링포인트 정리해", "경쟁 프로젝트 조사해", "검색 키워드 조사해", "누가 들어오는지 정리해", "과장 문구 걸러", "positioning.yml 만들어", "홍보 준비 리서치". Not for orchestration and approval gates (isac-e2e-promo-readiness), name/logo/brand kit (isac-brand-identity), landing/docs site build and page copy (isac-project-site), README/repo settings/registry metadata/consistency gate (isac-discovery-surfaces), screenshots and recordings (isac-demo-media), or any promotional writing or posting — launch posts, channel copy, press kits, outreach (a separate marketing agent).
---

# Positioning

오픈소스 프로젝트를 홍보·발견 가능한 상태로 준비할 때 **무엇을, 누구에게, 어떤 근거로 말하는가**를 정한다. 이 스킬은 리서치(저장소 감사, 경쟁·선례 조사, 검색 의도, 방문자 모델)와 그 결론을 담는 **단일 포지셔닝 소스 파일**을 소유한다. 그 파일은 모든 형제 스킬의 입력이다: `isac-brand-identity`(BRD), `isac-project-site`(SITE), `isac-discovery-surfaces`(DSC), `isac-demo-media`(MED). 전체 순서·오너 승인 게이트·보고 페이지는 `isac-e2e-promo-readiness`(E2R)가 소유한다. 이 스킬은 표면(사이트·README·매니페스트)을 직접 쓰지 않고, 표면 문구의 재료와 금지선만 만든다. 홍보 글·채널 문구·보도자료·팩트시트·게시는 범위 밖이다(별도 마케팅 에이전트).

위임: 사용자 질문은 `isac-decision-brief`, 토론·합의는 `isac-multi-agent-consensus`, 대량 분류는 eval의 `judge_batch`(jevify), 공개 텍스트 문체는 `writing-clearly-and-concisely`·`humanizer`, 공개 텍스트 언어·sanitize는 `isac-github-publishing`, 디자인·UI/UX는 `impeccable`(BRD·SITE 경유). 이 스킬이 소유하는 교차 규칙: **정직**(주장은 `file:line`을 인용하고 개수는 셀링포인트가 아니라 증거다, POS-19~POS-24). 다른 스킬은 이 ID로 참조한다.

`[U]` = 사용자 지시·교정·승인에서 온 규칙(사용자 승인 없이 완화·삭제 불가). 태그 없음 = 바꿀 수 있는 기본값. 파일 스키마와 템플릿은 `references/positioning-source.md`, 조사 방법·명령·루브릭은 `references/research.md`에 있다.

## 순서

1. 정체성 질문 일괄(POS-01~03) → 2. 병렬 리서치: 저장소 감사(POS-04~07) · 경쟁·선례(POS-08~11) · 검색 의도(POS-12~15) → 3. 방문자 모델(POS-16~18) → 4. 카테고리 전제·셀링포인트 토론(POS-19~24) → 5. 안티클레임·비교·성숙도·상표(POS-25~33) → 6. 포지셔닝 소스 파일 작성·진실 검토·오너 승인(POS-34~40) → 7. 형제 스킬에 전달. 리서치 산출물은 세션 작업 디렉터리(`local://` 등)에 두고, 저장소에는 소스 파일과 impeccable용 `PRODUCT.md`만 커밋한다.

## 1. 정체성·목적 질문

- **POS-01** [U] 정체성·목적 수준의 선택은 에이전트가 정하지 않고 오너에게 묻는다. 리서치가 결론을 내기 **전에** `isac-decision-brief`로 한 번에 묶어 묻는다: 제품 이름과 도메인·서브도메인(브리프와 저장소가 다르면 추측하지 않는다), 이름 충돌 시 한정어, 1차·2차 대상 독자와 우선순위, 공개 언어(i18n 여부), 사이트 호스팅·소스 위치, repo 소유 주체(개인 계정 vs 조직), 목표(사용자·기여자·후원 중 무엇), 브랜드 중 고정할 부분과 확장 가능한 부분, 기존(레거시) 페이지 처리, 실제 운영 사용 여부(POS-29 입력). 각 질문에 자유 입력 여지를 남긴다.
- **POS-02** [U] 답은 구속력이 있다. 받은 답은 즉시 진행 중인 모든 리서치 에이전트에 전파(`agent://all`)하고 소스 파일 `identity`·`audience`에 기록한다.
- **POS-03** [U] 오너가 말한 제품의 의미(무엇이 장점인지, 무엇을 강조할지)가 포지셔닝의 전제다. 에이전트가 스스로 만든 제약·금지(예: "이름을 글자 그대로 형상화하지 않는다")는 오너 입력보다 오래 살아남지 않는다. 충돌하면 오너 쪽으로 브리프를 고친다.

## 2. 저장소 콘텐츠 감사

- **POS-04** 새 문구를 쓰기 전에 모든 공개 표면을 출시된 코드와 대조한다: README, GitHub About·topics·homepage·social preview, 패키지·차트·앱 매니페스트, 레지스트리 페이지, 문서, 기존 사이트. 주장마다 `surface | claim | code evidence (file:line) | verdict(true/stale/unshipped/unverifiable)` 행을 남긴다. 메타데이터(topics, social card, 설명)가 미출시 기능을 광고하는 것이 가장 큰 신뢰 위험이다. 깨진 링크·잘못된 설치 경로·레지스트리 404도 같이 기록한다.
- **POS-05** [U] 이미 있는 자리만 갱신하지 않는다. `git ls-files` 전체를 동결 루브릭으로 분류해 브랜딩·SEO를 위해 손봐야 할 곳을 오너가 모르던 곳까지 찾는다(역할: `must_change`/`should_review`/`irrelevant`, 두 번째 축: 필요한 자산 종류). 자산 종류 판정 결과는 BRD·MED에 넘긴다. 전형적 적중: README, About 대화상자, `.desktop`/AppStream metainfo, 패키징 spec, `pyproject.toml`·`package.json`·`Cargo.toml`·`go.mod`·`Chart.yaml` 메타데이터, docs index.
- **POS-06** 동질 항목이 약 20개를 넘으면(파일, 문서 섹션, 문단, 경쟁 페이지) 루브릭을 **데이터를 읽기 전에** 동결하고 `judge_batch`로 일괄 분류한 뒤 플래그만 사람이(오케스트레이터가) 전부 읽는다. 에스컬레이션 기본값: 기본 라벨이 아님, 최상위 확률 < 0.7, 오류. 오탐은 이유와 함께 판정 기록에 남긴다. 판정 결과는 힌트이며 주장 확정은 코드 대조로 한다. 루브릭 템플릿은 `references/research.md` §1.
- **POS-07** [U] 첫 공개 릴리스를 앞둔 프로젝트는 문서·랜딩 문자열을 추가 클래스로 감사한다: 변경 서사(“이전에는 X였다”, 마이그레이션 이야기), 소스 checkout 기반 설치(배포된 아티팩트가 있는데 `git clone`으로 설치를 설명함), 버전 고정 절차, 내부 전용 문서(PRD·E2E 케이스·감사 기록). 수정은 SITE·DSC가 하고, 이 스킬은 목록과 근거를 넘긴다.

## 3. 경쟁·선례 조사

- **POS-08** 비교 대상 5~10개(같은 문제를 푸는 도구, 플랫폼 기본 도구, DIY 기준선)를 표로 만든다: 저장소, stars(`gh api`), 라이선스, 히어로 문장 원문, 1차 CTA, 문서 스택, 성숙도 신호, 아키텍처·데이터 경로 요지, 스크린샷, `checkedOn`(URL과 날짜). 여기서 “우리가 신뢰할 수 있게 차지할 수 있는 빈자리”와 카테고리 **상투 목록**(문구와 시각 둘 다, 예: "cloud-native ... run anywhere", 어두운 배경에 빛나는 아이소메트릭 큐브)을 도출한다.
- **POS-09** 선례 랜딩 7~12개를 카테고리 안팎에서 고른다(같은 카테고리의 대표, 작은 프로젝트의 인상적인 랜딩, 인접 카테고리). 각각 기록: 한 가지 시그니처 아이디어, 히어로 단어 수, 첫 화면의 코드·데모 유무, 설치까지의 클릭 수, 문서 IA 첫 탭. 디자인 판단은 하지 않고 SITE·BRD의 impeccable 입력으로 넘긴다.
- **POS-10** 카테고리 관례(대부분이 쓰는 색·모티프·문구·구조)를 “기본값”으로 명시해 기록한다. 디자인이 그 기본값과 그 정반대를 둘 다 피할 수 있게 하는 입력이다.
- **POS-11** [U] 브랜드와 사이트를 떠받칠 시그니처 동작이나 기능(데모의 주인공)이 있으면 구현·촬영 전에 레퍼런스 자료집을 만든다: 원 구현·특허·데모를 찾아 인용하고 동작을 분석한다. 오너가 “다른 프로젝트는 보통 어떻게 해?”라고 물으면 선례를 조사해 제시한다(DBR-11).

## 4. 검색 의도 지도

- **POS-12** 유료 키워드 도구 없이 무료 수요 신호를 쓴다: GitHub topic·검색 개수(`gh api search/repositories -f q='topic:<t>' --jq .total_count`), 검색 자동완성, HN Algolia·Reddit·Stack Exchange 검색 결과와 점수, 경쟁 저장소 이슈·토론에서 실무자가 쓴 고통 표현, 레지스트리 내부 검색, 동의어 선택용 Google Trends. 추정치는 추정이라고 적고 가짜 검색량을 만들지 않는다. 명령은 `references/research.md` §3.
- **POS-13** 질의를 인지 단계로 묶는다: 문제 인지(“<증상> <환경>”), 해결 인지(“<카테고리> for <플랫폼>”, “<기본 도구> alternative”), 제품 인지(이름, 이름 + install/config/error), 평가(“X vs Y”). 클러스터마다 **정규 페이지 하나**를 지정하고, 그 페이지의 title·meta description·H1은 그 클러스터의 실제 문구를 쓴다. 두 페이지가 한 클러스터를 겨냥하지 않는다.
- **POS-14** 키워드는 계층(`primary` 카테고리어, `secondary`, `long_tail`)과 표면별 후보(GitHub topics 후보와 각 topic 모집단, 레지스트리 keywords)로 소스 파일 한 곳에만 둔다. 에이전트 지침(AGENTS.md, CLAUDE.md, rules)에 키워드 목록을 복제하지 않고 파일을 가리킨다. topic 선택·개수 한도·레지스트리별 한도 적용은 DSC가 한다.
- **POS-15** 서치 콘솔 쿼리 데이터가 생기면(SITE가 연결) 의도 지도를 실제 노출 쿼리로 갱신한다. 노출은 높고 클릭률이 낮은 페이지는 title·description 후보로 표시한다.

## 5. 방문자 모델

- **POS-16** 유입 경로별 방문자 모델을 쓴다: 누가(역할·환경), 어디서(검색 질의 클러스터, GitHub README, 레지스트리 목록, 포럼 링크, 문서 딥링크), 무엇을 이미 아는지, **60초 안에 답해야 할 질문 3개**(보통: 이게 뭔가 / 내 환경에 맞나 / 어떻게 바로 써 보나)와 1차 행동. 예: CLI는 터미널 사용자가 설치 한 줄과 출력 예시를, K8s 오퍼레이터는 플랫폼 엔지니어가 지원 버전·권한 범위·Helm 설치를, 데스크톱 앱은 배포판·데스크톱 환경 지원과 스크린샷을, MCP 서버는 에이전트 사용자가 지원 클라이언트와 설정 스니펫을 찾는다.
- **POS-17** 사용자 0명인 프로젝트는 시연이 사회적 증거다. 이 프로젝트만 보여 줄 수 있는 시연을 방문자 질문에 연결해 지정하고 MED에 넘긴다. 청구 가능 증거와 청구 금지 증거를 가르는 증거 목록(proof inventory)을 함께 둔다.
- **POS-18** [U] 오너가 표면별 1순위를 말하면(예: “첫 페이지는 브랜딩이 가장 중요하다”) 방문자 모델의 표면 목표로 그대로 기록해 SITE·BRD에 넘긴다.

## 6. 카테고리 전제와 셀링포인트

- **POS-19** 카테고리 전제(primary promise) 한 문장을 정한다: 프로젝트를 카테고리에 놓는 말(예: “<플랫폼>용 <표준 API> 구현”, “<데스크톱 환경>용 <앱 종류>”). tagline·title·meta·About·레지스트리 설명의 뿌리가 되며 번호 붙은 셀링포인트로 세지 않는다.
- **POS-20** [U] 셀링포인트는 `isac-multi-agent-consensus`로 토론해 합의한다. 기본 렌즈 3개(고통·JTBD, 경쟁 위치, 검색 의도) → 표적 교차 반박 → 중립 중재자의 구속력 있는 계획. 결과는 3~5개.
- **POS-21** [U] 셀링포인트 하나 = **headline**(≤8단어) + **benefit** 한 줄(엔지니어가 갈아탈 이유) + **mechanism**(어떻게 가능한지) + **evidence**(고정 커밋의 `file:line`) + **proof page**(주장을 입증하는 사이트·문서 경로). 증거 없는 항목은 셀링포인트가 될 수 없다.
- **POS-22** [U] 개수(CRD 수, 도구 수, 테스트 통과 수, 지원 항목 수)는 셀링포인트가 아니라 증거다. 히어로·헤드라인에 두지 않고 proof page에만 두며, 정규 값은 소스 파일 `evidence.counts`에 하나만 둔다(DSC 게이트가 표면과 코드를 대조). 산문에는 변동하는 개수 대신 “모든 …” 같은 불변 표현을 쓴다.
- **POS-23** [U] 기능을 있는 그대로 나열하면 장점이 흐려진다. 오너가 말한 결과(예: 여러 도구를 설치하는 대신 하나로 끝남, 사전 설치·설정 최소화, 설정 방식 통일)를 먼저 세우고 기능 목록은 그 증거로 쓴다. 결과 문장도 POS-21 증거 규칙을 따른다.
- **POS-24** 검증 주장은 범위를 정확히 쓴다(로컬 실행 vs 공식 제출, 시뮬레이션 vs 실제 인프라, 어떤 기능을 끈 채였는지). “conformant”, “certified”, “official”은 해당 기관 목록에 실린 뒤에만 쓴다. 코드와 문서가 엇갈리는 사실은 해소될 때까지 문구에서 뺀다. [U] 하드웨어는 모델명 대신 요구사항만 쓴다.

## 7. 안티클레임·비교

- **POS-25** 안티클레임 표를 쓴다: `never_say | because | evidence`. 기본 범주: 절대 표현(only, first, fastest, zero-config), 인증·적합성, 보증·제휴 암시, 성숙도 과장, 범위 과장(“X 전부를 관리”), 오래된 개수, 미출시 기능, 경쟁 제품 비하, POS-08 상투 목록. 모든 표면 작성자(SITE·DSC)가 이 표로 초안을 걸러낸다.
- **POS-26** [U] 주 표면(히어로, 랜딩, README 상단, About, social card)의 비교는 **기본 기준선**(플랫폼 기본 도구나 DIY 조합)의 문서화된 한계와만 하고, 그 문서를 인용한다. 이름을 건 경쟁 제품 공격 표를 주 표면에 두지 않는다. 경쟁 사실은 날짜가 찍힌 리서치 기록에 둔다.
- **POS-27** 그 대안에 대한 검색 의도가 실제로 있으면(POS-13) 별도 비교·대안 페이지를 둘지 오너에게 묻는다. 만들면 한 비교당 한 페이지, title·H1은 정확한 질의, 상대가 이기는 지점을 정직하게 적고 `checkedOn`을 표시한다. 페이지 구조와 SEO 배선은 SITE가 한다. 선행 프로젝트와의 관계는 사실대로 쓴다(포크가 아니면 fork·clone·replacement라 부르지 않고 “inspired by”, “spiritual successor” 같은 정확한 표현을 오너 승인으로 정한다).
- **POS-28** 비교 대상의 실제 토론 스레드·이슈에서 예상 반론(왜 기본 도구+설정이 아닌가, 락인, 보안, 단일 복제본, 유지보수 인력, AI 작성 여부 등)을 모으고 저장소 증거로 짧게 답해 `objections`에 둔다. SITE의 FAQ 페이지 재료이며 홍보 답글 초안이 아니다.

## 8. 성숙도 표현

- **POS-29** [U] 사이트와 README는 실제로 출시되어 쓰이는 것만 말한다. 오너가 실제로 운영에 쓰고 있으면 “experimental”, “preliminary”, “not production …”, 버전 뒤 경고 배지 같은 얼버무림 문구를 넣지 않는다. 반대로 production-grade, HA, battle-tested 같은 과장도 넣지 않는다. 표면별 표현을 `maturity`에 기록하고, 확인이 안 되면 POS-01로 묻는다.
- **POS-30** [U] 미구현 기능은 “planned”로 명확히 표시해 지원 매트릭스·로드맵에 보이게 둔다. 숨기지도 출시된 것처럼 쓰지도 않으며, title·meta·topics·H1·About·social card·레지스트리 keywords에는 넣지 않는다.
- **POS-31** 외부 채널용 상태 문구는 마케팅 에이전트 몫이다. 이 스킬은 그 판단에 필요한 사실(누가 언제부터 어디에 쓰는지, API 버전 단계)만 소스 파일에 둔다.

## 9. 제3자 상표

- **POS-32** 포지셔닝이 다른 회사·재단의 플랫폼·제품 이름을 쓰면 그 상표 가이드라인을 가져와 표시별 규칙을 `third_party_marks`에 적는다: 지시적 표현만(“<Project> for <Mark>”), 가이드라인이 요구하면 첫 **렌더링된** 사용에 ™/®, 소유격·동사화 금지, 그 로고·고유색 사용 금지, meta keywords에는 넣지 않고 설명의 지시적 문장 하나까지만, 모든 페이지 푸터의 비제휴 문구 원문. 렌더링은 SITE, 자체 이름의 상표 확인은 BRD.
- **POS-33** 보증·소속을 암시하지 않는다(“<재단> 프로젝트”, “official”, “endorsed”, 그 조직 로고 옆 배치). 해당 조직이 실제로 받아들인 경우에만 쓴다.

## 10. 단일 포지셔닝 소스 파일

- **POS-34** 결론은 기계가 읽는 파일 하나에 둔다. 기본 경로는 저장소 루트 `positioning.yml`이며, 저장소에 이미 규약(예: `.claude/positioning.yml`)이 있으면 그것을 쓴다. 스키마: `references/positioning-source.md`. tagline, 카테고리 전제, About·레지스트리 설명, 셀링포인트, 증거·개수, 안티클레임, 성숙도, planned, 기준선, 키워드, 의도 지도, 제3자 상표, 반론이 여기 있고 BRD가 `brand` 블록을 채운다.
- **POS-35** 사이트·README·About·매니페스트·레지스트리 설명은 이 파일에서 생성하거나 이 파일과 대조된다(대조 게이트와 CI 검사는 DSC 소유). 표면 작성자는 파일에 없는 주장을 추가하지 않는다. 새 주장이 필요하면 증거와 함께 파일에 먼저 넣는다.
- **POS-36** impeccable용 `PRODUCT.md`는 이 파일에서 파생한 서술(대상, JTBD, 원칙, 톤, 브랜드 약속, 금지 주장 요약)이다. 위치는 `impeccable context`가 가리키는 곳이고, 없으면 사이트 루트나 저장소 루트다. 사실·키워드·개수를 복제하지 않고 소스 파일을 가리킨다.
- **POS-37** 증거는 커밋 SHA에 고정한다(`meta.pinned_commit`). 코드가 바뀌면 영향받는 `file:line`을 다시 확인하고 `meta.version`을 올린다. 오래된 제품 문서는 옛 주장을 다시 주입하므로, 각 단계 게이트마다 소스 파일과 PRODUCT.md를 코드와 재대조한다.
- **POS-38** 작성자가 아닌 독립 검토자가 파일을 진실 렌즈로 검토한다: 모든 `evidence`를 열어 주장과 대조하고, 안티클레임 위반·미출시 기능·범위 과장을 `field | problem | evidence | replacement` 표로 낸다. 작성자는 항목마다 반영하거나 이유를 붙여 거절한다.
- **POS-39** [U] tagline, 카테고리 전제, 셀링포인트 목록, 성숙도 표현, 비교 페이지 여부처럼 정체성·목적 수준인 항목은 E2R의 오너 승인 게이트에서 옵션과 권장안을 붙여 확정한다(`isac-decision-brief`). 승인 후 변경은 다시 묻는다.
- **POS-40** 형제 스킬 전달물: 소스 파일, PRODUCT.md, 감사 표(POS-04·05·07), 경쟁·선례·관례 기록(POS-08~10), 의도 지도(POS-13), 방문자 모델(POS-16~18). 어느 스킬이 어느 키를 읽는지는 `references/positioning-source.md` §3.

## 교정 루프

결과가 기대와 다르면 사용자는 `isac-skill-correction`으로 이 스킬을 교정할 수 있다. 실행 중 사용자가 포지셔닝 방식을 교정했다면 따로 묻지 말고 최종 보고에 한 줄로 안내한다. `references/cases.md`는 교정할 때만 읽는다.
