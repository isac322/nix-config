# Phases, templates, and checklists (E2R)

`SKILL.md`의 E2R 규칙을 실행할 때 쓰는 세부 사양. 규칙 번호는 SKILL.md가 정본이고, 여기서는 입력·산출물·게이트·템플릿만 다룬다. 예시는 프로젝트 유형(CLI, 라이브러리, K8s operator/controller, 데스크톱 GUI 앱, MCP/AI 도구 서버, 웹 서비스)을 섞어 든다. 특정 프로젝트 값은 적지 않는다.

## Phases

| # | 단계 | owner | 입력 | 산출물 | 게이트 | 선행 |
|---|---|---|---|---|---|---|
| 0 | 킥오프 계약 + 정체성 질문 | E2R | 오너 요청, `gh repo view --json ...`, 라이브 표면 | ledger 머리(계약), intake 답 | 오너 답 수신 | — |
| 1 | 리서치 wave 1 (병렬) | POS·SITE·BRD·DSC scout | repo, 라이브 표면, 공개 웹 | 관점별 리서치 파일 | 주장마다 file:line/URL+확인일 | 0과 병렬 시작 가능, 답은 도착 즉시 전파 |
| 2 | 리서치 wave 2 (좁힘) | 같은 scout | wave 1 빈 곳 | 보강 파일 | 같음 | 1 |
| 3 | 토론 → 합의 | E2R (`isac-multi-agent-consensus`) | 모든 리서치 | `consensus.md` | 지표마다 API 출처+baseline | 1, 2 |
| 4 | 리포트 게시 + 실행 시작 | E2R | consensus | 리포트 URL, `status.json` | 오너 기기에서 200 | 3 |
| 5 | positioning source | POS | consensus, repo | `positioning.yml`(저장소 규약 우선), PRODUCT.md(파생) | 정직성 규칙(POS) | 3 |
| 6 | 브랜드 아이덴티티 | BRD (`impeccable`) | positioning, 스타일 계열 답 | 제품 맥락 속 시안, 비교 페이지 | 오너 선택 | 5 |
| 7 | 브랜드 킷 | BRD | 선택된 방향 | `assets/brand/`(규약 없을 때) + generator, favicon·manifest·OG·social preview·앱 아이콘 | 재생성 결정성, 크기 사다리 | 6 |
| 8a | 사이트 | SITE (`impeccable`) | positioning, 킷, IA | 랜딩+문서, 기술 SEO, 분석 배선 | critique/audit/detector, 시각 QA | 5 (디자인은 7) |
| 8b | README·repo 표면·레지스트리 메타데이터·신뢰/커뮤니티 파일 | DSC | positioning, 킷 | README, About/topics/homepage, 리스팅 메타데이터, health 파일 | 설치 계약 verbatim, 일관성 게이트 | 5 (이미지는 7) |
| 8c | 데모 미디어 | MED | 최신 main, 배경 승인 | 영상(MP4/WebM+poster), 스크린샷 | 프레임 검사, 타이밍 검증 | 기능 안정 + 배경 승인 |
| 9 | 게이트 | DSC·SITE·BRD·리뷰어 | 8a–8c | GREEN 판정 모음 | 모두 GREEN | 8a–8c |
| 10 | 오너 리뷰 → 머지 | E2R | PR, 프리뷰 | 승인·머지 기록 | E2R-27, 전역 머지 가드 | 9 |
| 11 | IaC apply + 배포 | SITE (IaC) | IaC PR | 라이브 도메인·HTTPS·sitemap 제출 | 라이브 smoke | 10 (IaC는 사이트 머지 전 가능) |
| 12 | 외부 사본 교체 | DSC·BRD | 머지된 에셋 URL | 교체된 외부 표면 | API/페이지 재조회 | 10, 11 |
| 13 | 라이브 감사 | E2R | 모든 표면 | 감사 표 | 기대=관측 | 12 |
| 14 | 메타데이터 릴리스 | DSC + 릴리스 절차 | 감사 gap | 새 버전, 갱신된 리스팅 | 오너 승인, 재조회 | 13 |
| 15 | ledger 마감 + 최종 보고 + memory | E2R | 전부 | 최종 보고 | verification 가드 | 13/14 |

병렬 규칙: 5가 끝나면 8a의 IA·문서 동기화·기술 SEO 배선과 8b의 텍스트 부분은 7을 기다리지 않는다. 이미지가 필요한 부분만 7 뒤에 붙인다. 8c는 최신 main에서 찍으므로 기능 변경이 남았으면 마지막에 한다.

## Intake

`isac-decision-brief` 형식으로 한 번에 묻는다. 각 항목에 저장소에서 확인한 현재값과 권장안을 붙이고, 자유 입력 여지를 남긴다.

1. 브랜드 이름: repo·패키지 이름과 같은가, 한정어가 필요한가(이름이 다른 레지스트리·계정에서 이미 쓰이면 한정어 권장 — BRD clearance 결과 첨부).
2. 도메인: 개인 도메인의 서브도메인 / 전용 도메인 / 호스팅 기본 도메인. 기존 도메인 설정과 모순이 있으면 명시.
3. 청중과 우선순위: 예) CLI → 개인 개발자 우선, 팀 도입 차순위; K8s operator → 자체 호스팅 클러스터 운영자 우선, 소규모 팀 차순위; 데스크톱 앱 → 특정 데스크톱 환경 사용자; MCP 서버 → 에이전트 사용자와 도구 통합자; 웹 서비스 → 셀프호스팅 도입자 우선.
4. 공개 언어(영어만 / 다국어). i18n 배선을 지금 할지 결정 기록만 할지.
5. 사이트 호스팅과 소스 위치(같은 repo `site/` + Pages / 별도 repo). 스택은 Astro+Starlight+Bun 기본값을 계약에 적는다(묻지 않음).
6. 고정 브랜드 요소(로고·워드마크·색)와 확장 가능한 요소.
7. 레거시 페이지: 대체 후 삭제 / 유지 / 리다이렉트.
8. 배포·머지 범위와 외부 설정 적용 경로(IaC 저장소 유무, 브라우저 허용 여부).
9. 비용 한도(무료만 등)와 분석 도구 허용 범위.
10. 성숙도: 오너가 실제로 쓰고 있는지, 어떤 기능이 출시·계획 상태인지(표면별 표현은 POS).
11. 목표 성격: 초기 사용자·피드백 / 기여자 / 채택 신호. star는 참고 지표로만 둘지.

## Research

| 관점 | owner | 산출물 핵심 |
|---|---|---|
| repo 공개 표면 감사 | POS·DSC | README·docs·social 이미지·패키지 메타데이터·레지스트리 페이지의 모든 주장을 코드와 대조. 로컬 설치 경로, 깨진 링크, 미출시 기능 광고, 모듈 경로 불일치 |
| 경쟁자·선례 랜딩 | POS | 비교 대상 N개(stars, 라이선스, hero 문장 원문, CTA, 문서 프레임워크, 성숙도 신호, 확인일), 차지할 수 있는 빈칸, 피할 클리셰 |
| 검색 수요·키워드 | POS | 무료 신호(GitHub topic 수, 자동완성, HN/Reddit 스레드)로 의도별 질의 순위, intent map |
| 기술 SEO·플랫폼 | SITE | SSG 비교, 검색·i18n·버전, OG 생성, JSON-LD, llms.txt, 호스팅·DNS 현황 |
| 포지셔닝·브랜드 기준선 | POS·BRD | 페르소나·JTBD, 포지셔닝 각도, 톤, 시각 방향 후보(카피 전 별도 산출물) |
| 문서 IA | SITE | Diátaxis 페이지 목록, 이관 지도(source file:line → page), 자동 생성 레퍼런스, 닫힌 이슈 기반 트러블슈팅 |
| 외부 표면 지도 + 자격증명 감사 | DSC | 표면별 현재 상태·필드·이미지 사양(출처 링크)·쓰기 경로(API/CLI/UI)·자격증명 상태·우선순위. 값은 출력하지 않음 |
| 이름·도메인·namespace clearance | BRD·DSC | 상표·기존 OSS·패키지 namespace·핸들 충돌, 공식 레지스트리에 다른 주체의 항목이 있는지 |

scout 결과가 비어 있으면 같은 관점으로 다시 띄운다. 오너 답(Intake)은 도착하는 즉시 실행 중 scout에 전파한다.

## Consensus

`consensus.md`(오너 언어) 절 순서:

1. 진단: 현재 표면의 문제, 증거 링크.
2. 시장 위치·포지셔닝: 카테고리 전제, 한 문장, 차별점(메커니즘+증거).
3. 목표와 지표: `| 지표 | baseline | target(기간) | 출처 API | 비고 |`. 예) 고유 clone 수(GitHub traffic API), stars(REST), 사이트 고유 방문(분석 API), 핵심 키워드 검색 순위(Search Console), 사이트 도메인에서 온 referrer 수, 첫 성공까지 시간(설치 가이드 실측), 공개 주장 오류 0건. 측정 불가 지표는 기각 목록으로.
4. 랜딩 컨셉과 시각 방향(후보와 채택 근거).
5. 사이트·기술 결정, 문서 IA.
6. 작업 목록: `| id | 작업 | owner 스킬/에이전트 | 선행 | 산출물 | 게이트 | 우선순위(P0–P2) |`.
7. 오너 질문(`isac-decision-brief` 형식).
8. 채택·기각 매트릭스와 기각한 대안(MAC-11).

## Revision brief

`revision-brief-N.md`: 라운드 번호, 오너 원문 인용, 해석(바뀌는 결정), 코드로 확인한 주장(file:line), 영향받는 owner와 파일, 지울 이전 제약, 완료 기준. 전달 후 각 owner가 수신 확인하고 ledger에 기록한다.

## Owner preview gate

- 비교 페이지: 변형마다 고정 경로(`/round-N/<variant>/`), 인덱스에 나란히, 데스크톱·모바일·다크/라이트 스크린샷, 각 변형의 한 줄 차이 설명. 이전 라운드 변형은 유지.
- 머지 승인 요청: 변경 요약, 사이트맵·표면 표, PR·diff 링크, 라이브 프리뷰 URL, 게이트 결과, 남은 결정, 머지 방식(전역 가드 세부).
- 큰 변경 사전 보고: 파일 수, 대략 줄 수, 영향 표면, 예상 시간, 되돌리기 난이도, 선택지.

## Surface coverage

작업 목록을 만들 때 아래가 owner에게 배정됐는지 확인한다. 해당 없는 항목은 이유를 적고 뺀다.

- POS: positioning source, 성숙도 표현, 키워드·intent map, anti-claims.
- BRD: 이름·도메인·namespace clearance, 로고·워드마크·색, 브랜드 킷과 generator, favicon·manifest·앱 아이콘·OG·social preview, 공개 브랜드 사용 페이지(사용 규칙·에셋·상표 문구), 재색상 시 모든 사본 재검증.
- SITE: 랜딩·문서, 기술 SEO(meta/OG/JSON-LD/sitemap/robots/canonical/llms.txt/redirect), 도메인·Pages IaC, 분석·Search Console, 문서 동기화, 성능 예산(모바일 포함), 접근성 게이트, 비교·FAQ·로드맵·변경 이력 페이지, try-it 경로, 소유 도메인의 신원 확인 배선(`rel="me"` 등), star/CTA 넛지(윤리 한도).
- DSC: README, About·topics·homepage·social preview 업로드와 검증, 커뮤니티 health 파일(CoC, CONTRIBUTING, SUPPORT, issue forms, PR template), SECURITY.md와 비공개 취약점 신고, 서명·SBOM·provenance 같은 공급망 신뢰 신호, Scorecard·Best Practices 배지, 거버넌스·MAINTAINERS·CODEOWNERS, Discussions, good-first-issue 시드, FUNDING, CITATION, 라이선스 감지, 레지스트리·스토어 메타데이터와 namespace 소유, 일관성 게이트, 레디니스 lint.
- MED: 시그니처 기능 레퍼런스 조사, 스크립트 촬영, 표면별 사양, visual PR의 before/after.

## Live audit

`| 표면 | 기대값(출처) | 관측값 | 증거(URL/명령) | 확인 시각 | 판정 |`

- 사이트 페이지마다: `<title>`, description 길이, canonical, `og:image` 200과 크기, `twitter:card`, JSON-LD 유형, manifest 링크, icons. `/sitemap*.xml`의 `<loc>` 수, `robots.txt`, `llms.txt`, 404 경로, http→https 301, 인증서.
- `site.webmanifest`(또는 동등 파일)와 참조 아이콘 200.
- `gh repo view --json description,homepageUrl,repositoryTopics,openGraphImageUrl,usesCustomOpenGraphImage` 와 커뮤니티 profile health.
- README 렌더링: 헤더 이미지(라이트/다크), 설치 명령, 링크.
- 레지스트리·스토어 페이지마다(예: 언어 패키지 인덱스, 차트 허브, 앱 스토어·배포판 저장소, MCP 레지스트리): 설명, 아이콘, 링크, 라이선스 표시, 최신 버전.
- 업로드 사본: social preview, 스토어 스크린샷, 릴리스 배너가 현재 팔레트·로고인지.
- 리포트 페이지가 최종 상태인지.

## Ledger

repo 밖 scratch(예: `~/<project>-promo/ledger.md`, 리포트 디렉터리 옆). 절:

1. 계약(E2R-04)과 intake 답.
2. 결정 로그: `| 시각 | 결정 | 출처([U] 원문 / 합의 id) | 영향 owner |`.
3. 작업: `| id | owner | status | 산출물·PR | 증거 | 승인 |` — 리포트의 `status.json`과 같은 원본에서 생성.
4. 외부 표면: `| 표면 | 이전 | 이후 | 쓰기 경로 | 확인 |`.
5. blocked: `| 표면 | 이유 | 준비된 에셋 | 오너 절차 |`.
6. 시간 기록: 단계별 시작·종료, time box 초과 보고.

## Final report

한국어, 결론 먼저.

1. 한 줄 결론: 준비 완료 / 남은 blocked N건.
2. 라이브 표면 표(Live audit 요약).
3. 머지한 PR(번호·제목·머지 커밋)과 적용한 외부 설정(URL, before/after).
4. blocked 항목과 오너가 할 정확한 절차(어디서, 무엇을, 완료 확인 방법).
5. 기록된 오너 결정(`[U]`), 수용한 잔여 위험.
6. 마케팅 에이전트용 입력 경로: positioning source, 브랜드 킷, 사이트 URL, 데모 미디어 경로. 문구는 쓰지 않는다.
7. 실행한 검증과 실행하지 못한 검증의 구분.
8. 실행 중 사용자 교정이 있었다면 `isac-skill-correction` 안내 한 줄.
