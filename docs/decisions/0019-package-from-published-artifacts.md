# 0019. 소스 체크아웃이 아니라 배포된 아티팩트에서 패키징

**결정** — `pkgs/` 의 CLI 들은 git 체크아웃이 아니라 crates.io · npm 타르볼에서
가져온다. 목록은 [레퍼런스 · `pkgs/`](../reference.md#pkgs).

셋 다 같은 모양의 이유다: 상류가 모노레포이고, 버전 번호가 실제로 가리키는 것은
publish 훅이 만든 번들이며, 체크아웃을 쓰면 작은 바이너리 하나 만들자고 거대한
트리와 추가 빌드 도구를 끌어와야 한다.

## posthog-cli — crates.io

GitHub 이 아니라 crates.io 인 이유는, 이 CLI 가 PostHog 모노레포 안에 살아서 git
체크아웃을 하면 작은 바이너리 하나 만들자고 거대한 트리를 받아오기 때문이다.
배포된 크레이트는 같은 코드에 Cargo.lock 까지 들어 있다. 두 가지를 미리 확인했다 —
의존성이 rustls 로 풀려 Cargo.lock 어디에도 `openssl-sys` 가 없어서 맥과 리눅스가
같은 표현식으로 빌드되고, `build.rs` 가 심는 텔레메트리 토큰은 디버그 빌드 전용에
소비 측이 `option_env!` 이라 릴리스 빌드는 CI 시크릿 없이도 컴파일되고 토큰도 안
들어간다.

`fetchCrate` 의 해시는 파일 해시가 아니라 **압축을 푼 트리의 NAR 해시**다.
`nix store prefetch-file` 로 받은 값을 그대로 넣으면 어긋난다.

## axiom-cli — 평범한 Go 모듈

goreleaser 가 박는 변수 중 `version.release` 만 옮겨 심었다. 나머지 둘
(`revision`, `buildDate`)은 체크아웃의 git 메타데이터를 요구하는데 받아온 타르볼에는
없다. 최소한 `release` 는 있어야 `axiom version` 이 빈 문자열을 뱉지 않는다. 셸
완성은 방금 빌드한 바이너리를 실행해서 만들므로 `stdenv.buildPlatform.canExecute`
로 감쌌다 — 크로스 빌드에서는 완성만 빠지고 빌드는 실패하지 않는다. posthog-cli 는
clap 정의에 완성 생성 서브커맨드가 없어 넣지 않았다.

## langfuse-cli — npm 타르볼

저장소에는 태그가 하나도 없고 `dist/` 가 `.gitignore` 에 들어 있다 — 번들은
prepublish 훅의 `bun build` 가 만든다. 체크아웃을 쓰면 npm 이 이미 배포한 파일
하나를 다시 만들자고 bun 을 빌드 의존성으로 끌어와야 하고, 버전 번호가 가리키는
것도 결국 그 타르볼이다.

npm 타르볼에는 **lock 파일이 없는데** `buildNpmPackage` 의 재현성은 `npm ci` 에서
나오고 `npm ci` 는 lock 없이는 돌기를 거부한다. 그래서 한 번 손으로 만들어
`pkgs/langfuse-cli/package-lock.json` 으로 함께 담았다. 버전을 올릴 때 둘을 같이
다시 만든다:

```sh
npm install --package-lock-only --legacy-peer-deps
nix run nixpkgs#prefetch-npm-deps -- package-lock.json   # npmDepsHash
```

`--legacy-peer-deps` 는 에러를 지우려고 붙인 것이 아니다. 유일한 의존성인 `specli`
가 `ai` 와 `zod` 를 peer 로 선언하는데, 그대로 두면 `undici` 까지 열두 개가 더
따라 들어온다. 둘은 `specli` 의 `dist/ai/tools.js` — 이 CLI 가 한 번도 로드하지
않는 별개 export — 에서만 쓰인다.

설치 검사는 `--version` 이 아니라 `api __schema` 다. 이 CLI 는 `--version` 을
아예 모르고 (도움말을 뱉으며 0 으로 끝난다), 도움말은 **아무것도 증명하지 않는다** —
번들의 유일한 런타임 import 인 `import.meta.resolve("specli")` 는 로드 시점이 아니라
api 서브커맨드가 돌 때 풀리므로, `node_modules` 가 통째로 없어도 도움말은 멀쩡히
나온다. 그게 바로 이 패키지가 깨질 수 있는 지점이다. `api __schema` 는 그 import 를
지나가는 가장 싼 명령이고, 스펙을 타르볼에 담긴 `openapi.yml` 에서 읽으므로 자격
증명도 샌드박스에 없는 네트워크도 필요 없다.

## vercel-cli — npm 타르볼 + 편집한 manifest

nixpkgs 에는 어떤 이름으로도 없다 — `vercel` 도 `vercel-cli` 도 없고, 가장 비슷한
`vercel-pkg` 는 이름만 바뀐 zeit/pkg 번들러로 무관하다. 타르볼을 고른 이유는
langfuse-cli 와 같다: 저장소가 모노레포이고 `files` 가 `["dist"]` 이라, 배포된
것이 곧 prepublish 가 만든 번들이고 버전 번호가 가리키는 것도 그것이다.

까다로운 쪽은 의존성 트리이고, 패키지 옆에 `package.json` 과 `package-lock.json`
**둘 다** 들어 있는 게 그 결과다.

npm 타르볼에 lock 이 없다는 것까지는 langfuse-cli 와 같은데, 여기서는 배포된
manifest 그대로는 lock 을 만들 수조차 없다. devDependencies 셋이 애초에 배포된 적
없는 워크스페이스 패키지라 `npm install --package-lock-only` 가 레지스트리 404 에서
멈춘다. `--omit=dev` 도 답이 아니다 — lock 은 설치할 것이 아니라 **이상적인 트리
전체**를 적기 때문이다. 어차피 여기서는 아무것도 컴파일하거나 테스트하지 않으므로
필요도 없다.

`optionalDependencies` 는 이유가 다르다. 같은 네이티브 바이너리를 플랫폼별로 넷
빌드해 둔 것이고 하나가 약 68 MB 인데, `prefetch-npm-deps` 는 이 플랫폼 것인지와
무관하게 lock 의 모든 항목을 받아온다. `dist/vc.js` 의 shim 은 사용자가 명시적으로
켰을 때만 그중 하나를 JS CLI 보다 우선하므로, 빼도 기본 경로는 그대로이고 클로저가
270 MB 가벼워진다.

**그 편집이 lock 을 읽기 전에 끝나야 하고, 그건 곧 `postPatch` 안이어야 한다는
뜻이다.** `buildNpmPackage` 는 의존성 캐시를 두 번째 fixed-output 파생에서 만드는데
그쪽은 `src` 와 `postPatch` 만 공유하고 빌드 인풋은 하나도 못 받는다. 게다가
`npmConfigHook` 은 자기를 `postPatchHooks` 에 덧붙이므로 `preConfigure` 는
자기가 준비해 주려던 `npm ci` **다음에** 돈다. 이미 편집된 manifest 를 복사해
넣는 방식은 두 파생 모두에서 동작하고 둘 다 아무 도구도 필요 없다. 다시 만드는
절차는 패키지 안에 적어 두었다.

설치 검사가 `--version` 이 아니라 `vercel telemetry status` 인 것도 같은 종류의
이유다. 버전은 shim 이 아무것도 로드하기 전에 답하므로 `node_modules` 가 통째로
없어도 통과한다 — 위의 이야기가 전부 node_modules 에 무엇을 넣느냐였다는 걸
생각하면, 그게 바로 잡아야 할 고장이다.
