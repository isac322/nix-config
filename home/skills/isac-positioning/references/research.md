# Positioning research methods

`SKILL.md`의 POS-04~POS-18·POS-20·POS-26~28이 요구하는 조사를 수행하는 절차·명령·루브릭·출력 형식. 규칙의 정본은 SKILL.md이고, 여기는 실행 세부다. 예시는 프로젝트 유형(CLI, 라이브러리, K8s operator/controller, 데스크톱 GUI 앱, MCP/AI 도구 서버, 웹 서비스)을 섞어 쓰며 특정 프로젝트 값은 적지 않는다. 리서치 산출물은 세션 작업 디렉터리(`local://` 등)에 두고 저장소에 커밋하지 않는다. 채널 조사·게시 문구·캠페인 재료 같은 홍보 실행은 이 문서의 범위 밖이다(별도 마케팅 에이전트).

## 1. 저장소 콘텐츠 감사와 동결 루브릭 (POS-04~07)

### 1.1 감사 단위와 표면 감사표

감사 단위는 파일, 문서 섹션(H1/H2로 분할), 문단, 경쟁 페이지처럼 동질적인 항목이다. 대상 파일은 `git ls-files`로 전체를 열거하고, 라이브 표면(About·topics·social card·레지스트리 페이지)은 API/브라우저로 읽는다.

표면 감사표(POS-04)의 행 형식:

| surface | claim | code evidence (file:line) | verdict |
|---|---|---|---|
| … | … | … | true / stale / unshipped / unverifiable |

반드시 기록하는 것: 미출시 기능을 광고하는 메타데이터(topics·social card·설명 — 가장 큰 신뢰 위험), 깨진 링크, 배포 아티팩트와 다른 설치 경로, 레지스트리 404(모듈·패키지 경로와 저장소 URL 불일치), 본문의 내부 문서 링크.

### 1.2 동결 루브릭 템플릿

동질 항목이 약 20개를 넘으면 **데이터를 읽기 전에** 루브릭을 동결하고(POS-06) `judge_batch`로 일괄 분류한다. 축마다 라벨 집합과 라벨별 한 줄 판정 기준을 적는다.

```yaml
rubric: repo_surface_scan          # 동결 시각을 판정 기록에 적는다
unit: tracked file                 # git ls-files
prefilter:                         # 판정하지 않고 건너뛸 것
  - binary assets (images, fonts)
  - license texts
context_cap_chars: 6000            # 단위당 프롬프트에 넣을 최대 본문
axes:
  role:                            # 기본 라벨 = irrelevant
    must_change:    user/store-facing; brand·SEO 자산을 심거나 선언·참조해야 함
    should_review:  표면일 수 있으나 확실하지 않음
    irrelevant:     위 둘 모두 아님 (기본 라벨)
  asset_needed:                    # role이 must_change/should_review일 때만
    one_of: [app_icon, wordmark_banner, social_image, screenshot, brand_color_or_text, none]
flags:
  stale: bool                      # 내용이 코드와 어긋남
  overclaim: bool                  # 미출시 기능 광고
escalate_if:
  - role != irrelevant             # 기본 라벨이 아님
  - top_label_probability < 0.7
  - judge_error
```

실행 순서: 루브릭 동결 → 단위 열거 → `judge_batch` 일괄 분류 → 에스컬레이션 조건에 걸린 항목만 오케스트레이터(또는 전담 확인 에이전트)가 코드와 대조해 **전부** 읽는다. 오탐은 이유와 함께 판정 기록에 남긴다. 판정은 힌트이며 주장의 확정은 코드 대조로 한다.

같은 형태로 만드는 다른 루브릭:

- **문서 섹션 배치**: axes = audience {evaluator, installer, operator, contributor, internal}, target {landing, docs_tutorial, docs_howto, docs_reference, docs_explanation, keep_internal, drop}; flag stale bool. 섹션은 H1/H2로 분할한다.
- **산문 스윕**(초안 작성 후): axes = tells {clean, minor, violation, not_prose}; flags = overclaim, banned_names bool. 자동 생성 파일은 prefilter로 제외한다.
- **첫 공개 릴리스 감사**(POS-07, [U]): 추가 클래스 change_narrative("이전에는 X였다", 마이그레이션 이야기), checkout_install(배포 아티팩트가 있는데 `git clone` 설치를 설명), version_pin(버전 고정 절차 언급), internal_doc(PRD·E2E 케이스·감사 기록). 산출물은 수정이 아니라 SITE·DSC에 넘길 목록과 근거다.
- **비교 판정**(랜딩 개념·후보 선발): novelty 1–4, fit {core, decor, none}, feasible {yes, risky, no}, gimmick bool("읽고 설치하는 것을 방해하는가"). 에스컬레이션을 상위 N 선발식으로도 쓴다(예: feasible∧¬gimmick 중 novelty×fit 상위 6).

전형적 `must_change` 적중: README, GitHub About·topics, `.desktop`/AppStream metainfo(데스크톱), 패키징 spec, `pyproject.toml`·`package.json`·`Cargo.toml`·`go.mod`·`Chart.yaml` 메타데이터, docs index, 앱의 About 대화상자(GUI), 플러그인·서버 매니페스트(MCP 서버), compose 파일과 env 예시(웹 서비스).

## 2. 경쟁·카테고리 관례·선례 랜딩 (POS-08~11)

### 2.1 비교 대상 표 (POS-08)

고르는 법: 같은 문제를 푸는 도구(topic 검색, awesome 목록, 포럼에서 같이 언급되는 이름), 플랫폼 기본 도구, DIY 기준선 조합. 5~10개.

| repo | stars | license | hero 문장(원문) | 1차 CTA | docs 스택 | 성숙도 신호 | 아키텍처·데이터 경로 요지 | checkedOn (URL+날짜) |

```bash
gh api repos/<owner>/<repo> --jq '{stargazers_count, license: .license.spdx_id, description, homepage}'
```

- 랜딩은 직접 열어 읽고 스크린샷을 남긴다. hero 문장은 번역·요약하지 말고 원문으로.
- 성숙도 신호: 릴리스 빈도, 마지막 푸시, 기여자 수, 문서 완성도, "production" 주장의 유무.
- 산출물 1 — **빈자리**: 코드 증거가 있는 우리의 말 중 대부분이 못 하는 것. 대부분이 안 하는 말은 이유가 있다(과장이거나 못 증명하거나).
- 산출물 2 — **상투 목록**: 언어적(예: "seamless", "blazing fast", "… made easy")과 시각적(어두운 배경+아이소메트릭 큐브, 그라디언트 메시, 터미널 스크린샷 나열) 모두. `cliches`와 `anti_claims`로 간다(POS-25).

### 2.2 선례 랜딩 (POS-09)

7~12개를 고른다: 같은 카테고리의 대표, 작은 프로젝트의 인상적인 랜딩, 인접 카테고리(예: 인프라 도구면 CLI·에디터·데스크톱 앱 랜딩도).

| URL | signature 아이디어 1개 | hero 단어 수 | 첫 화면 코드/데모 유무 | 설치까지 클릭 수 | docs IA 첫 탭 |

디자인 판정(좋다/나쁘다)은 여기서 하지 않는다. 이 표는 SITE·BRD의 impeccable 입력이다.

### 2.3 카테고리 관례 명시 (POS-10)

§2.1·§2.2의 표에서 3회 이상 반복되는 패턴을 "기본값"으로 분류해 적는다: 지배적인 색·모티프·문구 패턴·페이지 구조(hero → 로고 나열 → 기능 그리드 → install). 디자인이 기본값과 그 정반대를 둘 다 피할 수 있게 하는 것이 목적이다.

### 2.4 시그니처 동작 레퍼런스 자료집 (POS-11, [U])

브랜드·데모·사이트의 주인공이 될 동작이나 기능이 있으면(독특한 애니메이션·제스처, 특정 프로토콜 흐름, 고유한 시각화) 구현·촬영 전에 자료집을 만든다:

- 원 구현(선행·유사 프로젝트 소스), 특허·논문, 공개 데모·튜토리얼을 URL과 함께 수집한다.
- 각 레퍼런스의 동작을 분석한다(수식·상태 기계·파라미터). 가능하면 작은 시뮬레이션으로 재현해 제품의 실제 구현과 비교한다.
- 오너가 "다른 프로젝트는 보통 어떻게 해?"라고 물으면 이 자료집의 선례를 근거로 답한다.

## 3. 검색 의도 — 무료 수요 신호 (POS-12~15)

유료 키워드 도구를 쓰지 않는다. 모든 수치는 `query | source | raw count | checkedOn`으로 기록하고, 추정은 `(estimate)`로 표시한다. 가짜 검색량을 만들지 않는다.

### 3.1 수집 명령

```bash
# GitHub topic/검색 모집단 — 후보 topic 전부에 대해
gh api -X GET search/repositories -f q='topic:<topic>' --jq .total_count
gh api -X GET search/repositories -f q='<kw> in:name,description,readme' --jq .total_count

# 경쟁 저장소 이슈·토론에서 실무자가 쓴 고통 표현(원문 수집)
gh search issues '<symptom>' --repo <owner>/<competitor> --state all --limit 30 --json title,url,commentsCount
gh api -X GET search/issues -f q='repo:<owner>/<competitor> <symptom>' --jq .total_count

# HN (Algolia 공개 API) — 스토리 수와 점수, 댓글 원문
curl -s 'https://hn.algolia.com/api/v1/search?query=<q>&tags=story' | jq '.nbHits'
curl -s 'https://hn.algolia.com/api/v1/search?query=<q>&tags=comment' | jq '.hits[:10][] | {points, objectID}'

# Reddit (서브레딧 검색 JSON; User-Agent 필요할 수 있음)
curl -s -A 'research' 'https://www.reddit.com/r/<sub>/search.json?q=<q>&restrict_sr=1&limit=25&sort=top' \
  | jq '.data.children[].data | {title, score, num_comments, permalink}'

# 검색 자동완성(무료 JSON 엔드포인트) — 씨앗어 변형으로 반복
curl -s 'https://duckduckgo.com/ac/?q=<q>&type=list' | jq '.[1]'
curl -s 'https://suggestqueries.google.com/complete/search?client=firefox&q=<q>' | jq '.[1]'

# Stack Exchange 계열 Q&A (site= 로 unix, serverfault, devops 등 전환)
curl -s 'https://api.stackexchange.com/2.3/search/advanced?site=<site>&q=<q>&filter=withscore&pagesize=10' \
  | jq '.items[] | {title, score, link}'

# 레지스트리 내부 검색 모집단 — 생태계에 맞는 것을 고른다
curl -s 'https://registry.npmjs.org/-/v1/search?text=<q>&size=1' | jq '.total'                 # npm
curl -s 'https://crates.io/api/v1/crates?q=<q>&per_page=1' | jq '.meta.total'                  # crates.io
curl -s 'https://artifacthub.io/api/v1/packages/search?ts_query_web=<q>&limit=1' | jq '.packages | length'  # Helm 차트 등
# 데스크톱: Flathub·배포판 저장소 검색; 라이브러리: 언어 패키지 인덱스(pkg.go.dev, PyPI); MCP 서버: MCP 레지스트리 검색

# 동의어 선택: Google Trends에서 두 용어를 나란히 비교(웹 UI, 상대 관심도 — 절대량 아님)
```

### 3.2 클러스터 → 정규 페이지 (POS-13~14)

- 질의는 수집된 원문 그대로 모은다(자동완성 문구, 스레드 제목). 클러스터는 인지 단계로 묶는다: `problem`("<증상> <환경>"), `solution`("<카테고리> for <플랫폼>", "<기본 도구> alternative"), `product`(이름, 이름+install/config/error), `evaluation`("X vs Y").
- 클러스터마다 **정규 페이지 하나**를 `intent_map`에 지정하고, 그 페이지의 title·meta·H1은 클러스터의 실제 문구를 쓴다. 두 페이지가 한 클러스터를 겨냥하지 않는다.
- 키워드 계층(`primary`/`secondary`/`long_tail`)과 표면별 후보(`github_topics`+모집단, `registry_keywords`)는 소스 파일에만 둔다(POS-14). topic 선택과 한도 적용은 DSC.

### 3.3 Search Console — 사이트 라이브 후 (POS-15)

SITE가 연결한 뒤 실제 노출 질의로 의도 지도를 갱신한다:

```
POST https://www.googleapis.com/webmasters/v3/sites/<siteUrl>/searchAnalytics/query
{"startDate":"…","endDate":"…","dimensions":["query","page"],"rowLimit":500}
```

- 노출은 높고 클릭률이 낮은 페이지를 title·description 개선 후보로 표시한다.
- 새로 확인된 질의는 `intent_map[].signals`에 추가하고 확인일을 적는다.

## 4. 방문자 모델 (POS-16~18)

행 형식은 `audience.visitor_model` 스키마와 같다:

| source | who | questions_60s | first_action | landing_page |
|---|---|---|---|---|

- `source`: 검색 클러스터 id, github-readme, registry, forum-link, docs-deeplink.
- `who`: 역할 + 환경 + 이미 아는 것(예: "self-hosted 클러스터 운영자, 기본 도구의 한계를 이미 겪음").
- `questions_60s`: 보통 ①이게 뭔가 ②내 환경에 맞나 ③어떻게 바로 써 보나 — 유형별로 다르다:

| 유형 | 방문자의 60초 질문 예 |
|---|---|
| CLI | 설치 한 줄과 출력 예시; 지원 셸·플랫폼 |
| 라이브러리 | import 한 줄과 최소 예제; 지원 언어 버전·라이선스 |
| K8s controller | 지원 버전·권한 범위·설치 경로; 기존 리소스와의 공존 |
| 데스크톱 GUI 앱 | 배포판·데스크톱 환경 지원; 실제 스크린샷; 패키지 유무 |
| MCP/AI 도구 서버 | 지원 클라이언트와 등록 스니펫; 도구 목록 |
| 웹 서비스 | 셀프호스트 방법·요구사항·비용; 라이브 데모 유무 |

- `first_action`: 설치 명령 / 데모 보기 / 특정 docs 페이지 중 하나를 명확히.
- 사용자가 0명이면 시연이 사회적 증거다(POS-17). `proof_inventory`(claimable / not_claimable)와 `demo_only_we_can_show`를 방문자 질문에 연결해 MED에 넘긴다.
- 오너가 표면별 1순위를 말하면 `audience.surface_priorities`에 그대로 기록한다(POS-18).

## 5. 병렬 리서치 각도와 출력 형식

### 5.1 각도

POS가 돌리거나 입력받는 조사 각도(조율은 E2R; 표 전체와 다른 스킬 소유 각도는 `isac-e2e-promo-readiness` references/phases.md §Research):

| 각도 | owner | 핵심 산출물 |
|---|---|---|
| repo 공개 표면 감사 | POS(DSC와 병행 가능) | §1 감사표·판정 기록 |
| 경쟁·카테고리 관례·선례 랜딩 | POS | §2 표, 빈자리·상투 목록 |
| 검색 수요·의도 | POS | §3 신호 표, intent_map 초안 |
| 방문자 모델·proof inventory | POS | §4 표 |
| 포지셔닝·브랜드 기준선 | POS·BRD | 페르소나·JTBD·포지셔닝 각도(카피 전 별도 산출물) |
| 이름·namespace clearance | BRD·DSC | 충돌 조사(POS-01 한정어 질문의 입력) |
| 기술 SEO·플랫폼, 문서 IA | SITE | 결과를 방문자 모델·intent_map에 반영 |
| 외부 표면 지도·자격증명 감사 | DSC | 레지스트리 검색 신호를 받아 씀 |

운용 규칙:

- scout 결과가 비어 있으면 같은 각도로 다시 띄운다. 빈 결과를 침묵으로 두지 않는다.
- 오너 답(POS-01·02)은 도착 즉시 실행 중 scout 전부에 전파한다(`agent://all`).
- 파급 조사(확인된 빈자리 검증, 보강 질의)는 2차 wave로 두고 1차를 막지 않는다.

### 5.2 산출물 파일과 판정 형식

- 각도마다 세션 디렉터리에 파일 하나(예: `research-repo-audit.md`, `research-competitors.md`, `research-keywords-landings.md`). 저장소에 커밋하지 않는다.
- 외부 사실·주장 행은 모두 같은 판정 형식:

| claim | verdict | evidence | checkedOn |
|---|---|---|---|
| … | Confirmed | URL 또는 file:line | YYYY-MM-DD |
| … | Refuted | 반박 증거 | … |
| … | Unverifiable | 확인을 시도한 방법 | … |

- `Unverifiable`에는 "못 찾음"이 아니라 **시도한 방법과 왜 안 됐는지**를 적는다. 빈 API 결과, 로그인 게이트, 403도 기록한다.
- 원문 인용은 번역하지 않는다. 추정치는 `(estimate)` 표시.

## 6. 다중 스탠스 토론 → 합의 (POS-20)

실행은 `isac-multi-agent-consensus`(MAC)에 위임한다. POS 전용 기본값:

- **렌즈 3개**: 고통·JTBD(방문자 모델과 이슈 원문 기반), 경쟁 위치(§2 표 기반), 검색 의도(§3 신호 기반). 필요하면 유지보수 비용 렌즈를 추가한다.
- **라운드**: R1 각 렌즈가 주장 ≤5개(각 주장은 §5.2의 Confirmed/Refuted/Unverifiable 판정과 증거) → R2 표적 교차 반박(에이전트 간 `agent://` 메시지, 분량 상한) → 중립 중재자가 주장별 수용·기각·수정을 명시한 구속력 있는 계획.
- **산출**: 셀링포인트 후보 3~5개. 각각 POS-21 형식(headline ≤8단어, benefit, mechanism, evidence `file:line`, proof_page)을 갖추기 전에는 합의가 끝난 것이 아니다.
- 지표가 필요하면 측정 가능한 API 출처와 baseline이 있는 것만 채택하고, 측정 불가 지표는 기각 목록에 이유와 함께 적는다.
- 카테고리 전제(POS-19)는 토론에서 후보를 뽑되 셀링포인트로 번호를 매겨 세지 않는다.

## 7. 오너에게 묻는 것 (POS-01·39)

`isac-decision-brief`로 **한 번에** 묶어 묻는다. 각 질문에 저장소·리서치에서 확인한 현재값과 권장안을 붙이고 자유 입력 여지를 남긴다. 답은 구속력이며 즉시 모든 실행 중 에이전트에 전파한다(POS-02).

1. 제품 이름과 도메인·서브도메인 — 브리프와 저장소가 다르면 추측하지 않는다. 이름 충돌 시 한정어(예: "for <플랫폼>", "-cli").
2. 1차·2차 대상 독자와 우선순위.
3. 공개 언어(영어만 / 다국어, i18n 배선 여부).
4. 사이트 호스팅·소스 위치(같은 repo / 별도 repo).
5. repo 소유 주체(개인 계정 vs 조직)와 레지스트리 namespace 소유자.
6. 목표(초기 사용자·피드백 / 기여자 / 채택 신호·후원).
7. 브랜드 중 고정할 부분과 확장 가능한 부분.
8. 기존(레거시) 페이지 처리: 대체·삭제 / 유지 / 리다이렉트.
9. 실제 운영 사용 여부 — 누가·어디서·언제부터 쓰는지(POS-29 성숙도 표현의 입력).
10. 표면별 우선순위(예: "랜딩은 브랜딩이 1순위" — POS-18).
11. 비교·대안 페이지를 둘지(검색 의도가 확인될 때만, POS-27)와 선행 프로젝트와의 관계 표현 — fork가 아니면 "inspired by", "spiritual successor" 같은 정확한 표현을 옵션으로 제시한다.
12. 상표·제휴 표현 중 실제 관계가 있는 것(재단이 받아들인 프로젝트인지 등 — POS-33).

정체성·목적 수준 산출물(tagline, 카테고리 전제, 셀링포인트 목록, 성숙도 표현, 비교 페이지 여부)은 E2R 오너 승인 게이트에서 옵션과 권장안을 붙여 확정한다(POS-39). 승인 후 변경은 다시 묻는다.
