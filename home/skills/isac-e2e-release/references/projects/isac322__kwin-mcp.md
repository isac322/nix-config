# isac322/kwin-mcp release profile

`isac-e2e-release`의 kwin-mcp 프로젝트 문서다. 각 칸은 저장소 안의 위치(파일·제목)나 매 run 다시 계산할 질의만 담는다. 개수·버전·PR 번호·실행 id·소요 시간 같은 구체 값은 `## Cases`에 날짜와 함께만 둔다. 이 문서는 기본값을 좁히거나 구체화만 하고 `[U]` 규칙과 전역 가드를 완화하지 않는다. 질의 결과와 이 문서가 다르면 질의 결과를 따르고 차이를 ledger에 적는다.

## Sources of truth

먼저 읽는 순서다. 저장소 하네스의 릴리스 단계와 노트 규칙이 이 문서와 직전 릴리스보다 우선한다(E2V-04).

- `.claude/skills/release-notes/SKILL.md`: 저장소 릴리스 노트 스킬. "Step 1.5: Verify plugin manifests + bundled SKILL.md are in sync", "Step 2: Determine Release Type", "Step 3: Generate Release Notes"(Minor+ / Patch 템플릿, New Tools 표), "Step 4: SEO Rules for Release Notes"(도구 개수가 바뀔 때 함께 고칠 파일 목록), "Step 5: Present for Review".
- `CLAUDE.md`: "CHANGELOG.md Rules", "GitHub Release Notes Rules", "Pre-work Checklist"(게이트 명령, docs-seo 트리거 표), "Common Commands".
- `CONTRIBUTING.md`: "Complete Docker End-to-End Proof", "Documentation Consistency Check", "Pull Request Process"(버전 bump·도구 목록 변경 시 동기화 스크립트 단계).
- `docker/README.md`: "Reproducibility", "Arch Linux variant", "Fedora and openSUSE Tumbleweed variants", "Commands", "Test-file inventory", "Visual pixel oracles", "Evidence layout", "Screenshot backends and exact-virtual limitation".
- `README.md`: "Quick Start", "System Requirements"("Installing System Dependencies"), "Installation", "Available Tools", "Limitations".
- `.github/workflows/ci.yml`, `.github/workflows/e2e.yml`, `.github/workflows/docs-seo.yml`: 실제로 CI가 돌리는 명령과 트리거.
- `.claude/agents/docs-seo.md`: 문서 갱신 판단 에이전트(Claude Code 전용). 다른 하네스에서는 `scripts/check_docs_seo.py` 결과와 트리거 표를 직접 대조한다.

## Releasable units

- **`kwin-mcp` (PyPI 패키지)**
  - 직전 릴리스 질의: `gh api repos/isac322/kwin-mcp/releases/latest --jq '{tag_name,draft,prerelease}'`와 `https://pypi.org/pypi/kwin-mcp/json`의 `.info.version`. 둘이 다르면 차이를 ledger에 적고 PyPI를 게시 기준으로 삼는다.
  - 과거 태그 패턴(필터로만 사용): `v*` (`ci.yml`의 `on.push.tags`).
  - 버전 파일: `pyproject.toml`의 `[project] version`. `src/`에는 버전 문자열이 없다(`server.py`가 `importlib.metadata.version`으로 읽는다). 플러그인 매니페스트의 버전은 `scripts/sync_plugin_version.py`가 같은 값으로 맞춘다. 대상 파일 목록은 release-notes 스킬 "Step 1.5"와 `CONTRIBUTING.md` "Pull Request Process"에서 읽는다.
  - bump owner: agent. bot_pr_ci: 해당 없음(bump 봇 없음).
  - 버전 신호 힌트: 0.x 구간에서 수정만이면 patch, 도구 추가 같은 additive 변경이면 minor로 제안한다. 클라이언트가 보는 breaking 변경(버전 근거의 `제거·이름 변경` 또는 `형식·동작 변경` 칸)이 하나라도 있으면 버전을 정하지 않고 `## Overrides`의 E2V-35에 따라 사용자에게 묻는다. 근거는 E2V-11 방식으로 만들고, 저장소 기준은 release-notes 스킬 "Step 2: Determine Release Type"을 본다.
- **npm 플러그인 패키지 (unit 여부를 매 run 판정)**: `integrations/opencode/plugin/package.json`이 npm 패키지 이름과 버전을 갖는다. 0단계에서 (1) `.github/workflows/`에 이 패키지를 게시하는 job이 있는지, (2) npm 레지스트리의 `dist-tags.latest`(`https://registry.npmjs.org/<패키지 이름, / 는 %2f>`)와 PyPI 최신 버전을 비교해 ledger에 적는다. 게시 workflow가 있으면 releasable unit으로 다루고 E2V-06을 적용한다. 없고 레지스트리 버전이 이번 릴리스와 따로 움직이면 이 run의 게시 대상이 아니라 미게시 채널로 보고한다. 이 두 결과로도 게시 책임이 정해지지 않을 때만 사용자에게 묻는다(E2V-03).

## Release procedure

우선순위: 저장소 하네스(`.claude/skills/release-notes`, `CONTRIBUTING.md`, `CLAUDE.md`)에 있는 단계가 이 절보다 먼저다. 이 절은 저장소에 아직 없는 단계만 담는다.

- 직전 릴리스 PR 검색 키: `gh pr list --repo isac322/kwin-mcp --state merged --search '"prepare kwin-mcp" in:title' --limit 1 --json number,title,files`. 릴리스 PR의 파일 집합과 diff 모양은 이 PR에 버전 변경만 더한 것과 같아야 한다(E2V-32). PR 제목 규약도 이 PR에서 읽는다(제목을 검사하는 외부 required context가 있다).
- 스크립트·일관성 검사: `python3 scripts/sync_plugin_version.py`, `python3 scripts/sync_plugin_version.py --check`, `python3 scripts/check_docs_seo.py`. `check_docs_seo.py`의 도구 개수 검사는 `server.py`의 `@_tool(` 개수와 `TOOL_COUNT_CANONICAL`만 비교한다. 나머지 파일(release-notes "Step 4"의 목록)은 직접 읽어 맞는지 확인한다.
- lockfile: 도구는 uv. 고정 버전은 `docker/*.Dockerfile`의 `uv-bin` 단계(`ghcr.io/astral-sh/uv` digest pin)에만 있고, `ci.yml`의 `astral-sh/setup-uv`는 uv 버전을 고정하지 않는다. `uv.lock` 헤더 메타데이터는 base 브랜치와 같아야 한다. 다르면 이유와 그 lock을 만든 도구·버전을 적는다. `ghcr.io/astral-sh/uv` 이미지는 셸과 Python이 없는 distroless라 단독 실행 lock 생성기로 쓰기 어렵다. 빌드한 e2e 이미지 안의 고정 uv를 쓴다. 손 편집은 리뷰어에게 공개한 deviation일 때만 허용한다(E2V-32, E2V-29).
- 태그 형식·서명 확인: 형식은 직전 태그에서 읽는다(`git cat-file -p <직전 태그>`). 서명 설정은 `git config gpg.format`, `git config user.signingkey`로 확인하고, push 전에 `git tag -v <태그>`를 별도 명령으로 실행해 결과를 확인한다(E2V-38, E2V-39).
- 게시 트리거와 workflow: `v*` 태그 push가 `ci.yml`을 돌리고, `publish` job(`needs: [lint, type-check, build]`, environment `pypi`, OIDC, `pypa/gh-action-pypi-publish`)이 PyPI에 올린다. environment 보호 규칙 질의: `gh api repos/isac322/kwin-mcp/environments/pypi --jq .protection_rules`. 규칙이 비어 있으면 태그 push가 곧 무인 게시이므로 G-PUB 단언을 태그 push 전에 끝낸다. `e2e.yml`은 태그에서 돌지 않는다. 태그 시점의 E2E 증거는 태그 대상 트리와 같은 트리의 마지막 green head에서 가져온다(E2V-37).
- 채널별 "게시됨" 질의: `https://pypi.org/pypi/kwin-mcp/<버전>/json`의 `.urls[].packagetype`에 wheel(`bdist_wheel`)과 `sdist`가 모두 있어야 한다. publish run 완료 관찰: `gh run list --repo isac322/kwin-mcp --workflow CI --branch <태그>`.
- 릴리스 객체 단계: PyPI 확인 뒤 `gh release create <태그> --verify-tag --title <태그> --notes-file <노트 파일>`. 생성 뒤 `gh api repos/isac322/kwin-mcp/releases/latest`로 최신 릴리스가 새 태그인지 확인한다.

1. 최신 `main`에서 릴리스 브랜치를 만든다. PR 제목은 직전 릴리스 PR과 같은 형식으로 쓴다.
2. `pyproject.toml`의 `[project] version`을 바꾼다.
3. `CHANGELOG.md`: `## [Unreleased]` 아래 항목을 `## [X.Y.Z] - YYYY-MM-DD` 절로 옮기고 빈 `## [Unreleased]`를 남긴다. 파일 끝의 비교 링크에서 `[Unreleased]`를 고치고 `[X.Y.Z]`를 더한다(`CLAUDE.md` "CHANGELOG.md Rules").
4. `python3 scripts/sync_plugin_version.py` 뒤 `--check`.
5. 고정 uv로 `uv.lock`을 다시 만들고 헤더가 base와 같은지 본다(위 lockfile 항목).
6. `python3 scripts/check_docs_seo.py`.
7. 파일 집합을 직전 릴리스 PR과 비교하고 차이를 PR 본문에 설명한다.
8. 머지 뒤 G-PUB: 태그 대상 커밋의 트리와 ancestry를 단언하고, 서명된 annotated tag를 만들고, `git tag -v`, push, publish run 완료, PyPI 질의, `gh release create --verify-tag`를 각각 별도 명령으로 실행해 하나가 실패하면 멈춘다.

## Baseline recipe

- 실체화 override(E2V-07): 차등 QA의 기준선은 공개 산출물 대신 직전 태그에서 다시 빌드한 e2e 이미지다. 이유: 비교에 필요한 compositor·테스트 의존성과 기준선 테스트가 이미지 빌드 때 들어가므로(`docker/e2e.Dockerfile`의 `tests/` 복사), PyPI wheel만으로는 기준선 suite와 A/B 환경을 만들 수 없다. 재빌드 이미지에는 직전 릴리스 wheel이 아니라 태그 소스에서 만든 wheel이 들어가므로, 이 차이와 variant별 drift(아래)를 ledger에 적는다. 공개 산출물 확인(게시 전·후 문서대로 설치, `## Install contract`)은 이 override와 별개로 그대로 한다.
- variant별 재현성(`docker/README.md` "Reproducibility" 및 각 Dockerfile 머리 주석):
  - Debian(`docker/e2e.Dockerfile`): 베이스 이미지 digest와 snapshot.debian.org 날짜로 고정. 옛 태그 재빌드가 재현 가능하다.
  - Arch(`docker/e2e-arch.Dockerfile`): Arch Linux Archive 날짜로 고정. amd64 전용이다("Arch Linux variant").
  - Fedora, openSUSE Tumbleweed: 베이스만 digest 고정이고 패키지는 현재 저장소에서 받는다. 옛 태그 재빌드는 drift를 명시하거나 미검증 범위로 적는다.
- 기준선 suite × 후보 lane: 후보 이미지에 직전 태그 worktree의 `tests/`를 `/app/tests`에 읽기 전용으로 마운트하고 `tests/e2e`를 돌린다. 이미지가 빌드 시 `tests/`를 복사하므로 마운트가 필요하다. 바이트코드 캐시를 쓰지 않게 한다.
- `tests/e2e/test_mcp_protocol.py`는 도구 이름 집합과 개수를 정확히 단언한 뒤에 도구별 스키마를 검사한다. 도구가 추가되면 이 단언이 먼저 실패해 기존 도구의 스키마 검사가 실행되지 않는다. 이 실패는 CHANGELOG의 의도된 변경과 대조하고, 기존 도구의 스키마 계약은 다른 방법으로 확인한다(E2V-16).
- old-fail 확인: 바뀐 테스트 파일만(`git diff --name-only <base>...HEAD -- tests`) 수정 전 후보 이미지에 마운트해 돌린다. 양쪽에서 통과하는 테스트는 유지된 동작을 고정한 것인지 개별로 읽어 판정하고, 이번 실행이 보여 준 범위를 넘어 주장하지 않는다(E2V-27).

## Verification environment

- 기준 게이트 환경: e2e 이미지(`docker/e2e.Dockerfile` 계열). 명령은 `e2e.yml`의 "Run quality checks"(ruff check, ruff format --check, ty check를 `src tests`에)와 "Run end-to-end tests" 단계, 그리고 `CONTRIBUTING.md` "Complete Docker End-to-End Proof", `docker/README.md` "Commands"를 따른다. 일반 후보 suite는 `scripts/run-e2e-docker.sh`(`--distro`, `--image-tag`, pytest 인자 전달)를 쓴다. 두 ref를 나란히 돌리거나 자원 상한·다른 ref 테스트 마운트가 필요한 lane은 `docker build`/`docker run`을 직접 쓴다.
- CI와 로컬의 차이(E2V-15 test diff lane, E2V-26): `ci.yml` lint는 고정하지 않은 `uvx ruff`를 Python 버전 행렬로 돌리고, type-check는 `uv run ty check src/`만 돈다. `e2e.yml`은 이미지 안에서 `pytest tests`를 돌리지만 이미지 기본 CMD와 runner 기본값은 `tests/e2e`다. 이 차이를 매번 질의로 다시 확인한다.
- `CLAUDE.md` "Common Commands"의 호스트 `uv run ruff/ty`는 cairo 빌드 의존성이 없는 호스트에서 실패할 수 있다. 그런 호스트에서는 이미지 안에서 게이트를 돌린다.
- 재빌드 규칙: 이미지는 빌드 때 소스로 wheel을 만들고 `tests/`를 복사한다. 코드나 테스트가 바뀌면 다시 빌드한다. KWin이 필요 없는 검사만 worktree를 마운트해 재빌드 없이 돌릴 수 있다.
- 고정 경로(Dockerfile 정의): venv `/opt/kwin-mcp-venv`, 테스트 `/app/tests`, artifact `/artifacts`, 사용자 UID 1000. 호스트 artifact 디렉터리는 그 UID가 쓸 수 있어야 한다. 포맷 자동 수정처럼 마운트한 worktree에 쓰는 명령은 소유권을 호스트 사용자로 되돌린다.
- env-limitation으로 분류할 것(제품 결함 아님, 테스트가 의존하면 안 됨):
  - `kwin_wayland --virtual`은 이 이미지에서 ScreenShot2 캡처 데이터를 돌려주지 않는다(`docker/README.md` "Screenshot backends and exact-virtual limitation"). 픽셀 검증은 "Visual pixel oracles"의 테스트 전용 경로를 쓴다.
  - PID 1이 자식을 거두지 않는 컨테이너에서는 종료된 `kwin_wayland`가 좀비로 쌓인다.
  - 로컬 Docker 아키텍처에서 돌릴 수 없는 variant(예: amd64 전용 Arch)는 CI에서만 확인되거나 미검증 범위다.
- 컨테이너 상한: QA 에이전트당 컨테이너 하나, 컨테이너마다 `--cpus`·`--memory` 상한을 둔다. 값은 workstation memory에 기록된 Docker VM 크기를 동시 컨테이너 수로 나눠 정한다(공통 기본값은 defaults.md).
- 0단계 질문: 실제 KDE Plasma 세션에 닿을 수 있는가? 기억된 "라이브 호스트" 사실은 preflight에서 다시 확인한다(E2V-08). 닿지 않으면 실제 데스크톱 `session_connect`, 다중 모니터, 실제 ScreenShot2는 미검증 범위다. 라이브 attach는 컨테이너 안에 두 번째 `kwin_wayland --virtual`과 dbus 세션을 띄워 `session_connect`로 에뮬레이션할 수 있고, 보고서에는 에뮬레이션이라고 적는다.

## Surface areas and oracles

공개 표면 목록: `README.md` "Available Tools" 표, `server.py`의 `@_tool(` 등록, `pyproject.toml` `[project.scripts]`의 진입점(`kwin-mcp`, `kwin-mcp-cli`), `README.md` "Running Directly"의 CLI 옵션, `kwin_mcp.core.AutomationEngine`. 시나리오는 여기 적지 않는다. 매 run 변경 목록과 이 표면에서 설계한다(E2V-14).

| 영역 seed | 진입점 | 오라클 힌트 |
|---|---|---|
| 세션·서버·CLI·보조 도구 | `kwin-mcp`, `kwin-mcp-cli`, 세션 관리 도구 | MCP stdio 하네스(`tests/e2e/mcp_harness.py`, `tests/e2e/session_harness.py`), 설치된 패키지로 띄운 서버 |
| 입력(마우스·키보드·터치·클립보드) | 입력 도구 | GUI 앱 상태를 접근성 트리로 읽기, GTK 상호작용 probe(`tests/e2e/interaction_probe.py`, `tests/e2e/gui_probe.py`) |
| 관찰·접근성 | 관찰 도구, `accessibility_tree`, `find_ui_elements` | 알려진 앱의 위젯 트리·텍스트, 픽셀 오라클(`tests/e2e/visual_harness.py`, `docker/README.md` "Visual pixel oracles") |
| 창 관리 | 창 관리 도구 | KWin이 보고하는 창 상태와 접근성 트리 대조 |
| MCP 프로토콜·설치 패키지 | MCP `tools/list`·호출, wheel 설치 | 도구 스키마·annotation, 오류 신호 방식(`README.md` "How It Works") |

하네스 파일 전체 목록은 `docker/README.md`와 `CONTRIBUTING.md`의 테스트 파일 inventory를 본다.

## CI and merge facts

- required context 질의: `gh api repos/isac322/kwin-mcp/rules/branches/main --jq '.[] | select(.type=="required_status_checks") | .parameters.required_status_checks[].context'`. 이름을 이 문서에 복사하지 않는다.
- 외부·늦게 오는 context: 위 목록 중 `.github/workflows/`의 job이 만들지 않는 것. 목록과 workflow job 이름을 대조해 매번 구한다. 이런 context는 PR이 열린 뒤 몇 분 지나서야 등록되므로 "pending 없음"은 완료가 아니다(E2V-30).
- 자동 승인자: 필요한 승인 리뷰와 외부 required context 하나를 자동 리뷰 봇이 올린다. 직전 릴리스 PR의 리뷰 목록(`gh api repos/isac322/kwin-mcp/pulls/<번호>/reviews`)에서 식별한다. 그 봇이 올리는 required context도 모두 보고될 때까지 머지하지 않는다(E2V-30). 승인 리뷰가 없을 때의 처분은 전역 머지 가드가 정하고, 그 처분을 ledger에 적는다.
- 머지 규칙 질의: `gh api repos/isac322/kwin-mcp/rules/branches/main --jq '.[] | select(.type=="pull_request") | .parameters'`(squash 전용, 승인 수, last-push 승인, stale 리뷰 해제)와 `... select(.type=="required_status_checks") | .parameters.strict_required_status_checks_policy`(strict up-to-date). bypass actor는 strict도 건너뛸 수 있으므로 태그 대상 트리는 계산으로 확인한다(E2V-37). head 브랜치 자동 삭제: `gh api repos/isac322/kwin-mcp --jq .delete_branch_on_merge`.
- `docs-seo.yml`(Documentation consistency check)은 경로 필터가 있다. required 여부는 위 질의로 확인한다.
- 알려진 flake 서명: openSUSE Tumbleweed 이미지 빌드 중 `zypper`가 미러 404 메타데이터로 실패한다("not found on medium", "returned error: 404, trying next mirror" 류 로그). rolling 배포판이라 고정할 수 없다. 서명이 맞으면 즉시 재실행 한 번, 이후 간격을 둔 bounded retry(defaults.md)로 처리한다. required이므로 bypass하지 않는다. 같은 서명이 머지 뒤 기본 브랜치 E2E run에도 나온다(E2V-31, E2V-41).
- 소요 시간 질의(watcher 상한 산정): `gh run list --repo isac322/kwin-mcp --workflow CI --status success --limit 5 --json createdAt,updatedAt`, 같은 질의를 `--workflow E2E`로. 상한은 CI 소요와 자동 리뷰 지연의 합 이상으로 잡는다.

## Install contract

- 공개 설치 문서: `README.md` "Quick Start", "System Requirements"("Installing System Dependencies"의 빌드 전제와 런타임 패키지), "Installation".
- 깨끗한 이미지: README가 명령을 제시하는 배포판의 공식 베이스 이미지. 저장소 소스와 e2e 이미지는 쓰지 않는다. 게시 전에는 후보 SHA에서 만든 release-equivalent wheel을 README 절차대로 설치한다. 수정 분기가 없는 GO 경로에서는 G-GO의 설치 lane으로, 수정 뒤에는 G-REQA에서 최종 head로 다시 한다(E2V-28). 게시 뒤에는 PyPI에서 README 명령 그대로 설치한다(E2V-42). smoke 오라클은 MCP stdio 클라이언트로 이번 릴리스의 헤드라인 변경·수정을 호출하는 것이다.
- end-user vs env-only 분류 힌트: 데스크톱 사용자가 README 경로를 따라도 빠지는 시스템 패키지·도구(입력 백엔드, Qt Wayland 플러그인, uv 설치 안내 같은 것)는 문서 결함이다. 컨테이너에만 생기는 조치(바이너리 실행 capability 제거, 런타임 디렉터리 설정, root·sudo 부재, PID 1 좀비)는 env-only다. PR 본문이 env-only를 "이미 문서에 있음"이라고 주장하기 전에 해당 문서를 읽어 확인한다.

## Release notes

- 규칙: `.claude/skills/release-notes/SKILL.md`("Step 3" 템플릿, Minor+ 릴리스의 New Tools 표, "Step 4" SEO 규칙)와 `CLAUDE.md` "GitHub Release Notes Rules". 직전 릴리스 노트는 문체 참고로만 쓴다(E2V-04).
- 노트는 게시 전에 독립 리뷰어가 이 규칙과 CHANGELOG에 대조한다(E2V-34). 합의로 확정한 FIX가 저장소 전체에서 클라이언트가 보는 계약을 바꿨으면 노트와 보고에 동작 변경으로 따로 적는다(E2V-47).
- release-notes "Step 5: Present for Review"의 사용자 확인은 E2V-35를 아래 `## Overrides`까지 적용한 뒤 판단한다. 요청이 버전 결정과 최종 릴리스까지 명시적으로 맡겼으면 묻지 않고 버전 근거와 노트를 최종 보고에 싣는다(위임이면 생략. 프로필 Overrides가 요구하면 묻는다). 이 프로필에서는 버전 근거에 클라이언트가 보는 breaking 변경이 있으면 위임이어도 GO 직후 버전 제안과 근거를 붙여 버전 질문을 한 번 하고, 답이 올 때까지 3단계(컷)와 그 뒤 단계만 멈춘다. 답과 msg id는 ledger의 NEEDS-USER 표에 적고, G-CUT은 그 기록이 있어야 통과한다(노트 승인은 묻지 않는다). 위임이 아니면 GO 직후 버전과 노트를 한 번에 묻는다.

## Overrides

- **E2V-07**: 차등 QA 기준선은 직전 태그에서 다시 빌드한 e2e 이미지다(이유와 drift 기록은 `## Baseline recipe`).
- **E2V-26**: CI와 같은 환경은 e2e 이미지다. 호스트 `uv run` 결과로 게이트 통과를 주장하지 않는다.
- **E2V-35** 좁힘 [U]: 버전 근거에 클라이언트가 보는 breaking 변경이 하나라도 있으면, 요청이 버전과 릴리스를 끝까지 맡겼어도 GO 직후 버전 제안과 근거를 붙여 버전 질문을 한 번 한다. 답이 올 때까지 3단계(컷)와 그 뒤 단계만 멈춘다. 출처: 사용자 결정 01a12b05 122123cc; ASK@2026-10-12T09:32. 수정 분기를 거쳤으면 "GO 직후"는 G-REQA 통과와 버전 재도출이 ledger에 있는 시점이다.
- **E2V-42**: 게시 후 smoke는 이번 릴리스의 새·바뀐 도구를 MCP stdio로 호출하는 것을 포함한다.

## Cases

### CASE-20261011-release-notes-ignored-repo-skill
- 상태: applied
- 출처: omp session 01a12b05 msg 735cb2ac, 8673a128
- 상황: 저장소 릴리스 노트 스킬(New Tools 표, 게시 전 확인 단계)을 찾지 못하고 직전 릴리스 본문을 템플릿으로 썼다. 노트를 검토한 사람이 없었다.
- 대상: 릴리스 / 공개 저장소 / GitHub 릴리스 노트 / 중간
- 적용 조건: 저장소에 로컬 릴리스·노트 스킬이나 노트 규칙이 있는 모든 릴리스
- 사용자 기대: 저장소가 정한 노트 형식과 확인 절차를 따른다.
- 실제 행동: 도구 두 개를 추가한 minor 릴리스 노트에 New Tools 표가 없고, 독립 리뷰 없이 게시했다.
- 원인 분류: missing / 규칙: E2V-04, E2V-34
- 변경: E2V-04(0단계 저장소 하네스 탐색), E2V-34(노트 독립 리뷰) 신설
- 일반화: project
- 재발 확인 기준: ledger 헤더에 저장소 노트 스킬이 기록되고, 노트 리뷰 기록이 그 스킬의 템플릿 항목을 하나씩 대조한다.

### CASE-20261011-lock-revision-normalized
- 상태: applied
- 출처: omp session 01a12b05 msg d4b7139c, 61137a3b, 2b6d2c91, 47ddc799
- 상황: 로컬 uv가 lock 헤더를 다른 revision으로 다시 썼다. 고정 버전 uv 이미지로 다시 만들려던 시도는 CLI 오용과 distroless 이미지 때문에 실패했고, 헤더를 손으로 되돌린 뒤 공개했다. 그런데 리뷰어 brief는 CI가 uv를 고정한다는 틀린 전제를 담았다.
- 대상: 릴리스 PR / 공개 저장소 / lockfile / 낮음
- 적용 조건: 릴리스 PR에서 lockfile을 다시 만드는 모든 경우
- 사용자 기대: lock 메타데이터가 이유 없이 바뀌지 않고, 리뷰어에게 사실만 전달한다.
- 실제 행동: 손 편집은 공개됐지만 brief 전제가 틀렸다.
- 원인 분류: loose / 규칙: E2V-32, E2V-29
- 변경: E2V-32(lock drift 설명·도구 명시), E2V-29(brief는 확인할 사실만) 신설
- 일반화: project
- 재발 확인 기준: 릴리스 PR 기록에 lock 헤더 비교 결과와 생성 도구가 있고, brief에 확인되지 않은 환경 주장이 없다.

### CASE-20261011-automated-approver
- 상태: applied
- 출처: omp session 01a12b05 msg c3ff0ce3, c68a17bd, c8e4c5c2
- 상황: 필요한 승인 리뷰와 외부 required context 하나가 PR을 연 뒤 몇 분 지나 자동 리뷰 봇에게서 온다.
- 대상: 머지 / 공개 저장소 / PR / 높음
- 적용 조건: 이 저장소의 모든 PR 머지
- 사용자 기대: 늦게 오는 required context가 보고될 때까지 머지하지 않고, 승인 리뷰 처분은 전역 머지 가드를 따라 기록한다.
- 실제 행동: watcher가 아직 등록되지 않은 외부 context를 목록에서 보지 못한 채 끝났고, 그 context가 보고되기 전에 관리자 우회로 머지했다. context와 승인은 머지 직후 자동 승인자에게서 도착했다.
- 원인 분류: missing / 규칙: E2V-30
- 변경: E2V-30(실시간 ruleset 목록 기준 required context 완료 확인, 승인 처분은 전역 머지 가드에 맡기고 ledger에 기록) 신설
- 일반화: project
- 재발 확인 기준: 머지 기록에 정확한 head SHA 기준 required context 질의 결과가 모두 보고됨으로 있고, 승인 리뷰 상태와 그 처분(대기 또는 가드 예외)이 적혀 있다.

### CASE-20261011-rolling-distro-mirror-flake
- 상태: applied
- 출처: omp session 01a12b05 msg 8a6e2eb6, 82cd0cc9, faa7d0d1, c6b094f4
- 상황: rolling 배포판 이미지 빌드가 미러의 404 메타데이터로 실패했다. 즉시 재실행은 다시 실패했고, 간격을 둔 bounded retry로 통과했다. 같은 서명이 릴리스 커밋의 기본 브랜치 E2E에도 나왔다.
- 대상: CI / 공개 저장소 / required check / 중간
- 적용 조건: Tumbleweed 이미지 빌드 실패 로그가 미러 404 서명과 맞을 때
- 사용자 기대: 서명으로 분류하고 재시도하며 required check를 우회하지 않는다.
- 실제 행동: PR에서는 bounded retry로 해결했지만 기본 브랜치 run은 관찰하지 않았다.
- 원인 분류: missing / 규칙: E2V-31
- 변경: E2V-31(서명 분류, 즉시 재실행 1회, bounded retry, 기본 브랜치 run 포함) 신설
- 일반화: project
- 재발 확인 기준: 실패 기록에 로그 서명 분류와 재시도 이력이 있고 bypass가 없다.

### CASE-20261011-virtual-session-env-limits
- 상태: applied
- 출처: omp session 01a12b05 msg 53b8da0f
- 상황: 가상 compositor는 스크린샷 백엔드 데이터를 주지 않고, 자식을 거두지 않는 PID 1은 좀비 compositor를 남긴다. 테스트 helper 하나가 스크린샷 성공에 기대고 있어 고쳐야 했다.
- 대상: QA / 공개 저장소 / 테스트 환경 / 중간
- 적용 조건: 컨테이너 가상 세션에서 돌리는 QA와 테스트
- 사용자 기대: 환경 한계는 제품 결함으로 보고하지 않고, 테스트는 그 한계에 기대지 않는다.
- 실제 행동: 한계는 결국 env-limitation으로 분류됐지만 helper 의존은 수정 중에야 드러났다.
- 원인 분류: missing / 규칙: E2V-25
- 변경: E2V-25(brief에 환경 능력 사실, 실패는 artifact/제품 분류 후 수정) 신설
- 일반화: project
- 재발 확인 기준: QA brief에 이 두 한계가 있고, 관련 관찰이 env-limitation으로 분류된다.

### CASE-20261011-old-suite-pins-mask
- 상태: applied
- 출처: omp session 01a12b05 msg d099e8e9, aef1989e
- 상황: 기준선 suite의 도구 집합·개수 단언이 additive 변경에서 실패했고, 그 단언이 앞에 있어 기존 도구의 스키마 검사가 실행되지 않았다.
- 대상: QA / 공개 저장소 / 테스트 suite / 중간
- 적용 조건: 기준선 suite × 후보 lane에서 정확 일치 단언이 실패할 때
- 사용자 기대: 의도된 변경으로 인한 실패를 가려내고, 가려진 검사를 따로 확인한다.
- 실제 행동: 실패는 의도된 변경으로 맞췄지만 가려진 스키마 검사는 확인하지 않았다.
- 원인 분류: missing / 규칙: E2V-16
- 변경: E2V-16(실패를 CHANGELOG와 대조, 중단된 나머지 검사 보완) 신설
- 일반화: project
- 재발 확인 기준: lane 기록에 실패마다 CHANGELOG 항목과 보완 검사 결과가 있다.

### CASE-20261011-remembered-live-host-wrong
- 상태: applied
- 출처: omp session 01a12b05 msg 2a3771d2, a75317a4, 10c0a942
- 상황: 기억에 있던 "라이브 데스크톱 호스트"가 실제로는 작업 머신 자신이었다. 실제 세션 범위는 미검증으로 보고했다. 호스트 사실 자체는 memory 소관이고 주소는 적지 않는다.
- 대상: 0단계 / 공개 저장소 / 환경 사실 / 중간
- 적용 조건: 기억된 환경 사실로 검증 대상을 정할 때
- 사용자 기대: 기억된 사실을 preflight에서 다시 확인하고, 닿지 않는 대상은 미검증 범위로 적는다.
- 실제 행동: 연결이 실패한 뒤에야 사실이 틀린 것을 알았다.
- 원인 분류: missing / 규칙: E2V-08
- 변경: E2V-08(preflight 환경 사실 재확인) 신설
- 일반화: project
- 재발 확인 기준: preflight 기록에 호스트 정체 확인이 있고, 실패 대상이 미검증 범위에 있다.

### CASE-20261012-breaking-version-always-asked
- 상태: applied
- 출처: omp session 01a12b05 msg 122123cc; ASK@2026-10-12T09:32
- 상황: 0.x에서 클라이언트가 보는 breaking 변경을 담은 릴리스의 버전을 위임된 run이 스스로 정해도 되는지 사용자가 결정했다. 처음 답(특정 버전 지정)은 사용자가 다시 물어 달라고 해 대체됐고, 다시 물은 뒤의 답만 이 결정의 근거다.
- 대상: 릴리스 / 공개 저장소 / 버전 결정 / 높음
- 적용 조건: 버전 근거에 클라이언트가 보는 `제거·이름 변경` 또는 `형식·동작 변경` 항목이 하나라도 있는 kwin-mcp 릴리스
- 사용자 기대: 0.x breaking 변경 포함 릴리스는 위임과 무관하게 매번 버전을 묻는다.
- 실제 행동: 해당 없음(사용자 결정 시드)
- 원인 분류: missing / 규칙: E2V-35 (profile Overrides)
- 변경: profile `## Overrides`에 E2V-35 좁힘 추가. E2V-35 규칙 문구는 유지
- 일반화: project
- 재발 확인 기준: 위임된 run이라도 breaking 칸이 비어 있지 않으면 GO 직후 버전 질문이 ledger에 있고, 답 전까지 컷이 시작되지 않는다.
