# 0002. 상속이 아니라 조합

**결정** — OS × 역할 × 기기 세 축을 상속 계층이 아니라 모듈 조합으로 푼다.

모든 설정은 `common + platform + role + host` 이고, 조합 지점은 `flake.nix`
한 곳뿐이다.

```nix
"bhyoo-macbook-air" = mkDarwin { hostname = "bhyoo-macbook-air"; role = "laptop"; };
"bhyoo-macbook-pro" = mkDarwin { hostname = "bhyoo-macbook-pro"; role = "server"; };
```

상속이면 "랩탑은 맥을 물려받고 맥은 공통을 물려받는다" 는 사슬이 생기고, 어느 값이
어디서 왔는지 알려면 사슬을 거슬러야 한다. 조합은 그 목록이 한 줄에 다 있다.
세 층 어디에도 안 맞는 것은 `extraModules` / `extraHomeModules` 로 넘긴다 —
한 기계가 미디어 서버를 겸하는 식의 경우.

## 공유 모듈에 넣으면 안 되는 것

- **`system.stateVersion`** — nix-darwin은 정수(`7`), NixOS는 문자열(`"26.05"`).
  타입이 달라서 공통 모듈에 두면 평가가 깨진다. 각 플랫폼 모듈에 따로 있다.
- **`nixpkgs-firefox-darwin` 오버레이** — `firefox-bin` 외에 `librewolf`,
  `floorp-bin`, `zen-browser-bin`도 정의한다. Linux에 걸면 nixpkgs 원본을 가려버린다.
  그래서 `modules/darwin.nix`에만 있다. 검증: 맥에서 `librewolf.pname`은
  `Librewolf`(오버레이), 서버에서는 `librewolf`(nixpkgs). 오버레이가 랩탑 역할에만
  있는 이유도 같다 — 무해한 오버레이가 아니다.
- **공유 기본값은 `lib.mkDefault`로** — `modules/darwin.nix`의 `system.defaults`가
  그렇다. 없으면 호스트가 같은 옵션을 정의할 때 동일 우선순위로 충돌한다.

역할 파일은 의도적으로 얇다. 맥은 어느 역할이든 같은 맥이라 겉모습 설정은 위층에
있고, 역할에는 진짜로 갈리는 것만 둔다 —
[레퍼런스 · 무엇이 어느 층에](../reference.md#무엇이-어느-층에-속하나).
