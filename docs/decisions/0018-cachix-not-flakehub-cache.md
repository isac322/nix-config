# 0018. 세 기기가 같은 것을 세 번 컴파일하지 않게 — Cachix

**결정** — 모든 호스트가 쓰는 custom package output과 Darwin의 source-built
`macvnc`를 Cachix에 올린다. 서버 하나만 쓰고 고정된 상류 artifact를 푸는
`camoufox`, `camofox-browser`, `deskpad`, `displayplacer`는 제외한다. FlakeHub
Cache는 쓰지 않는다. 푸시 절차는 [운영 · 캐시 푸시](../operations.md#캐시-푸시).

[레포를 인풋으로 노출하는 것](../reference.md#이-레포를-패키지-저장소로-쓰기)까지는
공짜다. AUR과 정말 다른 지점은 배포가 아니라 **반복 빌드**다. custom CLI는 공개
cache에 없거나 이 저장소가 nixpkgs attribute를 교체한 derivation이고, `macvnc`는
source에서 빌드한다. 반면 제외한 네 package는 고정한 release artifact를 풀어
포장하는 것이 대부분이라 cache 용량과 upload bandwidth를 쓸 만큼 절약하지 못한다.
`bun` override도 같은 이유로 대상이 아니다.

`cache-push`는 `packages.<system>`을 읽은 뒤 위 네 attribute만 `removeAttrs`로
제외한다. 새 package는 기본적으로 push 대상이 되므로, 서버 전용 fixed-artifact
repack을 추가할 때만 exclusion도 함께 검토한다.

FlakeHub Cache 는 Determinate 를 이미 쓰는 만큼 자연스러워 보이지만 두 번 막힌다 —
유료 플랜 전용이고, 애드혹 push 를 의도적으로 금지해 신뢰된 빌더(GitHub Actions,
Semaphore, Buildkite)에서만 올릴 수 있다. 랩탑에서 빌드해 올리는 방식과 맞지 않는다.
Cachix 는 오픈소스에 5 GB 무료이고 어디서든 push 된다.
