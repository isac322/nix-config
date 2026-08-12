# 0005. 호스트명이 설정을 고른다

**결정** — 어느 설정을 적용할지는 `scutil --get LocalHostName` 이 정한다. 그 이름을
nix-darwin 이 관리하게 두지 않는다.

`darwin-rebuild` 는 `--flake` 에 `#` 이 없으면 `scutil --get LocalHostName` 을
속성 이름으로 쓰고(nix-darwin 의 `pkgs/nix-tools/darwin-rebuild.sh`), `--flake`
자체가 없으면 `/etc/nix-darwin/flake.nix` 를 따라간다 — 심링크여도 된다. 그래서
이름만 세워 두면 맥에서는 기기 이름을 칠 일이 없다. 이름이 틀리면 조용히 다른
설정이 적용되는 게 아니라 그냥 실패한다.

```
error: flake … does not provide attribute 'darwinConfigurations.<name>.system'
```

`nixos-rebuild` 에는 이 편의가 없어서 서버만 `#server` 를 붙인다.

**`networking.hostName` 등으로 nix-darwin 에 맡길 수도 있지만 일부러 두지 않았다.**
이름이 곧 입력이라 설정 안에 두면, 이름을 고치기 위해 먼저 잘못된 기기 설정을 한 번
적용해야 하는 순환이 된다. 부트스트랩에서 `scutil` 로 세우고 끝낸다.

셋 중 `LocalHostName` 만 설정 선택에 관여하지만 `ComputerName` 과 `HostName` 도
같이 세운다. 셋이 갈라져 있으면 나중에 기계를 헷갈린다.

문서에도 기기 이름을 적지 않는다. 목록은 레포가 갖고 있으므로 물어보면 된다:

```sh
nix eval --json .#darwinConfigurations --apply builtins.attrNames
```
