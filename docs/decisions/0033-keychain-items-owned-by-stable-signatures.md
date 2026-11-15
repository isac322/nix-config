# 0033. Nix 빌드가 업데이트될 때마다 키체인 창이 뜨지 않게

**결정** — 비밀은 계속 키체인에 둔다. 대신 Nix 빌드 바이너리가 바뀔 때마다 키체인이
그 바이너리를 다시 묻지 않게 한다.

- GitHub HTTPS 자격증명: nixpkgs git 의 `osxkeychain` 대신 `gh auth git-credential`
  (`home/darwin.nix`). gh 는 Apple 서명의 `/usr/bin/security` 로 키체인에 저장하므로
  업데이트와 무관하다.
- `gws`: 항목을 한 번 "모든 앱 허용"(`-A`)으로 다시 만들고, 서버 맥은 switch 마다
  그 항목의 파티션 목록을 새 gws 의 cdhash 로 바꾼다
  (`home/roles/darwin-server.nix` 의 `authorizeKeychainPrograms`).
- `ntn`: 그대로 둔다. Developer ID(`LBQJ96FQ8D`) 로 서명돼 있어 버전이 바뀌어도
  같은 바이너리로 인정된다.

## 어떻게 드러났나

키체인 비밀번호를 묻는 창이 거의 매일 떴고, 그동안 요청한 프로세스는 멈춰 있었다.
`securityd` 로그에 창을 띄운 주체가 그대로 남아 있었다:

```
displaying keychain prompt for /nix/store/5gpq…-git-2.56.0/…/git-credential-osxkeychain
  ACL: /usr/bin/security, …-git-2.55.0/…/git-credential-osxkeychain [cdhash H"7276…"], …
displaying keychain prompt for /nix/store/d7dv…-gws-0.22.5/bin/gws
  ACL: /nix/store/f057…-gws-0.22.5/bin/gws [cdhash H"3b37…"]
```

## 관문이 둘이다

macOS 는 옛 방식 키체인 항목을 두 번 검사한다(`securityd/src/acls.cpp`,
`clientid.cpp`).

1. **ACL** — 조용히 읽어도 되는 프로그램 목록. ad-hoc 서명이면 요구사항이
   `cdhash` 하나뿐이다.
2. **파티션 목록** — 서명 주체 목록. Apple 은 `apple:`, `/usr/bin/security` 는
   `apple-tool:`, Developer ID 는 `teamid:<팀>`, 그 밖의 서명은 `cdhash:<해시>` 다.
   정확히 일치해야 통과한다. 와일드카드는 없다.

Nix 빌드는 ad-hoc 서명이다. 의존성 하나만 바뀌어도 cdhash 가 바뀌고, 두 관문 모두
옛 해시를 들고 있으니 창이 뜬다. gws 는 버전이 0.22.5 그대로인데도 경로가 달라져
창이 떴다. 이 기기는 하루에도 몇 번씩 switch 하므로 창도 매일 뜬다.

## 그래서 이렇게 했다

**ACL 은 한 번 `-A` 로.** 그러면 첫 관문은 영구히 통과한다. gws 는 이 항목을
지우거나 다시 만들지 않으므로(`credential_store.rs`) 한 번이면 된다.

**파티션은 switch 마다.** `set-generic-password-partition-list` 는 키체인
비밀번호만 있으면 창 없이 바뀐다. 서버 맥은 자동 로그인 때문에 그 비밀번호를 이미
`/var/lib/nix-darwin/login-password` 에 들고 있다. 비밀번호는 `security -i` 의
stdin 으로 넘겨 `ps` 에 안 뜬다. `apple-tool:` 은 남겨 `security` 로도 읽힌다.

실험으로 확인했다: `-A` 항목에 cdhash A 만 넣으면 A 는 조용히 읽고, 같은 git 버전의
다른 빌드 B 는 창을 띄운다.

## 다른 길은 왜 안 했나

- **"항상 허용" 을 누른다** — 다음 빌드까지만 간다.
- **`-A` 만** — 파티션 관문에서 여전히 막힌다. 위 실험이 그것이다.
- **로컬 인증서로 다시 서명** — Developer ID 가 아닌 서명은 여전히 `cdhash:`
  파티션으로 분류된다. 고정되지 않는다.
- **gws 를 파일 백엔드로** — 키체인을 안 쓰게 될 뿐이다.

## 한계

**랩탑은 자동으로 안 된다.** 키체인 비밀번호를 파일로 갖고 있지 않고, 그걸 위해
비밀번호를 디스크나 키체인에 두는 것은 sudo 비밀번호를 내놓는 일이다. 랩탑에서는
gws 가 다시 빌드된 뒤 처음 한 번 창이 뜨고, 사람이 "항상 허용" 을 누른다.

## 한 번만 하는 이전

기존 gws 항목은 사라진 바이너리만 믿으므로, 읽을 때 창이 한 번 뜬다. 그 한 번을
허용한 뒤 같은 키로 `-A` 항목을 다시 만든다:

```sh
key=$(security find-generic-password -s gws-cli -a "$USER" -w)   # 여기서 창 한 번
security delete-generic-password -s gws-cli -a "$USER" >/dev/null
printf 'add-generic-password -A -s gws-cli -a "%s" -w "%s"\n' "$USER" "$key" | security -i
unset key
```

그다음 switch(또는 `authorize-keychain-programs` 직접 실행)가 파티션을 채운다.

GitHub 쪽은 옮길 것이 없다. gh 가 이미 로그인돼 있다. 옛 `github.com` 인터넷
비밀번호 항목은 더 이상 읽히지 않는다.
