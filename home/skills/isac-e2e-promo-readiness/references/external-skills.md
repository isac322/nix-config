# 외부 스킬·플러그인·MCP 조사 기록

2026-09-29에 온라인에 공개된 에이전트 스킬(SKILL.md 팩), 플러그인, MCP 서버를 조사했다. 목적은 우리 계열(E2R·POS·BRD·SITE·DSC·MED)에 넣을 일반화된 아이디어를 찾는 것이다. 별점·설치 수·마지막 push는 조사일 기준 GitHub API와 skills.sh 카운터다.

**원칙 [U]: 외부 스킬은 설치하지 않는다.** 읽고 일반화된 규칙만 해당 스킬 본문에 흡수하고, 출처는 이 파일에 기록한다. 원문을 통째로 옮기지 않는다(프로젝트 무관하게 일반화한다). 라이선스가 없거나 `NOASSERTION`인 저장소는 아이디어만 참고하고 텍스트를 옮기지 않는다.

"흡수" 열은 해당 스킬의 규칙 ID(실제로 본문에 들어간 것)다. "—"는 흡수하지 않음이다. 흡수 판단이 조사자 추정이면 *(추정)*으로 표시한다.

## 1. 조사한 항목(52 + 추가 팩)

### 포지셔닝·런치 팩

| # | 이름 | URL | 커버리지 | 흡수 → 담당 | 주의 |
|---|---|---|---|---|---|
| 1 | coreyhaines31/marketingskills | https://github.com/coreyhaines31/marketingskills | ~50개 마케팅 스킬 + 플러그인(51.8k★, skills.sh 최다 설치). 스킬 공유 context 파일, ORB 채널 프레임, directory-submissions의 "3 hard rules" | 공유 context 파일 관례 → POS-34(단일 positioning source). "foundation before submission" → DSC-42. 디렉터리별 포지셔닝 변형 → POS-14 *(추정)* | SaaS 중심. 런치·게시·카피 스킬은 마케팅 에이전트 범위 |
| 2 | samber/developer-relations-skills | https://github.com/samber/developer-relations-skills | ~60개 DevRel 스킬(2★, 신생). `oss-launch`: 이름·상표·라이선스 clearance, clean machine cold-run readiness 게이트, `<name> is a <category> for <audience>…` 원라이너, "why not X", HN 겸손 문체 인용 | 이름·네임스페이스 clearance → BRD-05~08. cold-run 설치 검증 → DSC-09. 원라이너 형식 → POS-19, DSC-08. "why not X" → POS-28. "모든 주장을 소스와 대조" → POS-04·21·38. 채널 우선순위 표는 미흡수(마케팅 범위) | 구조적으로 가장 가까운 선례. 신생 저장소라 유지보수 불확실 |
| 3 | jonathimer/devmarketing-skills | https://github.com/jonathimer/devmarketing-skills | 36개 스킬(87★, sickn33에 미러). open-source-marketing "Growth = Real value × Discoverability × First-use experience", github-presence README 해부표, 공유 audience context | README 해부 → DSC-06 *(추정)*. 공유 context → POS-34 *(추정)* | 채널·게시 스킬 다수는 마케팅 범위 |
| 4 | everest-an/github-morestar-skill | https://github.com/everest-an/github-morestar-skill | 단일 스킬 + references + launch-kit + 자체 llms.txt. 포지셔닝 진단 4문 → README first screen → 하루 집중 런치 → retention | README 첫 화면 구성 → DSC-07~08. llms.txt → SITE-42. star 노출 임계값 개념 → SITE-52 *(추정)* | 채널별 별 수익 기대치(예: HN 500–2000)는 출처 없음 — 채택 전 팩트체크 필수. 런치 부분은 마케팅 범위 |
| 5 | gingiris-1031/gingiris-skills | https://github.com/gingiris-1031/gingiris-skills | 75개 팩(82★). `gingiris-opensource`: Go/Fix/No-Go 6게이트 런치 계약, 채널 운영 표(ICP·angle·CTA·UTM·owner·성공 기준·중단 조건·evidence URL), anti-star-farming | Go/Fix/No-Go 게이트 → E2R-24 *(추정)*. 스타 조작 금지 → POS-25/STAR 파밍 금지 정신 *(추정)*. 채널 운영 표는 마케팅 에이전트에게 인계 | AFFiNE 경험 주장은 검증 불가 |
| 6 | sickn33/agentic-awesome-skills | https://github.com/sickn33/agentic-awesome-skills | 47k★ 애그리게이터/미러 마켓 | — (미러라서 원본 기준으로 평가) | `source_repo`·`license_source` 메타는 있으나 중복 |
| 7 | kostja94/marketing-skills | https://github.com/kostja94/marketing-skills | 160+ 스킬(999★). `platforms/github`: About/topics/Website/Pages/profile README 체크리스트 | GitHub 표면 체크리스트 → DSC-15~18 *(추정)* | "parasite SEO" 프레이밍은 우리 목소리와 충돌 — 그 부분은 버림 |
| 8 | kdeldycke/repomatic `repomatic-topics` | https://github.com/kdeldycke/repomatic/tree/main/.claude/skills/repomatic-topics | Claude 스킬. topic 페이지 1면 진입 별점을 재서 high/medium/niche 분류, niche 복합 topic 선호, 확인 후 `gh api PUT …/topics` | topics 측정·선택 방법 → DSC-16 + references/repo-surface.md §3 | GPL-2.0 — 코드가 아니라 방법만 흡수 |
| 9 | thatrebeccarae/claude-marketing | https://github.com/thatrebeccarae/claude-marketing | 스킬 팩(154★). `github-readme` generate/audit(0–100점, 읽기 전용)/update 모드, `social-preview` | README 감사-먼저 순서 → DSC-01·03 *(추정)* | 점수 매기기 관례는 채택 안 함(증거 대조 방식 사용) |
| 10 | samber/cc-skills | https://github.com/samber/cc-skills | 21개(224★). `site-launch-checklist`: analytics·GSC, DNS/TLS, robots, sitemap, llms.txt, hreflang, schema, OG, favicon+manifest, Lighthouse/CWV/WCAG 게이트, TONE.md + humanizer 패스 | 사이트 준비 체크리스트 전반 → SITE-40~42, SITE-57~61, references/seo-checklist.md. TONE.md+humanizer 패스 → SITE-22·24(voice 패널) *(추정)* | Cloudflare+Vercel+PostHog 편향 — 우리 기본값(Astro+Starlight+GitHub Pages, 쿠키 없는 분석)으로 대체 |
| 11 | AgriciDaniel/claude-seo | https://github.com/AgriciDaniel/claude-seo | 26 서브스킬+19 에이전트 플러그인(17.9k★). 기술 SEO, E-E-A-T, schema, GEO/AEO, llms.txt, GSC/PSI API | 기술 SEO 커버리지 목록 → SITE-40~42 *(추정)* | SaaS/대행사 규모(리포트·PDF 생성)는 과도. 비교·alternatives 페이지 스킬 일부만 참조(아래 #19 항목) |
| 12 | AgriciDaniel/claude-blog | https://github.com/AgriciDaniel/claude-blog | 블로그 플러그인(2.3k★). "5-gate Blog Delivery Contract" 품질 게이트 패턴 | 게이트-계약 패턴 → E2R-04·24 *(추정)* | 블로그 콘텐츠 생산은 범위 밖 |
| 13 | AgriciDaniel/codex-seo | https://github.com/AgriciDaniel/codex-seo | #11의 Codex 포트(761★) | — | NOASSERTION |
| 14 | addyosmani/web-quality-skills `seo` | https://github.com/addyosmani/web-quality-skills | 6개(2.9k★, seo 47.6K 설치). Chrome DevTools MCP로 Lighthouse, 헤더·리다이렉트·robots·sitemap·canonical·구조화 데이터. "Do not invent ranking-factor weights", 검증 완료 전 "pending" 보고 | 정직한 SEO 보고(실행 안 한 검증은 pending) → SITE-61, DSC-54, E2R-46 *(추정)*. 증거-우선 감사 순서 → SITE QA 접근 *(추정)* | 양호·정직한 선례 |
| 15 | github/awesome-copilot `create-readme` 등 | https://github.com/github/awesome-copilot | Copilot 프롬프트/스킬(39.5k★). 저장소 분석 → README 생성 | — | 생성기 결과가 획일적 → 채택 안 함 |
| 16 | softaworks/agent-toolkit `crafting-effective-readmes` | https://github.com/softaworks/agent-toolkit | README 작성 스킬(2.5k★) | — | 본문 미독 [INFERENCE] |
| 17 | oil-oil/beautify-github-readme | https://github.com/oil-oil/beautify-github-readme | (1.8k★) "Markdown = 콘텐츠, deterministic SVG = 레이아웃". README 모드/자산만 모드, GIF는 opt-in+SVG 폴백, 편집 전 범위 확인 | deterministic SVG 자산 + 생성기 → BRD-15·34 *(추정)*. GIF opt-in → MED-06 방향과 일치 | — |
| 18 | anthropics/skills `brand-guidelines`·`theme-factory`·`skill-creator` 등 | https://github.com/anthropics/skills | 공식 스킬(178.8k★). 브랜드 색·타이포를 스킬로 인코딩하는 패턴, skill-creator의 작성·eval 관례 | brand-guidelines 패턴(자산+규칙 문서) → BRD-37 + references/brand-kit.md. 공개 브랜드 페이지 → SITE-39 반영 *(추정)*. skill-creator 관례는 계열 작성에 참고 | Anthropic 자사 브랜드 기준 — 내용이 아니라 패턴만 |
| 19 | anthropics/knowledge-work-plugins marketing + brand-voice | https://github.com/anthropics/knowledge-work-plugins | 마케팅 플러그인(seo-audit, brand-review, competitive-brief) + brand-voice 파이프라인(discover → guidelines → enforce), Apache-2.0 | — | 기업/사내 마케팅용. discover→enforce 파이프라인은 OSS 표면에 과도 |
| 20 | blader/humanizer | https://github.com/blader/humanizer | (52.6k★) AI 문체 카탈로그와 재작성 패스 | 이미 로컬 `humanizer` 스킬로 채택 — 전 스킬이 참조(SITE-22, DSC-50) | — |
| 21 | hardikpandya/stop-slop | https://github.com/hardikpandya/stop-slop | (17.6k★) de-slop 규칙 파일 | humanizer와 같은 역할 — 중복이라 별도 흡수 없음 | — |
| 22 | Nanako0129/sepia | https://github.com/Nanako0129/sepia | (2.9k★) 다국어 de-AI(zh/zh-TW/ja 변형 존재) | — | 한국어 de-slop 스킬 부재 → 격차(§3) |
| 23 | leonxlnx/taste-skill (`brandkit` 등) | https://github.com/leonxlnx/taste-skill | (90.9k★, brandkit 325.5K 설치) 브랜드 킷과 anti-generic 비주얼 taste | anti-generic 방향 → BRD-12·26(카테고리 기본값 배제) *(추정)* | 본문 미독 [INFERENCE] |
| 24 | tech-leads-club/agent-skills `(gtm)/multi-platform-launch` | https://github.com/tech-leads-club/agent-skills | (7.0k★) 계획 전 7개 필수 입력, 2025–26 플랫폼 표 | 계획 전 필수 입력 수집 → E2R-04·07 킥오프 계약/일괄 질문 *(추정)* | SaaS. 채널 표는 마케팅 범위. NOASSERTION |
| 25 | chadboyda/agent-gtm-skills | https://github.com/chadboyda/agent-gtm-skills | #24의 상류(79★) | — | 라이선스 없음 |
| 26 | aaron-he-zhu/aaron-marketing-skills | https://github.com/aaron-he-zhu/aaron-marketing-skills | 플러그인+마켓플레이스(2.9k★). research → assemble → prove → mobilize 파이프라인, seo-geo, evals | — | 런치 파이프라인 구조는 마케팅 범위 |
| 27 | aaron-he-zhu/seo-geo-claude-skills | https://github.com/aaron-he-zhu/seo-geo-claude-skills | (211★) SEO/GEO 콘텐츠 스킬 | — | 콘텐츠 마케팅 |
| 28 | nowork-studio/notfair-plugin | https://github.com/nowork-studio/notfair-plugin | (3.9k★) SEO/GEO/마케팅 플러그인 | — | 미검증 |
| 29 | ReScienceLab/opc-skills `seo-geo` | https://github.com/ReScienceLab/opc-skills | (1.8k★, seo-geo 49.5K 설치) 솔로프리너 SEO/GEO | — | — |
| 30 | zubair-trabzada/ai-marketing-claude | https://github.com/zubair-trabzada/ai-marketing-claude | (2.7k★) 병렬 서브에이전트 감사 + 점수 PDF | — | 대행사/SaaS. PDF 리포트 산출물은 불필요 |
| 31 | alirezarezvani/claude-skills | https://github.com/alirezarezvani/claude-skills | (26.8k★) 380개 메가팩, 마케팅 부분집합 | `business-name-fit` 네이밍 보조 → BRD-05 clearance 참고 *(추정)* | 범용 |
| 32 | wondelai/skills `storybrand-messaging` 등 | https://github.com/wondelai/skills | (2.3k★) 책 기반 프레임워크 | — | B2C/SaaS |
| 33 | OpenClaudia/openclaudia-skills | https://github.com/OpenClaudia/openclaudia-skills | (700★) SEO·콘텐츠·이메일 | — | SaaS |
| 34 | Yuzzyuk/marketing-os | https://github.com/Yuzzyuk/marketing-os | (530★) 단일 메가스킬, "copy graded before you see it", 0–100 채점, hook 엔진 | "보여 주기 전 채점" 방향 → SITE-24 패널·E2R-25 *(추정)* | SaaS |
| 35 | iannuttall/seo | https://github.com/iannuttall/seo | 스킬+로컬 CLI+MCP(543★). 자체 크롤·GSC·GA4 데이터 위 70+ 감사 | GSC 쿼리 데이터로 title/meta 반복 → SITE와 POS-15 *(추정)* | 유료 데이터 의존 가능 |
| 36 | tigerless-labs/seo-ops | https://github.com/tigerless-labs/seo-ops | (519★) LLM 없는 결정적 26개 pass/fail 체크 | 결정적 head 태그·SEO 게이트 → SITE-57·DSC-49 *(추정)* | 라이선스 없음 |
| 37 | Bhanunamikaze/Agentic-SEO-Skill | https://github.com/Bhanunamikaze/Agentic-SEO-Skill | (941★) 스킬+88개 증거 수집 스크립트 | 증거 수집기로서 스크립트 패턴 → SITE 감사 *(추정)* | — |
| 38 | JeffLi1993/seo-audit-skill | https://github.com/JeffLi1993/seo-audit-skill | (763★) 초급/고급 감사 | — | — |
| 39 | AminForou/mcp-gsc | https://github.com/AminForou/mcp-gsc | MCP(1.8k★). GSC 쿼리·색인 인사이트 | 도구 후보로 tools.md §10에 등재(SITE·POS) | 설치는 하지 않고 API 직접 호출로 대체 가능 |
| 40 | saurabhsharma2u/search-console-mcp | https://github.com/saurabhsharma2u/search-console-mcp | MCP(295★). GSC + Bing Webmaster + GA4 | tools.md §10 | 동일 |
| 41 | googleanalytics/google-analytics-mcp | https://github.com/googleanalytics/google-analytics-mcp | 공식 MCP(3.3k★) GA4 리포팅 | — | 우리 기본값은 쿠키 없는 분석(SITE-49)이라 GA4는 채택 안 함 |
| 42 | getsentry/plausible-mcp | https://github.com/getsentry/plausible-mcp | MCP(42★). 프라이버시 친화 분석 | tools.md §10 대안 목록 | — |
| 43 | mickpletcher/AI-Skills `github-social-preview` | https://github.com/mickpletcher/AI-Skills | 스킬+생성기(16★). 1280×640 <1MB JPG 생성, "Do not fabricate missing facts" | 소셜 프리뷰 규격 → BRD-35·DSC-18. "사실 지어내지 않기" → POS-04와 일치 | NOASSERTION. 유사: laurigates `github-social-preview`, bestdeejay-design `repo-social-preview` |
| 44 | b-open-io/prompts `cli-demo-gif` | https://github.com/b-open-io/prompts | (16★) VHS `.tape` 작성 → `docs/demo/` 렌더 | VHS tape 스크립트 캡처 → MED-13 CLI 경로. 유사: bruin-data `record-vhs-demo`, babarot `vhs-demo`/`vhs-tape-authoring` | 라이선스 없음 — 방법만 참고 |
| 45 | davila7/claude-code-templates `star-history-chart` 등 | https://github.com/davila7/claude-code-templates | (32.1k★) 컴포넌트 마켓. star-history 임베드, `domain-name-brainstormer` | star-history 배지는 선택 사항으로 tools.md §10·DSC에 반영. 네이밍 보조 → BRD-05 참고 *(추정)* | 유사: 666ghj/create-star-history-skill, korakot `star-history` |
| 46 | firecrawl/llmstxt-generator | https://github.com/firecrawl/llmstxt-generator | (537★) llms.txt/llms-full.txt 생성기 + 프레임워크 플러그인 | llms.txt 자동 생성 → SITE-42 + tools.md §7(starlight-llms-txt) | 라이선스 없음. 생성 결과는 직접 검수 |
| 47 | umutxyp/Seo-Promt-Master | https://github.com/umutxyp/Seo-Promt-Master | (554★) Google SEO 문서를 per-route 감사 프롬프트로 | — | 프롬프트 팩 |
| 48 | appeeky/aso-skills | https://github.com/appeeky/aso-skills | (2.1k★) 앱 스토어 리스팅 최적화(press-and-pr 포함) | 스토어 리스팅 품질 관점 → DSC-36(Flathub 품질 기준) *(추정)* | B2C 모바일. press-and-pr은 마케팅 범위 |
| 49 | ParthJadhav/app-store-screenshots | https://github.com/ParthJadhav/app-store-screenshots | (7.1k★) 스토어 스크린샷 파이프라인 | 표면별 스크린샷 규격 파이프라인 → MED-26·media-specs.md *(추정)* | B2C 모바일 |
| 50 | irinabuht12-oss/marketing-skills | https://github.com/irinabuht12-oss/marketing-skills | (2.6k★) 49개 + ads MCP | — | 광고/B2C, 라이선스 없음 |
| 51 | bergside/awesome-design-skills | https://github.com/bergside/awesome-design-skills | (3.0k★) DESIGN.md/SKILL.md 목록 | — | 목록일 뿐 |
| 52 | forint573/human-copywrite | https://github.com/forint573/human-copywrite | (6★) "never invents facts, keeps brand voice" | — | POS 정직 규칙이 더 강함 |

### 추가 발견 팩(2026-09-29 gap 조사에서 별도 확인 — in-scope 커버리지 있음)

| 이름 | URL | 커버리지 | 흡수 → 담당 | 주의 |
|---|---|---|---|---|
| castrojo/cncf-skills | https://github.com/castrojo/cncf-skills | 유지보수자용 스킬 24개: openssf-badge, openssf-scorecards, security-policy·contacts·embargo·self-assessment, governance-*, maintainers-list, codeowners, contributor-ladder, roadmap, adopters, releases, graduation-checklist, vendor-neutrality | 신뢰 신호 일괄 → DSC-25~31. 거버넌스·기여자 표면 → DSC-22·31. roadmap/changelog 노출 → SITE-37 *(추정)* | CNCF 생태계 기준 — 재단 어조는 우리 규모에 맞게 축소 |
| alpha-omega-security/scrutineer | https://github.com/alpha-omega-security/scrutineer | `posture`: 정책 파일·PVR 플래그·security.txt·advisories로 신고 수용 준비도 점수화. sbom·disclose·threat-model·compliance 포함 | SECURITY.md+PVR+security.txt 묶음 → DSC-26. 감사 순서 → DSC-03 *(추정)* | 작성은 여전히 수동 — 파일 내용은 우리가 만든다 |
| jdevalk/skills `github-repo` | https://github.com/jdevalk/skills | repo 표면 감사(health 파일, 메타데이터, 템플릿, 브랜치 위생) | 표면 인벤토리·감사 → DSC-01~03, DSC-25 *(추정)* | — |
| NASA-AMMOS/slim | https://github.com/NASA-AMMOS/slim | slim-code-of-conduct, slim-contributing-guide, slim-issue-templates, slim-governance, slim-license, slim-readme, slim-changelog, slim-website-maker | 커뮤니티 파일 세트 → DSC-25·31. 라이선스 감지 → DSC-29 *(추정)* | NASA 프로젝트 관례 — 템플릿 그대로 쓰지 않고 구조만 |
| royalpinto007/distro-skills | https://github.com/royalpinto007/distro-skills | `comparison-pages`(검증됨), awesome-list-submission, github-discoverability, npm-pypi-discoverability, demo-asset | 비교 페이지 구조 → POS-27·SITE-35. awesome-list 준비 상태 → DSC-42 | launch/outreach 스킬은 범위 밖 |
| Community-Access/accessibility-agents | https://github.com/Community-Access/accessibility-agents | WCAG 2.2 AA 리뷰 에이전트 11종 | a11y 게이트 기준 → SITE-58(axe·pa11y CI, 키보드, reduced-motion, 터치 타깃) *(추정)* | 에이전트 개수가 많아 통째 적용보다 체크 기준만 |
| cofoundy/brand-skills | https://github.com/cofoundy/brand-skills | 네이밍 + prior-art + 도메인 체크 | 이름 clearance sweep 항목 → BRD-05 *(추정)* | — |

### 디스커버리 디렉터리(항목 수에 미포함)

| 디렉터리 | URL | 신호 |
|---|---|---|
| skills.sh | https://www.skills.sh/search?q=marketing | 설치 수 카운터. 마케팅 결과는 coreyhaines31이 지배(44K–216K) |
| ComposioHQ/awesome-claude-skills | https://github.com/ComposioHQ/awesome-claude-skills | 75.8k★ |
| hesreallyhim/awesome-claude-code | https://github.com/hesreallyhim/awesome-claude-code | 54.8k★ |
| VoltAgent/awesome-agent-skills | https://github.com/VoltAgent/awesome-agent-skills | 35.0k★, "1000+ skills" |
| travisvn/awesome-claude-skills | https://github.com/travisvn/awesome-claude-skills | 15.2k★ |
| BehiSecc/awesome-claude-skills | https://github.com/BehiSecc/awesome-claude-skills | 10.2k★ |
| 공식 MCP registry | https://registry.modelcontextprotocol.io/v0/servers?search=seo | "seo" 검색에 30+ 서버(대부분 벤더 SaaS 래퍼) |
| wilwaldon/Claude-Code-Content-Marketing-Toolkit | https://github.com/wilwaldon/Claude-Code-Content-Marketing-Toolkit | 콘텐츠 마케팅 스킬·MCP 목록(8★) |

## 2. 카테고리별 수량

카테고리: C1 포지셔닝, C2 GitHub repo 표면, C3 랜딩/문서 사이트, C4 기술 SEO, C5 브랜드 정체성, C6 카피·문체, C7 런치·채널, C8 레지스트리·리스팅, C9 측정, C10 시각 미디어, C11 프로세스·QA.

**(a) GitHub 코드 검색 hit 수**(`filename:SKILL.md <terms>`, 2026-09-29 실행). 미러·포크가 섞여 있고 코드 검색의 `OR` 처리가 나빠 일부 쿼리가 실패했다. **자릿수**로만 읽는다.

| 카테고리 | 쿼리 | Hits |
|---|---|---|
| C1 | positioning competitor "value proposition" | ~8,200 |
| C2 | readme badges "quick start" github | ~1,500 |
| C3 | landing page / docs site / docusaurus / mkdocs (OR) | 42 (OR가 실계수보다 적게 셈) |
| C4 | seo sitemap robots "structured data" | ~9,900 |
| C5 | brand logo "color palette" | ~16,500 (대부분 UI/디자인 스킬) |
| C6 | copywriting + brand/tone of voice | ~225 |
| C7 | hacker news / reddit / product hunt + launch | ~2,100 |
| C8 | awesome list / directory submission / registry listing | 44 |
| C9·C10·C11 | OR 쿼리 실패 — (b) 참조 | — |

**(b) 선별 52개 항목 안에서의 커버리지**(한 항목이 의미 있게 덮는 카테고리당 1회 계수).

| 카테고리 | 항목 수 | 밀도 | 비고 |
|---|---|---|---|
| C1 포지셔닝 | 14 | 높음 | 대부분 SaaS ICP·경쟁 프레임. OSS 프레임("why not X", 카테고리 우선 원라이너)은 #2·4·5뿐 |
| C2 GitHub repo 표면 | 14 | 중간 | README 생성기는 흔함. topics 분석(#8), social preview(#43), About/Pages(#7)는 드묾 |
| C3 랜딩/문서 사이트 | 4 | **드묾** | #2(docs-structure-audit, docs-seo), #3(docs-as-marketing), #10. SSG 선택·OSS 문서 IA는 어떤 스킬도 안 다룸 |
| C4 기술 SEO | 26 | **포화** | 최대 클러스터. llms.txt/GEO는 표준(#4·10·11·14) |
| C5 브랜드 정체성 | 8 | 중하 | 브랜드 가이드라인 인코딩(#18)·비주얼 킷(#23). 네이밍·상표 clearance(#2뿐), favicon/manifest 파이프라인(#10뿐)은 거의 없음 |
| C6 카피·문체 | 17 | 높음 | 전환 카피(SaaS) + anti-slop(#20~22) 두 갈래. 주장 팩트체크는 #2·43·52에만 |
| C7 런치·채널 | 18 | 높음 | Product Hunt 중심. HN·Reddit·awesome-list·dev.to를 잘 다루는 것은 #2~5뿐. **전부 마케팅 에이전트 범위** |
| C8 레지스트리·리스팅 | 8 | **OSS에는 드묾** | SaaS/AI 디렉터리(#1), 앱 스토어(#48). **pkg.go.dev, ArtifactHub, Flathub, AUR, KDE Store, PyPI 메타, MCP 레지스트리를 발견 표면으로 다루는 스킬 없음** |
| C9 측정 | 13 | 중간 | GA4/GSC MCP가 대부분. OSS 신호(star velocity, GitHub traffic API, 채널별 UTM)는 #2·4·5·45뿐 |
| C10 시각 미디어 | 10 | 중하 | social preview(#43), VHS 데모(#44), SVG 히어로(#17), OG 이미지(#11) 등 점 단위 도구만 |
| C11 프로세스·QA | 10 | 낮음 | 게이트·계약(#2 cold-run 게이트, #5 Go/Fix/No-Go, #12 5-gate, #34 채점). **마케팅 주장의 다에이전트 토론·코드 대조 팩트체크는 없음** |

## 3. 이 계열이 채우는 격차

조사된 어떤 항목도 다음을 다루지 않는다 — 우리가 직접 만든 이유다.

- **OSS 레지스트리를 발견 표면으로**(C8): pkg.go.dev, Artifact Hub(Helm/operator), Flathub/AppStream metainfo, AUR, KDE Store, PyPI classifiers/`project.urls`, MCP 레지스트리(공식·Smithery·Glama 등) → DSC §5 + references/registries.md.
- **OSS 문서 사이트 IA**(C3): SSG 선택(Astro+Starlight [U]), Diátaxis 탭, 방문자 순서, 커스텀 도메인 + Pages → SITE.
- **이름·상표·네임스페이스 clearance**(C5): 상표 DB, 레지스트리 네임스페이스, 핸들 sweep을 한 절차로 → BRD-05~08. samber `oss-launch` 1단계가 유일한 선례.
- **주장의 코드 대조 팩트체크와 다에이전트 비판**(C11): "verify every claim"(#2), "never invent facts"(#43·52) 조각만 존재 → POS-04·21·38, SITE-24 truth 패널, DSC-48.
- **한국어 문체·anti-slop**: zh/zh-TW/ja 변형(#22)은 있으나 한국어는 없음 → 로컬 `humanizer` + `writing-clearly-and-concisely` 조합으로 대체한다(공개 영문 텍스트 기준).
- **생태계 특화 발견 표면**: CNCF/K8s 목록, KDE 생태계, MCP 디렉터리 같은 도메인 채널은 일반 HN/Reddit/PH 스킬에 없음 → DSC references/registries.md.
- **자기 저장소용 `good first issue` 시딩·기여자 온보딩**(기존 스킬은 남의 저장소 이슈 찾기만 함) → DSC-22.
- **유지보수자 측 보안 신고 수용 표면을 끝까지**(감사만 있고 파일 작성·PVR 활성화·security.txt 배치까지는 없음) → DSC-26.
- **네임스페이스 선점 sweep**(핸들 체커 CLI만 있고 레지스트리 네임스페이스 점유 확인·claim 절차는 없음) → BRD-05, DSC-35.
- **CLOMonitor/repolinter를 런치 게이트로 쓰는 스킬 없음** → DSC-28·49.

## 4. 마케팅 에이전트로 넘기는 것(우리 범위 밖)

조사에서 발견했지만 [U] 범위 규칙상 우리가 쓰지 않는 것들. 목록만 남긴다: 런치 포스트·채널별 운영 표·UTM(#5), ORB 채널·directory 제출 실행(#1), HN/Reddit/PH 플레이북(#3·4), multi-platform launch(#24), press-and-pr·보도자료(#48), 소셜 계정 생성·handle 예약(BRD-08이 넘기는 목록), awesome-list·디렉터리 제출(DSC-42는 준비 상태까지만), 측정 리포팅 운영(E2R-02).
