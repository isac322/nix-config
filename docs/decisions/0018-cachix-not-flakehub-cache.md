# 0018. 세 기기가 같은 것을 세 번 컴파일하지 않게 — Cachix

**결정** — `pkgs/` 의 여섯만 Cachix 에 올린다. FlakeHub Cache 는 쓰지 않는다.
푸시 절차는 [운영 · 캐시 푸시](../operations.md#캐시-푸시).

[레포를 인풋으로 노출하는 것](../reference.md#이-레포를-패키지-저장소로-쓰기)까지는
공짜다. AUR 과 정말 다른 지점은 배포가 아니라 **빌드**가 아프다는 것이다.
`pkgs/` 의 여섯은 어떤 공개 캐시에도 없다 — 넷은 nixpkgs 에 존재하지 않고,
`slack-cli` 와 `tempo-cli` 는 nixpkgs 의 attribute 를 갈아끼운 것이라
`cache.nixos.org` 가 그 이름으로 빌드해 둔 것과 파생이 다르다. 그래서 기기마다
새로 컴파일한다. 나머지는 상류 캐시가 덮으므로, 올릴 가치가 있는 것은 정확히 이
여섯뿐이다. (`bun` 오버라이드도 로컬 빌드이긴 한데, 상류가 배포한 zip 을 푸는
게 빌드의 전부라 올려도 아끼는 게 없다.)

`packages.<system>` 과 `cache-push` 는 **같은 목록**이다. 후자가 전자를
`attrValues` 로 읽는다 — 한쪽에만 추가된 패키지는 조용히 모든 기기에서 다시
컴파일되는 패키지가 되기 때문이다.

FlakeHub Cache 는 Determinate 를 이미 쓰는 만큼 자연스러워 보이지만 두 번 막힌다 —
유료 플랜 전용이고, 애드혹 push 를 의도적으로 금지해 신뢰된 빌더(GitHub Actions,
Semaphore, Buildkite)에서만 올릴 수 있다. 랩탑에서 빌드해 올리는 방식과 맞지 않는다.
Cachix 는 오픈소스에 5 GB 무료이고 어디서든 push 된다.
