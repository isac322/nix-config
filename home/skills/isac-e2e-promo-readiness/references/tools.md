# 준비 도구 카탈로그

promo-readiness 계열(E2R·POS·BRD·SITE·DSC·MED)이 쓰는 도구·CLI·라이브러리·서비스·검증기 목록이다. 출처는 두 가지다. 하나는 실제 준비 세션에서 쓴 것이고(`세션` = yes), 다른 하나는 2026-09-29 온라인 조사에서 찾은 것이다(`세션` = no). 별점, 라이선스, 가격은 조사일 기준이라 바뀔 수 있으니 채택 전에 다시 확인한다. 이 표는 도구 목록일 뿐이다. 규칙은 각 스킬 SKILL.md에 있고, 이 표를 근거로 `[U]` 규칙을 완화하지 않는다.

열 설명:
- **세션**: 준비 세션에서 실제로 썼으면 yes. planned는 계획만 세우고 실행하지 않은 것, rejected는 써 보고 버린 것이다.
- **자동화**: Y는 에이전트가 headless로 CI나 스크립트에서 돌릴 수 있다. P는 부분 자동화로, 로그인·1회성 사람 확인·웹 UI가 필요하다. N은 사람이나 웹 UI 전용이다.
- **담당**: 그 도구를 쓰는 스킬이다. 여러 스킬이 쓰면 주 담당을 앞에 적는다.

고정 기본값(`[U]`, 상세는 각 스킬):
- 사이트는 Astro + Starlight로 만들고 Bun만 쓴다. node/npm/npx 대신 `bun`/`bunx`를 쓴다. 표에 `npx`로 소개된 도구도 `bunx`로 실행한다.
- 디자인과 UI/UX는 전부 `impeccable` 스킬을 거친다.
- 데모는 영상이 먼저다. GIF/APNG는 영상을 재생할 수 없는 곳에만 쓴다.
- 브랜드 키트 기본 경로는 `assets/brand/`다.
- 외부 스킬은 설치하지 않고 내용만 흡수한다.

## 1. 조사·대량 판정·오케스트레이션 (E2R, POS)

| 이름 | URL | 용도 | 세션 | 자동화 | 라이선스·비용 | 담당 |
|---|---|---|---|---|---|---|
| omp `judge` / `judge_batch` / `completion` (eval 커널, "jevify") | `xd://eval/judge` | 고정 루브릭으로 대량 분류한다. 문서 섹션 배치, 과장 주장·계획 기능 노출, AI 문체 흔적, code==docs 동등성, 헤드라인 채점. 판정 결과는 힌트로만 쓰고 사람이 확인한다 | yes | Y | 모델 호출 비용 | E2R, POS, SITE, DSC |
| subagents: `task`·`scout`·`browser`·`reviewer` | harness | 병렬 조사, 관점별 토론, 빌더, 리뷰(GREEN/BLOCKING) | yes | Y | — | E2R |
| `isac-multi-agent-consensus` 스킬 | `skill://isac-multi-agent-consensus` | 여러 관점 토론 → 반박 → 합의(consensus.md) | yes | Y | — | E2R |
| `isac-decision-brief` 스킬 + ask 도구 | `skill://isac-decision-brief` | 선택지와 권고안을 붙여 owner 질문을 묶어서 묻는다 | yes | P | — | E2R |
| `gh` CLI (REST·GraphQL) | https://cli.github.com | `repo view --json`, 검색 카운트, stargazers, traffic, Pages, PR/CI | yes | Y | MIT, 무료(rate limit) | 전체 |
| `rg` 금지 패턴 grep | https://github.com/BurntSushi/ripgrep | 변경 서사·세션 흔적·내부 경로·수치 누출 검사 | yes | Y | MIT/Unlicense | DSC, SITE |
| Python `http.server` / `bunx serve` | stdlib / https://github.com/vercel/serve | owner 미리보기와 steering report 페이지를 LAN 또는 VPN 사설 IP로 서빙한다. 공개 인터넷에는 노출하지 않는다 | yes | Y | 무료 | E2R, SITE, BRD |
| Camofox browser MCP | `xd://mcp__camofox_*` | 로그인이 필요한 설정 변경, 360px iframe 기법 시각 QA, `getComputedStyle` 증거 수집 | yes | P | 로컬 서비스 | E2R, SITE, DSC |
| Playwright + Chromium / chrome-headless-shell | https://github.com/microsoft/playwright | 뷰포트별·다크 모드·전체 페이지 스크린샷, 요소 캡처, 터치 에뮬레이션 | yes | Y | Apache-2.0 | SITE, MED |
| 1Password `op` / macOS `security` keychain | https://developer.1password.com/docs/cli | 브라우저 로그인 자격증명 주입. 값은 출력하지 않는다 | yes | P | 유료(1Password) | E2R |
| `writing-clearly-and-concisely`, `humanizer` 스킬 | `skill://…` | 모든 공개 문자열의 작성·검수에 필수 | yes | Y | — | SITE, DSC, POS |
| `isac-github-publishing` 스킬 | `skill://isac-github-publishing` | 공개 GitHub 텍스트의 언어와 sanitize 규칙 | yes | Y | — | DSC |
| `mermaid` (보고서 도식) | https://github.com/mermaid-js/mermaid | 진행 흐름 도식, steering 페이지 | yes | Y | MIT | E2R |

## 2. 포지셔닝·키워드·선례 조사 (POS)

| 이름 | URL | 용도 | 세션 | 자동화 | 라이선스·비용 | 담당 |
|---|---|---|---|---|---|---|
| GitHub search API 토픽/경쟁 카운트 | https://docs.github.com/en/rest/search/search | `gh api search/repositories -f q="topic:<t>"` → `total_count`로 토픽 규모와 경쟁 별점을 본다 | yes | Y | 무료, rate limit | POS, DSC |
| GitHub topic 페이지 | https://github.com/topics | 토픽별 1페이지 진입에 필요한 별점을 측정해 niche 토픽을 고른다 | yes | Y | 무료 | POS, DSC |
| Google autosuggest / "People also ask" | https://www.google.com | 검색 의도별 쿼리 확장(evaluate/install/troubleshoot) | yes | N | 무료 | POS |
| Google Trends | https://trends.google.com | 동의어 사이 상대 관심도(볼륨 아님) | no | N | 무료 | POS |
| HN Algolia API | https://hn.algolia.com/api | 카테고리 선례, 수요 신호, 과거 반응(읽기 전용 조사) | yes | Y | 무료 | POS |
| Reddit `.json` / `r/<sub>/about/rules.json` | https://www.reddit.com | 수요와 반복 질문 조사(읽기 전용). 게시는 범위 밖 | yes | P | 무료, bot wall 가능 | POS |
| GH Archive on ClickHouse Play | https://play.clickhouse.com | 비교 대상 별점 곡선, 외부 참여자 기준선 | yes | Y | 무료 | POS |
| star-history.com | https://star-history.com | 선례 별점 곡선 비교 | yes | P | 무료 | POS |
| OSS Insight | https://ossinsight.io | 저장소 비교, 컬렉션(발견 표면), 공개 API | no | Y | 무료 | POS |
| ecosyste.ms | https://ecosyste.ms | 레지스트리 전반의 다운로드와 dependents(허영 지표 대신 실제 채택) | no | Y | 무료 | POS |
| Ahrefs free keyword tools / AnswerThePublic | https://ahrefs.com/free-seo-tools · https://answerthepublic.com | 키워드 아이디어, 질문형 확장 | no | N | 무료 한도 작음 | POS |
| DataForSEO MCP | https://github.com/dataforseo/mcp-server-typescript | 실측 검색량·SERP | no | Y | **유료 API**. 무예산 OSS에는 기본으로 쓰지 않는다 | POS |
| 경쟁·선례 랜딩 페이지 fetch | `read` / web fetch | hero 문구, CTA, 문서 구조, 피해야 할 클리셰 수집(URL과 날짜 기록) | yes | Y | — | POS, SITE |

## 3. 이름·상표·도메인·네임스페이스 확인 (BRD, DSC)

| 이름 | URL | 용도 | 세션 | 자동화 | 라이선스·비용 | 담당 |
|---|---|---|---|---|---|---|
| USPTO tmsearch / WIPO Global Brand DB / TMview | https://tmsearch.uspto.gov · https://branddb.wipo.int · https://www.tmdn.org/tmview | 이름 상표 충돌 확인 | no | P | 무료 | BRD |
| fossmarks.org | http://fossmarks.org | OSS 상표 실무 가이드 | no | N | 무료 | BRD |
| 제3자 상표 정책 페이지 | 예: https://www.linuxfoundation.org/legal/trademark-usage · https://www.cncf.io/brand-guidelines/ | 참조하는 타사 마크의 사용 규칙과 보증 암시 금지 | yes | N | — | BRD, POS |
| namechecker / instantdomainsearch | https://namechecker.vercel.app · https://instantdomainsearch.com | 이름·도메인 가용성 | no | P | 무료 | BRD |
| sherlock | https://github.com/sherlock-project/sherlock | 핸들 가용성 일괄 확인(계정 생성은 하지 않는다) | no | Y | MIT | BRD |
| `whois` / RDAP, `dig` | — | 도메인 등록과 DNS 상태 | yes (`dig`) | Y | 무료 | BRD, SITE |
| 레지스트리 이름 검색 API | 예: `pypi.org/pypi/<n>/json`, `registry.modelcontextprotocol.io/v0/servers?search=`, `artifacthub.io/api/v1/packages/search`, `flathub.org/api/v2/appstream/<id>` | 패키지 네임스페이스 선점과 fork 점유 확인 | yes | Y | 무료 | DSC, BRD |

## 4. 브랜드·SVG·아이콘 (BRD)

| 이름 | URL | 용도 | 세션 | 자동화 | 라이선스·비용 | 담당 |
|---|---|---|---|---|---|---|
| `impeccable` 스킬 | https://github.com/pbakaus/impeccable · `skill://impeccable` | `context`/`init`(PRODUCT.md·DESIGN.md), `concept-seed`, `new-work`, `craft-floor`, `critique`, `audit`, `polish`, `live`, finish reviewer, documenter, `detect --json`(규칙 61개, exit 0/1/2) | yes | Y (detect), P (루프) | Apache-2.0. `bunx`로 실행한다 | BRD, SITE |
| 브랜드 키트 생성기(Bun+TS 또는 Python `build.py`) | repo `assets/brand/` | SVG 원본 → 모든 PNG/ICO/OG/manifest를 결정적으로 생성한다. 재생성 명령은 README에 적는다 | yes | Y | 자체 | BRD |
| resvg / usvg | https://github.com/linebender/resvg | 결정적 SVG→PNG 변환, 텍스트를 path로 굽기 | yes | Y | Apache-2.0/MIT | BRD, SITE |
| rsvg-convert (librsvg) | https://gitlab.gnome.org/GNOME/librsvg | SVG→PNG 대안(Linux 데스크톱 아이콘) | no | Y | LGPL-2.1 | BRD |
| Inkscape CLI | https://inkscape.org | 텍스트 outline, 고품질 export | no | Y | GPL-2.0+, 의존성이 무겁다 | BRD |
| SVGO | https://github.com/svg/svgo | SVG 최적화(`bunx svgo --multipass`) | no | Y | MIT | BRD |
| scour | https://github.com/scour-project/scour | SVG 정리(Python 대안) | no | Y | Apache-2.0 | BRD |
| oxipng | https://github.com/oxipng/oxipng | 무손실 PNG 압축 | yes | Y | MIT | BRD |
| pngquant | https://github.com/kornelski/pngquant | 손실 팔레트 압축 | no | Y | **GPL-3**. 번들하지 않는다 | BRD |
| ImageMagick (`magick`, `identify`) | https://imagemagick.org | 여러 크기를 담은 `favicon.ico` 패킹, 래스터 크기 검증 | yes | Y | Apache-like | BRD |
| macOS `sips`, `file`, Pillow | — · https://python-pillow.org | 래스터화, 픽셀 크기 확인, APNG 생성 | yes | Y | 무료 / HPND | BRD, MED |
| Fontsource(self-host) / Noto via nixpkgs | https://fontsource.org | CDN 없는 폰트. 워드마크 텍스트를 path로 굽기 | yes | Y | 폰트별(대개 OFL). 라이선스를 기록한다 | BRD, SITE |
| simple-icons | https://github.com/simple-icons/simple-icons | "works with" 행에 쓰는 타사 로고 | no | Y | CC0이지만 상표권은 남는다 | BRD, SITE |
| CNCF artwork 매트릭스 | https://github.com/cncf/artwork | 산출물 사양 {horizontal,stacked,icon}×{color,black,white}×{svg,png} | no | N | 참조 | BRD |

## 5. Favicon·manifest·OG·소셜 프리뷰 (BRD, SITE)

| 이름 | URL | 용도 | 세션 | 자동화 | 라이선스·비용 | 담당 |
|---|---|---|---|---|---|---|
| Evil Martians favicon 가이드 | https://evilmartians.com/chronicles/how-to-favicon-in-2021-six-files-that-fit-most-needs | 최소 세트: `favicon.ico` 32(세션에서는 16/32/48), `icon.svg`(`prefers-color-scheme`), apple-touch 180, manifest 192/512 + maskable 512 | yes | N | 참조 | BRD |
| W3C Web App Manifest | https://www.w3.org/TR/appmanifest/ | `site.webmanifest`의 `icons[].purpose`, `theme_color` 검증 | yes | Y | 참조 | BRD, SITE |
| maskable.app | https://maskable.app | maskable safe zone(409px 원) 확인 | no | N | 무료 | BRD |
| RealFaviconGenerator checker | https://realfavicongenerator.net | 배포된 사이트의 favicon 점검 | no | P | core MIT | BRD |
| Satori (+ resvg) / `@vercel/og` / Takumi | https://github.com/vercel/satori · https://github.com/kane50613/takumi | 빌드 시 1200×630 OG 이미지 생성 | no | Y | MPL-2.0 / Apache-2.0 | SITE, BRD |
| astro-og-canvas | https://github.com/delucis/astro-og-canvas | Astro 빌드 시 OG 생성 | no | Y | MIT | SITE |
| GitHub social preview (웹 UI) | https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/customizing-your-repositorys-social-media-preview | 1280×640, 1MB 미만. REST가 없으므로 브라우저 에이전트로 업로드한 뒤 GraphQL `usesCustomOpenGraphImage`로 확인한다 | yes | P | 무료 | DSC, BRD |
| opengraph.xyz / LinkedIn Post Inspector / Facebook Sharing Debugger / metatags.io | https://www.opengraph.xyz · https://www.linkedin.com/post-inspector · https://developers.facebook.com/tools/debug/ · https://metatags.io | 카드 렌더링 미리보기와 캐시 갱신 | no | N | 무료(일부 로그인) | SITE |

## 6. 색·대비·접근성 (BRD, SITE)

| 이름 | URL | 용도 | 세션 | 자동화 | 라이선스·비용 | 담당 |
|---|---|---|---|---|---|---|
| WCAG 대비 계산 스크립트 | 자체 | 팔레트의 모든 전경/배경 쌍에 대해 4.5:1 / 3:1 검증 | yes | Y | 자체 | BRD |
| color.js | https://github.com/color-js/color.js | OKLCH 팔레트, WCAG21·APCA `contrast()` | no | Y | MIT | BRD |
| APCA (`apca-w3`) | https://github.com/Myndex/apca-w3 | 지각 대비(참고용). 규범 게이트는 WCAG 2.x | no | Y | 자체 라이선스(NOASSERTION). 번들하기 전에 읽는다 | BRD |
| OKLCH picker / Adobe Leonardo | https://oklch.com · https://github.com/adobe/leonardo | 목표 대비비를 맞춘 색 스케일 | no | P / Y | NOASSERTION / Apache-2.0 | BRD |
| axe-core / pa11y-ci | https://github.com/dequelabs/axe-core · https://github.com/pa11y/pa11y-ci | WCAG 2.2 AA CI 게이트 | no | Y | MPL-2.0 / LGPL | SITE |
| accessibility-agents | https://github.com/Community-Access/accessibility-agents | WCAG 검토 에이전트 11종(흡수 참조) | no | P | 저장소 라이선스 확인 | SITE |

## 7. 사이트 스택·문서 파이프라인 (SITE)

| 이름 | URL | 용도 | 세션 | 자동화 | 라이선스·비용 | 담당 |
|---|---|---|---|---|---|---|
| Astro + Starlight `[U]` | https://astro.build · https://starlight.astro.build | 커스텀 랜딩(`index.astro`)과 Diátaxis 문서. component override, `customCss`, `redirects`, i18n | yes | Y | MIT | SITE |
| Bun `[U]` | https://bun.sh | `bun install/add/run build`, `bunx --bun astro check`, `bun -e`, 스크립트 실행 | yes | Y | MIT | SITE, BRD, MED |
| `@astrojs/sitemap`, `@astrojs/check`, `tsc --noEmit --strict` | https://docs.astro.build | sitemap-index 생성, 사이트와 typed copy 모듈 타입 검사 | yes | Y | MIT | SITE |
| Pagefind | https://pagefind.app | 정적 검색(Starlight 내장) | yes | Y | MIT | SITE |
| Expressive Code | https://expressive-code.com | 코드 블록 테마와 복사 버튼 | yes | Y | MIT | SITE |
| 문서 동기화 스크립트(repo Markdown → site) | 자체 `site/scripts/sync-docs.ts` 류 | 링크 재작성, title/meta 파생. 원본만 고치고 생성물은 고치지 않는다 | yes | Y | 자체 | SITE |
| typed copy 모듈 | 자체 `site/src/data/*.ts` | 랜딩 문자열을 타입이 있는 데이터 계약 하나에 모은다(negations에 evidence 링크 포함) | yes | Y | 자체 | SITE |
| 빌드 시 GitHub 별 수 조회 | `api.github.com/repos/{o}/{r}` | 별 CTA에 표시할 수. 임계값 미만이면 숨기고, 실패하면 조용히 숨긴다 | yes | Y | rate limit | SITE |
| crd-ref-docs / helm-docs | https://github.com/elastic/crd-ref-docs · https://github.com/norwoodj/helm-docs | 생성형 참조 문서(K8s 계열 예시)와 `make docs-check` drift 게이트 | yes | Y | Apache-2.0 / GPL-3.0 | SITE, DSC |
| starlight-llms-txt 등 llms.txt 플러그인 | https://github.com/delucis/starlight-llms-txt | `llms.txt` / `llms-full.txt` 자동 생성 | no | Y | MIT | SITE |
| starlight-links-validator | https://github.com/HiDeoo/starlight-links-validator | 빌드 시 내부 링크 검증 | no | Y | MIT | SITE |
| CDP coverage / LayerTree | Chrome DevTools Protocol | 모바일 성능 인벤토리(미사용 JS/CSS, 레이어) | yes | Y | — | SITE |
| Killercoda scenarios / devcontainers | https://killercoda.com/creators · https://github.com/devcontainers/spec | 가입 없이 5분 안에 써 보는 경로 | no | P | 무료 | SITE, DSC |
| 대안 SSG: Docusaurus / MkDocs Material / VitePress / Hugo+Docsy / Jekyll | https://docusaurus.io · https://squidfunk.github.io/mkdocs-material/ · https://vitepress.dev · https://www.docsy.dev · https://jekyllrb.com | 비교 참조용이다. 기본값은 `[U]` Astro+Starlight이고, 저장소에 이미 사이트가 있으면 먼저 owner에게 묻는다 | no | Y | MIT / Apache-2.0 | SITE |

## 8. 기술 SEO·검증기 (SITE)

| 이름 | URL | 용도 | 세션 | 자동화 | 라이선스·비용 | 담당 |
|---|---|---|---|---|---|---|
| llms.txt spec (v2) | https://llmstxt.org | H1, `>` 요약, H2 링크 목록, `.md` twin, `rel=alternate` | yes | Y | 참조 | SITE |
| schema.org `SoftwareApplication` / `SoftwareSourceCode` / `BreadcrumbList` | https://schema.org/SoftwareApplication | JSON-LD. 가짜 `aggregateRating`은 넣지 않는다 | yes | Y | 참조 | SITE |
| Google Rich Results Test / Schema Markup Validator | https://search.google.com/test/rich-results · https://validator.schema.org | 수동 점검 | no | N | 무료 | SITE |
| sitemaps.org, Google robots/canonical 가이드 | https://www.sitemaps.org/protocol.html · https://developers.google.com/search/docs/crawling-indexing | sitemap, robots, canonical 규칙 | yes | Y | 참조 | SITE |
| Open Graph / X Cards | https://ogp.me · https://developer.x.com/en/docs/x-for-websites/cards | `og:*`, `twitter:card=summary_large_image` | yes | Y | 참조 | SITE |
| lychee + lychee-action | https://github.com/lycheeverse/lychee | 링크 검사. PR에서는 `--offline`, 주간 cron으로 외부 링크까지 | yes | Y | Apache-2.0/MIT | SITE, DSC |
| Nu Html Checker (`vnu`) | https://github.com/validator/validator | `vnu --errors-only dist/` | yes | Y | MIT | SITE |
| htmltest / muffet | https://github.com/wjdp/htmltest · https://github.com/raviqqe/muffet | 빌드 HTML 또는 서빙 중인 사이트의 링크·이미지·alt 검사 | no | Y | MIT | SITE |
| Lighthouse CI / Unlighthouse / PageSpeed Insights | https://github.com/GoogleChrome/lighthouse-ci · https://unlighthouse.dev · https://pagespeed.web.dev | 성능·SEO·a11y 예산 assert(`bunx lhci autorun`) | no | Y | Apache-2.0 / MIT / 무료 API | SITE |
| IndexNow | https://www.indexnow.org | 배포 후 변경 URL ping(Bing 등. Google은 쓰지 않는다) | no | Y | 무료 | SITE |
| AI crawler robots 제어 | https://developers.google.com/search/docs/crawling-indexing/google-common-crawlers · https://platform.openai.com/docs/bots | 검색·AI 봇 허용 여부 확인. CDN 기본값의 "AI bot 차단" 설정을 점검한다 | no | Y | 참조 | SITE |
| head 태그 감사(`curl`, `rg` over `dist/`) | — | 페이지마다 `<title>`·description·canonical·og:image·JSON-LD·manifest가 정확히 하나씩 있는지 | yes | Y | — | SITE |
| sibling-overlap 스캐너 | 자체 Playwright 스크립트 | 여러 폭에서 형제 요소 bounding box 겹침을 회귀 검사한다 | yes | Y | 자체 | SITE |
| `impeccable detect --json` CI | https://impeccable.style | 디자인 anti-pattern 게이트(exit 2 = findings) | yes | Y | Apache-2.0 | SITE |

## 9. 도메인·호스팅·IaC (SITE, DSC)

| 이름 | URL | 용도 | 세션 | 자동화 | 라이선스·비용 | 담당 |
|---|---|---|---|---|---|---|
| GitHub Pages + `actions/configure-pages`·`upload-pages-artifact`·`deploy-pages` | https://github.com/actions/deploy-pages | PR에서 빌드하고 main에서 배포한다. pinned SHA, 최소 권한(`pages: write`, `id-token: write`) | yes | Y | 무료 | SITE |
| Pages API | `gh api -X PUT repos/{o}/{r}/pages -f cname=… -F build_type=workflow` | cname, https_enforced 설정(IaC provider 순서 버그 보완용) | yes | Y | 무료 | SITE |
| GitHub Pages verified domains | https://docs.github.com/en/pages/configuring-a-custom-domain-for-your-github-pages-site | 서브도메인 takeover 방지 | no | P | 무료 | SITE |
| Terraform / OpenTofu + `integrations/github` + DNS provider | https://registry.terraform.io/providers/integrations/github · https://opentofu.org | 저장소 메타, Pages, environment, DNS-only CNAME, Search Console TXT, analytics 토큰 변수. `import`와 `prevent_destroy` 사용 | yes | Y | Terraform BSL / OpenTofu MPL, 원격 state는 유료일 수 있다 | SITE, DSC |
| DNS provider(예: Cloudflare DNS, Route 53) | — | apex/sub CNAME. Pages TLS를 위해 프록시를 끈다 | yes | Y (IaC) | 공급자별 | SITE |
| 대안 호스팅(Cloudflare Pages, Netlify 등) | — | 커스텀 헤더나 리다이렉트가 필요할 때만 | no | Y | 무료 티어 | SITE |
| fine-grained PAT(브라우저에서 권한 추가) | https://github.com/settings/personal-access-tokens | IaC 토큰에 Pages/Admin 권한 부여 | yes | P | 무료 | E2R, SITE |
| `dig`, `curl -I` | — | DNS 전파, 200/404/301, HTTPS 리다이렉트, 인증서 상태 | yes | Y | — | SITE |
| security.txt (RFC 9116) | https://securitytxt.org | `/.well-known/security.txt` | no | Y | 무료 | SITE, DSC |

## 10. Analytics·Search Console 연결 (SITE)

연결과 기준선 수집까지만 이 계열이 맡는다. 주간 리포트 같은 운영은 마케팅 에이전트 몫이다.

| 이름 | URL | 용도 | 세션 | 자동화 | 라이선스·비용 | 담당 |
|---|---|---|---|---|---|---|
| 쿠키 없는 beacon(예: Cloudflare Web Analytics) | https://www.cloudflare.com/web-analytics/ | 방문과 referrer 수집. 빌드 env에 토큰이 있을 때만 삽입한다 | yes | Y | 무료 | SITE |
| GoatCounter / Plausible / Umami | https://www.goatcounter.com · https://plausible.io · https://umami.is | 대안(공개 대시보드, self-host) | no | Y | 무료(비상업) / 유료 또는 AGPL CE / MIT | SITE |
| Google Search Console(Domain property, DNS TXT) | https://search.google.com/search-console | 소유권 확인, sitemap 제출, URL 검사 | yes | P | 무료 | SITE |
| Bing Webmaster Tools | https://www.bing.com/webmasters | GSC에서 가져오기 | no | P | 무료 | SITE |
| GSC API / search-console-mcp / mcp-gsc | https://developers.google.com/webmaster-tools · https://github.com/saurabhsharma2u/search-console-mcp · https://github.com/AminForou/mcp-gsc | 읽기 전용 쿼리 데이터로 title/meta를 반복 개선 | no | Y | 무료 / MIT | SITE, POS |
| GitHub Traffic API | https://docs.github.com/en/rest/metrics/traffic | views, clones, referrers, paths 기준선. 14일만 보존된다. 주기 보관에 추가 토큰이 필요하면 owner 승인을 받는다 | yes | Y | 무료, push 권한 | SITE, E2R |
| GitHub stargazers API | `application/vnd.github.star+json` | 별 기준선(시각 포함) | yes | Y | 무료 | E2R |
| GHCR 패키지 페이지 | https://github.com/features/packages | "Total downloads" 기준선(REST에 카운터가 없다) | yes | P | 무료 | E2R |
| star-history 임베드 / repobeats | https://star-history.com · https://repobeats.axiom.co | README 활동 카드(선택 사항, 과장 금지) | no | P | 무료 | DSC |

## 11. 데모 캡처·인코딩 (MED)

| 이름 | URL | 용도 | 세션 | 자동화 | 라이선스·비용 | 담당 |
|---|---|---|---|---|---|---|
| Playwright `recordVideo` / screenshot | https://playwright.dev | 웹 UI와 랜딩의 재현 가능한 캡처, before/after | yes | Y | Apache-2.0 | MED, SITE |
| ffmpeg / ffprobe | https://ffmpeg.org | x11grab, VP9 2-pass WebM, H.264 `+faststart` MP4, WebP/poster, per-frame pts 검증, contact sheet | yes | Y | LGPL/GPL(빌드별) | MED |
| 인코딩 스크립트(`encode.sh` 류) | 자체 | 포맷과 크기 규칙 `[U]`을 한 곳에서 적용 | yes | Y | 자체 | MED |
| VHS | https://github.com/charmbracelet/vhs | CLI/TUI용 `.tape` 스크립트 녹화(MP4/WebM/GIF). ttyd와 ffmpeg가 필요하다 | no | Y | MIT | MED |
| asciinema + agg + player | https://github.com/asciinema/asciinema · https://github.com/asciinema/agg | 실제 세션 녹화, 문서 사이트용 복사 가능한 플레이어 | planned | Y | GPL-3.0 / Apache-2.0 | MED |
| terminalizer / charm freeze / termshot | https://github.com/faressoft/terminalizer · https://github.com/charmbracelet/freeze · https://github.com/homeport/termshot | 터미널 녹화, 정지 이미지 | no | Y | MIT | MED |
| gifski / gifsicle | https://gif.ski · https://github.com/kohler/gifsicle | 영상을 재생할 수 없는 곳에 쓸 GIF 폴백 | no | Y | **AGPL-3.0** / GPL-2.0 | MED |
| Pillow APNG | https://python-pillow.org | GIF보다 나은 폴백 애니메이션 | yes | Y | HPND | MED |
| 헤드리스 데스크톱 세션(Wayland compositor 헤드리스 모드, compositor 스크립트, `xdotool`, Xvfb, `notify-send`) | 배포판 패키지 | 데스크톱 GUI 앱의 스크립트 녹화 | yes | Y | GPL 계열 | MED |
| wf-recorder / Spectacle / OBS (obs-websocket) / grim | https://github.com/ammen99/wf-recorder · https://apps.kde.org/spectacle/ · https://obsproject.com | Linux 데스크톱 캡처 대안 | no | P | GPL/MIT | MED |
| Docker(대상 배포판 컨테이너) | https://www.docker.com | 깨끗한 환경의 빌드와 헤드리스 캡처 | yes | Y | 무료(Desktop은 조건부 유료) | MED, DSC |
| 하드웨어 인코더 경로 | 공급자별(VA-API, 벤더 MPP 등) | 이미 있는 HW 인코딩 경로를 재사용해 캡처 시간을 줄인다 | yes | Y | — | MED |
| libfaketime | https://github.com/wolfcw/libfaketime | 캡처 타이밍 조작 시도 | rejected | — | GPL-2.0 | MED |
| llvmpipe 진단 | Mesa | 소프트웨어 렌더링 탓에 fps가 떨어지는지 원인 확인 | yes | Y | MIT | MED |
| GitHub-hosted video(README/issue 첨부 URL) | https://docs.github.com | README 인라인 영상 `[U]`. 옆에 정지 PNG를 둔다 | yes | P | 무료, 크기 제한 | MED, DSC |
| Remotion / Motion Canvas | https://www.remotion.dev · https://motioncanvas.io | 프로그래밍 방식 영상(트레일러) | no | Y | Remotion은 기업 유료 / MIT | MED |

## 12. 도식 (SITE, MED)

| 이름 | URL | 용도 | 세션 | 자동화 | 라이선스·비용 | 담당 |
|---|---|---|---|---|---|---|
| Mermaid / mermaid-cli (`mmdc`) | https://github.com/mermaid-js/mermaid-cli | README 아키텍처 도식(GitHub 인라인 렌더) | yes (보고서) | Y | MIT | SITE, DSC |
| D2 | https://d2lang.com | 문서 사이트용 고급 도식. SVG를 커밋한다 | no | Y | MPL-2.0 (TALA 레이아웃은 독점) | SITE |
| Excalidraw (+ export CLI / MCP) | https://github.com/excalidraw/excalidraw | 손그림 스타일 | no | P | MIT (MCP는 라이선스 미표기) | SITE |
| Kroki / PlantUML / svgbob | https://github.com/yuzutech/kroki | 여러 도식 언어를 하나의 HTTP API로 렌더 | no | Y | MIT / LGPL / Apache | SITE |

## 13. README·저장소 표면 (DSC)

| 이름 | URL | 용도 | 세션 | 자동화 | 라이선스·비용 | 담당 |
|---|---|---|---|---|---|---|
| `gh repo edit` / `gh api -X PUT …/topics` | https://cli.github.com | description, homepage, topics(최대 20개, 소문자·하이픈) | yes | Y | 무료 | DSC |
| GitHub GraphQL `usesCustomOpenGraphImage`, `openGraphImageUrl` | https://docs.github.com/en/graphql | social preview 적용 여부 검증 | yes | Y | 무료 | DSC |
| `gh api repos/{o}/{r}/community/profile` | https://docs.github.com/en/rest/metrics/community | Community Standards 완성도 | no | Y | 무료 | DSC |
| PVR / Discussions API | `PUT …/private-vulnerability-reporting` · `PATCH repos/{o}/{r} -f has_discussions=true` | 보안 신고 경로, 피드백 표면 | no | Y | 무료 | DSC |
| 깨끗한 환경 install 검증 | Docker, `uv tool install`/`uvx` 새 프로필, kind + `kubectl apply --dry-run=server`, `helm template/show/lint` | README install 계약을 글자 그대로 실행한다 | yes | Y | 무료 | DSC |
| standard-readme spec | https://github.com/RichardLitt/standard-readme | 섹션 순서, 120자 미만 짧은 설명 = 패키지 description = About | no | Y (lint) | MIT | DSC |
| Make a README / awesome-readme / GitHub About READMEs | https://www.makeareadme.com · https://github.com/matiassingers/awesome-readme · https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-readmes | 구조 참조, 상대 링크, 500KiB 절단 | no | N | 참조 | DSC |
| readme-ai | https://github.com/eli64s/readme-ai | AI README 생성기. 결과가 획일적이라 쓰지 않는다(참고만) | no | Y | MIT | DSC |
| Contributor Covenant, issue forms, PR template | https://www.contributor-covenant.org | community health 파일 | no | Y | CC-BY-4.0 | DSC |
| all-contributors / goodfirstissue.dev | https://github.com/all-contributors/all-contributors · https://goodfirstissue.dev | 기여자 인정, `good first issue` 노출 | no | P | MIT / 무료 | DSC |
| CITATION.cff + cffconvert / Zenodo | https://github.com/citation-file-format/cffconvert · https://help.zenodo.org/docs/github/ | "Cite this repository", 릴리스별 DOI | no | Y | Apache-2.0 / 무료 | DSC |
| FUNDING.yml | https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/displaying-a-sponsor-button-in-your-repository | Sponsor 버튼. 쓸지 말지는 owner가 정한다 | no | Y | 무료 | DSC |
| 배지 엔드포인트(shields.io, pkg.go.dev badge, Repology, Scorecard) | https://shields.io · https://repology.org | 신뢰 신호. 사실만 담고 너무 많이 달지 않는다 | partly | Y | 무료 | DSC |

## 14. 레지스트리·스토어 메타데이터와 검증기 (DSC)

레지스트리 메타데이터는 이 계열이 준비한다. 외부 등록 PR이나 제출을 할지는 owner가 정한다.

| 이름 | URL | 용도 | 세션 | 자동화 | 라이선스·비용 | 담당 |
|---|---|---|---|---|---|---|
| pkg.go.dev + `GOPROXY=proxy.golang.org go list -m <mod>@<ver>` | https://pkg.go.dev | 인덱싱 트리거, 404→200 확인 | yes | Y | 무료 | DSC |
| google/licensecheck | https://github.com/google/licensecheck | pkg.go.dev "License UNKNOWN" 진단(일치율). 라이선스 본문 수정은 owner 승인이 필요하다 | yes | Y | BSD-3 | DSC |
| Go Report Card | https://goreportcard.com | 품질 배지. 새로고침 후 캡처한다 | no | Y | 무료 | DSC |
| `go build ./...`, `make generate`, module path 재생성 | — | 모듈 경로 변경 후 재생성과 검증 | yes | Y | — | DSC |
| PyPI: `uv build`, `twine check`, `pypa/gh-action-pypi-publish`(OIDC) | https://docs.pypi.org/trusted-publishers/ | long_description 렌더, 신뢰 게시, `project.urls` 표준 라벨 | yes | Y | 무료 | DSC |
| npm: `npm pkg fix`, `--provenance` | https://docs.npmjs.com | `repository`·`keywords`·provenance 배지(npm 패키지 프로젝트에 한한다) | no | Y | 무료 | DSC |
| crates.io: `cargo publish`, keywords ≤5, categories | https://doc.rust-lang.org/cargo/reference/manifest.html | Rust 크레이트 메타 | no | Y | 무료 | DSC |
| Artifact Hub: `artifacthub-repo.yml` + `oras push …:artifacthub.io`, `Chart.yaml` `artifacthub.io/*` annotations, 검색 API | https://artifacthub.io/docs | Helm/operator 목록, verified publisher, category, links, license | yes | Y | 무료 | DSC |
| `helm lint/template/show`, OCI chart on GHCR | https://helm.sh | 차트 설치 문서 검증 | yes | Y | Apache-2.0 | DSC |
| OperatorHub: `operator-sdk bundle validate`, scorecard | https://operatorhub.io | OLM 번들 CSV annotations | no | Y | Apache-2.0 | DSC |
| Krew index + `krew-release-bot` | https://github.com/kubernetes-sigs/krew-index | kubectl 플러그인 manifest(`shortDescription` ≤50자) | no | Y | Apache-2.0 | DSC |
| Flathub: `appstreamcli validate --pedantic`, `desktop-file-validate`, `flatpak-builder-lint` | https://docs.flathub.org/docs/for-app-authors/metainfo-guidelines/quality-guidelines | AppStream 품질 기준: 이름 ≤15–20자, summary 10–35자, light+dark 브랜드 색, 256px 이상 아이콘, 스크린샷 3–6장, OARS. ⚠ Flathub은 에이전트가 제출 PR을 열거나 자동화하는 것을 금지한다 | yes (appstreamcli·desktop-file-validate) | Y (검증) / N (제출) | 무료 | DSC |
| 앱 메타데이터(예: `KAboutData`, `ecm_install_icons`, `.desktop` 키) | 프레임워크 문서 | 앱 내부 About/homepage/bug URL, 아이콘 설치 | yes | Y | — | DSC, BRD |
| KDE Store / OCS API | https://www.opendesktop.org/ocs-api/ | Plasma "Get New…" 안에서의 발견성 | no | P | 무료 | DSC |
| AUR: `PKGBUILD` + `makepkg --printsrcinfo`(Arch 컨테이너), AUR RPC | https://wiki.archlinux.org/title/AUR_submission_guidelines | keywords, url, description | yes | Y | 무료 | DSC |
| Fedora COPR: `copr-cli`, API v3 | https://copr.fedorainfracloud.org | description, instructions, homepage | yes | Y | 무료 | DSC |
| OBS: `osc meta prj/pkg` | https://openbuildservice.org | 프로젝트와 패키지의 title/description/url | yes | Y | 무료 | DSC |
| Launchpad PPA(웹 + API) | https://launchpad.net | PPA description과 링크. 로그인은 사람이 한다 | yes | P | 무료 | DSC |
| endoflife.date / 배포판 series API / Repology | https://endoflife.date · https://repology.org | 배포판 대상 자동 추적, 배포 현황 배지 | yes (endoflife) | Y | 무료 | DSC |
| Homebrew: own tap, `brew bump-formula-pr` | https://docs.brew.sh/Acceptable-Formulae | formula `desc`/`homepage`/`license` | no | Y | 무료 | DSC |
| Snapcraft | https://snapcraft.io/docs | `snapcraft.yaml` summary/description/icon | no | Y | 무료 | DSC |
| 공식 MCP Registry: `mcp-publisher`, `server.json`, `mcpName`/`mcp-name:` | https://github.com/modelcontextprotocol/registry | 인증에 묶인 네임스페이스(`io.github.<user>/…`, 도메인). fork가 먼저 점유했는지 확인한다 | no | Y | 무료, preview 단계 | DSC |
| Smithery / Glama / PulseMCP / mcp.so / Docker MCP registry | https://smithery.ai · https://glama.ai/mcp/servers · https://www.pulsemcp.com · https://mcp.so · https://github.com/docker/mcp-registry | MCP 디렉터리 메타(server card, 아이콘 ≤1MB, 클레임) | no | P | 무료 | DSC |
| VS Code Marketplace `vsce` / Open VSX `ovsx` | https://code.visualstudio.com/api/working-with-extensions/publishing-extension · https://open-vsx.org | 확장 메타. SVG 아이콘은 쓸 수 없다 | no | Y | 무료. Azure PAT 폐지 일정을 확인한다 | DSC |
| OCI image labels / `peter-evans/dockerhub-description` | https://specs.opencontainers.org/image-spec/annotations/ | `org.opencontainers.image.*`, Hub README 동기화 | no | Y | 무료 | DSC |

## 15. 신뢰 신호 (DSC)

| 이름 | URL | 용도 | 세션 | 자동화 | 라이선스·비용 | 담당 |
|---|---|---|---|---|---|---|
| OpenSSF Scorecard + scorecard-action | https://github.com/ossf/scorecard-action | 주간 점수와 README 배지 | no | Y | Apache-2.0 | DSC |
| OpenSSF Best Practices badge | https://www.bestpractices.dev | 자기 인증. 기준 자체가 준비도 체크리스트다 | no | P | 무료 | DSC |
| security-insights + si-tooling / OSPS Baseline scanner | https://github.com/ossf/security-insights · https://baseline.openssf.org | 기계가 읽는 보안 태세 파일 | no | Y | Apache-2.0 | DSC |
| cosign / syft / `actions/attest` / slsa-github-generator / GoReleaser | https://github.com/sigstore/cosign · https://github.com/anchore/syft · https://github.com/actions/attest · https://github.com/goreleaser/goreleaser | 서명, SBOM, provenance(릴리스 워크플로가 소유한다) | partly | Y | Apache-2.0 / MIT | DSC |
| REUSE tool / ScanCode | https://github.com/fsfe/reuse-tool · https://github.com/aboutcode-org/scancode-toolkit | 파일 단위 라이선스, 라이선스 검출 | no | Y | GPL-3 / Apache-2.0 | DSC |
| choosealicense / licensee(GitHub 검출) | https://choosealicense.com | SPDX 원문 그대로 둬야 검출된다 | yes | Y | 무료 | DSC |
| CLOMonitor linter / repolinter | https://github.com/cncf/clomonitor · https://github.com/todogroup/repolinter | 저장소 표면 완성도를 한 번에 보는 메타 게이트 | no | Y | Apache-2.0 | DSC |
| 가짜 별 연구(StarScout, arXiv 2412.13459) | https://arxiv.org/abs/2412.13459 | 근거 자료: 별을 사거나 조작하지 않는다(GitHub AUP 위반) | no | N | 참조 | DSC, SITE |

## 16. 일관성 게이트·CI (DSC 소유, E2R 최종 감사)

| 이름 | URL | 용도 | 세션 | 자동화 | 라이선스·비용 | 담당 |
|---|---|---|---|---|---|---|
| 포지셔닝 원본(`positioning.yml`, 기존 저장소 관례가 있으면 그것) | POS 참조 | tagline, About description, registry description, keywords, topics의 단일 원본 | yes | Y | 자체 | POS → DSC |
| 일관성 검사 스크립트 + workflow(`check_docs_seo.py`·`docs-seo.yml` 류) | 자체 | 원본 → README, 사이트 meta, About, 매니페스트 동등성. 버전 동기화 `--check` | yes | Y | 자체 | DSC |
| `make docs-gen` + `git diff --exit-code` | 자체 | 생성 문서 drift 게이트 | yes | Y | — | DSC, SITE |
| `dorny/paths-filter`(fail-closed) | https://github.com/dorny/paths-filter | 변경 감지. 감지 실패 시 무거운 잡을 건너뛰지 않고 돌린다 | yes | Y | MIT | DSC |
| actionlint | https://github.com/rhysd/actionlint | workflow lint | yes | Y | MIT | DSC |
| YAML/JSON-schema 예제 검증(`js-yaml`, `python -c yaml`, CRD schema) | — | 문서 예제를 실제 스키마로 검증 | yes | Y | — | DSC, SITE |
| clang-format, ctest, `rpmspec`, `node --check` 등 저장소 게이트 | — | PR 전 저장소 자체 게이트 | yes | Y | — | DSC |
| 라이브 "every surface in place" 감사(`curl`, `gh repo view --json`, 레지스트리 API) | — | 기억이 아니라 실제 상태를 다시 확인한다 | yes | Y | — | E2R |

## 제외 (마케팅 에이전트 몫)

HN/Reddit/Lobsters/Product Hunt 제출, dev.to Forem API, Hashnode GraphQL, Medium, Bluesky AT Protocol, Mastodon API, X API, Composio 소셜 커넥터(twitter-algorithm-optimizer, hashnode-automation 등), Slack 승인 브리지·게시 dispatcher·스냅샷 cron 런타임, UTM 빌더, 뉴스레터/CFP 제출 폼, awesome-list·AlternativeTo·OpenHub·Libhunt·Wikidata 등록, `awesome-lint`(자기 목록 운영), 보도자료·팩트시트 스킬, 릴리스 노트 도구(git-cliff, release-please; 릴리스 프로세스 소유).
