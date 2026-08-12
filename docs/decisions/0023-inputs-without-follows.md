# 0023. `follows` 를 일부러 안 붙인 인풋

**결정** — 두 인풋은 nixpkgs 를 따라가게 하지 않는다.

- `llm-agents` — `shared-nixpkgs` 오버레이가 `bun`을 자기 nixpkgs에서 고정한다.
  follows를 걸면 세트 전체의 store path가 바뀌어 캐시가 전부 빗나간다.
- `determinate` — upstream이 FlakeHub 캐시 미스를 이유로 권장하지 않는다.

둘 다 이유가 같은 종류다. `follows` 는 중복 nixpkgs 를 없애 평가를 가볍게 하지만,
그 대가로 상류가 빌드해 둔 것과 다른 파생이 된다.
