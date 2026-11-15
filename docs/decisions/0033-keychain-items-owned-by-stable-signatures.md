# 0033. Nix 빌드 바이너리가 키체인 항목을 소유하지 않게

**결정** — 키체인 항목은 서명이 업데이트를 넘어 유지되는 프로그램만 만든다.
`/usr/bin/security`(Apple 서명) 또는 Developer ID 로 서명된 업스트림 바이너리다.
Nix 가 소스에서 빌드한 바이너리(ad-hoc 서명)는 키체인에 직접 쓰지 않는다.

- GitHub HTTPS 자격증명: nixpkgs git 의 `osxkeychain` 대신 `gh auth git-credential`
  (`home/darwin.nix`). gh 는 `/usr/bin/security` 로 토큰을 저장한다.
- `gws`: `GOOGLE_WORKSPACE_CLI_KEYRING_BACKEND=file` 을 래퍼로 고정
  (`pkgs/overlay.nix`). 키는 `~/.config/gws/.encryption_key`(0600) 에 둔다.
- `ntn`: 그대로 둔다. 업스트림 바이너리가 Developer ID(`LBQJ96FQ8D`) 로 서명돼
  있어 버전이 바뀌어도 항목이 그 바이너리를 알아본다.

## 어떻게 드러났나

키체인 비밀번호를 묻는 창이 거의 매일 떴고, 그동안 요청한 프로세스는 멈춰 있었다.
`securityd` 로그에 창을 띄운 주체가 그대로 남아 있었다:

```
displaying keychain prompt for /nix/store/5gpq…-git-2.56.0/…/git-credential-osxkeychain
  ACL: /usr/bin/security, …-git-2.55.0/…/git-credential-osxkeychain [cdhash H"7276…"], …
displaying keychain prompt for /nix/store/d7dv…-gws-0.22.5/bin/gws
  ACL: /nix/store/f057…-gws-0.22.5/bin/gws [cdhash H"3b37…"]
```

`security dump-keychain -a` 로 보면 Nix 경로를 신뢰하는 항목이 전부 이 꼴이었다.
경로는 이미 GC 됐다(`status -67068`).

## 왜 매일인가

키체인 항목은 조용히 읽어도 되는 프로그램 목록을 **코드 서명 요구사항**으로
기억한다. Developer ID 서명이면 요구사항이 "이 식별자 + 이 팀" 이라 새 버전도
통과한다. ad-hoc 서명이면 요구사항이 `cdhash` 하나뿐이다. Nix 빌드는 ad-hoc 이고,
`nix run .#update-packages` 가 의존성 하나만 바꿔도 store 경로와 cdhash 가 바뀐다.
gws 는 버전이 0.22.5 그대로인데도 경로가 달라져 창이 떴다.

이 기기는 하루에도 몇 번씩 새 시스템으로 switch 하므로 창도 매일 뜬다. 0030 의
pinentry-keychain 이 `-A` 로 저장하는 것도 같은 이유다.

## 다른 길은 왜 안 했나

- **"항상 허용" 을 누른다**: 다음 업데이트까지만 간다.
- **로컬 인증서로 다시 서명**: store 는 읽기 전용이라 복사본을 따로 두고 서명용 키를
  관리해야 한다. 고칠 대상보다 장치가 더 크다.
- **gws 에 세션 변수로 설정**: Codex 처럼 이름에 `KEY` 가 들어간 변수를 지우는
  샌드박스에서 빠진다. 래퍼는 호출 경로와 상관없이 적용된다.

## 잃는 것

gws 의 키가 키체인에서 0600 파일로 옮겨온다. 서버 맥에서는 이미 로그인 비밀번호가
같은 사용자 권한의 파일(`/var/lib/nix-darwin/login-password`) 에 있으므로 보호
수준이 달라지지 않는다. 랩탑에서는 같은 사용자의 다른 프로세스가 확인 창 없이 읽을
수 있게 된다. 그 확인 창이 바로 이 문제였다.

## 한 번만 하는 이전

기존 gws 키는 키체인에 있고, 그 항목은 이미 사라진 바이너리만 신뢰한다. 파일
백엔드는 키 파일이 없으면 새 키를 만들고, 그러면 `credentials.enc` 를 못 푼다.
그래서 기기마다 한 번 옮긴다. 확인 창이 한 번 뜨고 누군가 허용해야 한다:

```sh
umask 077
security find-generic-password -s gws-cli -a "$USER" -w > ~/.config/gws/.encryption_key
```

키가 필요 없으면 항목을 지우고 `gws auth login` 을 다시 해도 된다.

GitHub 쪽은 옮길 것이 없다. gh 가 이미 로그인돼 있다. 옛 `github.com` 인터넷
비밀번호 항목은 더 이상 읽히지 않는다.
