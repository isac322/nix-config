# Media specs by surface

`SKILL.md` MED-04~MED-06, MED-26~MED-29의 표면별 세부. 값은 세션에서 기록한 규격과 공개 문서에서 온 것이며, `[verify]` 표시는 제출 전 해당 문서에서 다시 확인해야 하는 값이다. 규격은 바뀌므로 제출 직전 공식 문서를 다시 연다. 로고·아이콘·OG·소셜 프리뷰·릴리스 배너 **디자인**은 `isac-brand-identity`가 소유하고, 여기서는 데모 미디어가 그 규격과 충돌하지 않도록 참고용으로만 적는다.

## 1. 마스터와 공통 렌디션

| 항목 | 기본값 | 근거·메모 |
|---|---|---|
| 영상 마스터 | 2560×1280(2:1), 60 fps CFR, 무손실 중간 포맷(`.mkv` + Ut Video/FFV1) | 커밋하지 않음(MED-28). 스크립트로 재생성 |
| 웹 클립 | WebM(VP9 또는 AV1) + MP4(H.264 `yuv420p`, `+faststart`), 무음 | 파일당 ≤ 2 MB 목표. 초과 시 CRF 사다리 → 그래도 넘으면 길이·해상도 선택지 보고 |
| 모바일 변형 | 1280 px 폭 | 모바일에서 2560 원본 디코드 금지 |
| poster | WebP(또는 PNG), **표시 크기**에 맞춤 | 썸네일 타일에 2560 poster를 쓰면 수 배 과대. 타일 크기별로 따로 생성 |
| 스틸 | PNG, `oxipng` 무손실 압축 | README·스토어 공용 |
| GIF/APNG | 폭 ≤ 800 px, 12–20 fps, 짧게(≤ 10 s) | 영상 불가 표면 전용(MED-06). 같은 마스터에서 파생 |
| 루프 | 첫 프레임 = 끝 프레임 상태 | 컨택트 시트로 확인(MED-20) |
| 사이트 삽입 | `<video muted loop playsinline preload="none" poster>` + `<source type="video/webm">` → `<source type="video/mp4">` | reduced-motion이면 poster만. 한 번에 하나만 재생·디코드(갤러리 정책은 `isac-project-site`) |

## 2. 표면별 표

| 표면 | 영상 재생 | 권장 미디어 | 규격·제한 | 메모 |
|---|---|---|---|---|
| GitHub README | 업로드된 영상만 (`user-attachments` URL 한 줄 단독) | 영상 + 커밋된 스틸 PNG [U] | 업로드 형식 `.mp4`/`.mov`/`.webm`; 크기 한도는 요금제별 [verify] | 저장소에 커밋한 `.mp4`를 `<video>`로 넣어도 재생되지 않음 [verify]. 스틸은 상대 경로 가능 |
| GitHub PR 본문 (before/after, MED-30) | 업로드된 영상 | before/after 영상 또는 PNG 쌍 + 캡션 | README와 동일 | 같은 캡처 스크립트로 두 SHA를 찍음 |
| 프로젝트 사이트 (hero, 기능 갤러리) | 가능 | WebM + MP4 + poster [U] | §1 공통값 | 로딩·레이아웃은 `isac-project-site` |
| 릴리스 페이지 | 업로드된 영상 | 기능 클립, 배너 | 배너 1280×320 (세션 채택값) | 배너 디자인은 `isac-brand-identity` |
| PyPI (README 렌더) | 불가 | 스틸 PNG, 필요 시 GIF | 이미지 URL은 **절대 HTTPS** (상대 경로 깨짐) | README 변경은 다음 릴리스에서만 반영 |
| npm (README 렌더) | 불가 | 스틸 PNG, 필요 시 GIF | 절대 HTTPS URL | |
| pkg.go.dev (README 렌더) | 불가 | 스틸 PNG | 절대 URL 권장 [verify] | 라이선스 미검출 시 README 자체가 숨겨짐(`isac-discovery-surfaces`) |
| crates.io / docs.rs | 불가 | 스틸 PNG | 절대 URL | |
| Artifact Hub | 불가 | 스크린샷 | `Chart.yaml`의 `artifacthub.io/screenshots` 주석(title + url) | 주석은 YAML 문자열 안의 YAML — 검증 필수. 메타데이터 필드는 `isac-discovery-surfaces` |
| Flathub / AppStream metainfo | AppStream은 `<screenshot>` 안 `<video>` 허용(WebM, VP9/AV1) [verify]; 스토어별 표시 여부 상이 | 스틸 스크린샷 3–6장 + 캡션 | 16:9, 최소 폭 624 px(기본 1600×900 또는 1920×1080 권장), 창 그림자 없음, 첫 장이 `type="default"` | URL은 공개 raw URL이므로 머지 후에만 유효(MED-29). `appstreamcli validate --pedantic`; Flathub 품질 가이드 통과 여부 확인 |
| KDE Store (OCS) | 영상 링크 가능 [verify] | 스크린샷 | 1920×1080, 장당 ≤ 5 MB, 최대 10장 (세션 기록값) | 로고는 `isac-brand-identity` |
| Snap Store | 외부 영상 링크 [verify] | 스크린샷 + 영상 링크 | [verify] | |
| VS Code Marketplace / Open VSX | 불가 | PNG/GIF | README 이미지 HTTPS 필수, 신뢰 제공자 외 SVG 불가 | |
| Homebrew / AUR / COPR / OBS / Launchpad | 없음 | — | 미디어 필드 없음; 홈페이지 링크로 사이트 미디어 연결 | 설명·아이콘 규격은 `isac-discovery-surfaces`·`isac-brand-identity` |
| MCP 레지스트리·디렉터리 | 대부분 없음 | — | 대개 README에서 파생; 아이콘 업로드만 있는 곳이 많음 | README 스틸이 곧 목록 미디어가 되므로 README 스틸 품질이 중요 |
| GitHub social preview / OG 이미지 | — | (브랜드 자산) | 1280×640 < 1 MB / 1200×630 | `isac-brand-identity` 소유. 데모 스틸을 재사용할 때도 거기서 합성 |

- 표에 없는 표면은 해당 스토어·레지스트리의 공식 문서에서 비율·최소 해상도·개수·용량·형식·캡션 규칙을 확인해 행을 추가하고, 확인하지 못한 값은 `[verify]`로 둔다.
- 레지스트리가 README를 렌더링하는 경우, README에 둔 스틸이 곧 그 레지스트리의 미디어다. 절대 URL 여부를 그 렌더러 기준으로 확인한다.

## 3. 제품 유형별 샷 기본 구성

| 유형 | hero 클립 | 기능 클립 | 스틸 |
|---|---|---|---|
| 데스크톱 GUI | 시그니처 상호작용 5–10 s 루프 | 셀링 포인트당 1개 | 기본 화면, 설정 화면(실제 키만, MED-24), 스토어 규격 스틸 |
| 웹 UI·서비스 | 핵심 흐름 1개 | 주요 화면 전환 | 대시보드·결과 화면 |
| CLI·TUI | 설치 → 첫 명령 → 결과 | 대표 서브커맨드 | 출력 화면(텍스트 코드 블록과 짝) |
| 라이브러리 | (선택) REPL·스트리밍 출력 | — | 코드 스니펫 카드 + 실제 출력 카드 |
| K8s operator·controller | apply → 상태 변화 → 결과 확인 | CR별 동작 | 리소스 상태·결과 화면 |
| MCP·AI 도구 서버 | 도구 호출 + 실제 효과 한 화면 | 도구별 1개 | 도구 목록, 호출 결과 |

## 4. 캡션과 접근성

- 모든 스틸·poster에 대체 텍스트를 둔다. 대체 텍스트는 "무엇을 하는 장면인지"를 적고, 포지셔닝의 `anti_claims`에 걸리는 표현을 쓰지 않는다.
- 스토어 캡션·README 캡션은 owned-surface 문구다. 문체는 `writing-clearly-and-concisely`, `humanizer`를 따르고 사실은 포지셔닝 원본에서만 가져온다.
- 컷이나 배속이 있으면 캡션에 표시한다(capture-pipelines §6).
- 깜빡임·빠른 섬광이 없게 한다(초당 3회 이하).

## Sources

- Flathub quality guidelines — https://docs.flathub.org/docs/for-app-authors/metainfo-guidelines/quality-guidelines
- AppStream metadata (screenshots, video) — https://www.freedesktop.org/software/appstream/docs/chap-Metadata.html
- GitHub attaching files — https://docs.github.com/en/get-started/writing-on-github/working-with-advanced-formatting/attaching-files
- Artifact Hub Helm annotations — https://artifacthub.io/docs/topics/annotations/helm/
- VS Code publishing (README image rules) — https://code.visualstudio.com/api/working-with-extensions/publishing-extension
- KDE Store / OCS — https://www.opendesktop.org/ocs-api/
- WCAG 2.2 three flashes — https://www.w3.org/WAI/WCAG22/Understanding/three-flashes-or-below-threshold.html
