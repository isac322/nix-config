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

현재 배포된 타르볼은 의존성을 모두 번들에 담고 `dependencies` 가 비어 있다. 그래서
`npm ci` 도 lock 파일도 필요 없이 타르볼을 그대로 풀고 Node 래퍼만 씌운다.
`package.nix` 는 manifest 의 `dependencies` 가 비어 있다고 assert 한다 — 상류가
런타임 의존성을 다시 들이면 조용히 깨진 패키지가 아니라 평가 실패로 드러난다.
버전과 타르볼 integrity 는 `nix run .#update-packages` 가 npm 레지스트리의 최신
버전에서 snapshot 에 적는다.

## vercel-cli — npm 플랫폼 바이너리

nixpkgs 에는 어떤 이름으로도 없다 — `vercel` 도 `vercel-cli` 도 없고, 가장 비슷한
`vercel-pkg` 는 이름만 바뀐 zeit/pkg 번들러로 무관하다.

JS CLI 타르볼 대신 상류가 플랫폼별로 배포하는 `@vercel/vc-native-<platform>`
패키지를 쓴다. 하나의 바이너리라 의존성 트리도 lock 파일도 필요 없고, 플랫폼마다
자기 것 하나만 받는다. 세 플랫폼의 버전과 integrity 는 `update-packages` 가 각
패키지의 npm 최신 버전에서 snapshot 에 적고, 설치 검사는 `vercel --version` 이
snapshot 의 버전을 출력하는지 확인한다.
