# 0033. Nix 빌드가 업데이트될 때마다 키체인 창이 뜨지 않게

**결정** — 비밀은 계속 키체인에 둔다. 대신 Nix 빌드 바이너리가 바뀔 때마다 키체인이
그 바이너리를 다시 묻지 않게 한다.

- GitHub HTTPS 자격증명: nixpkgs git 의 `osxkeychain` 대신 `gh auth git-credential`
  (`home/darwin.nix`). gh 는 Apple 서명의 `/usr/bin/security` 로 키체인에 저장하므로
  업데이트와 무관하다.
- `gws`: 키는 그대로 키체인에 두고, 읽는 프로그램을 Apple 서명의 `/usr/bin/security`
  하나로 고정한다. macOS 의 `gws` 는 래퍼다(`pkgs/gws/package.nix`). 래퍼가
  `/usr/bin/security` 로 키를 읽어 FIFO 로 넘기고, gws 는 파일 백엔드로 그 FIFO 를
  읽을 뿐 키체인을 직접 부르지 않는다. 모든 맥에서 같다.
- `supabase`: 같은 방식이다. 상류 릴리스 바이너리가 ad-hoc 서명이라 릴리스마다
  cdhash 가 바뀐다. macOS 의 `supabase` 는 래퍼다(`pkgs/supabase-cli/keychain.nix`).
  CLI 는 항상 `SUPABASE_NO_KEYRING=1` 로 돌고, 래퍼가 `/usr/bin/security` 로 읽은
  토큰을 `SUPABASE_ACCESS_TOKEN` 으로 넘긴다. `login` 은 CLI 가 파일에 쓴 토큰을
  키체인 항목(`Supabase CLI`, 계정 = 프로필 이름)으로 옮기고 파일을 지운다. `logout`
  은 CLI 의 확인·파일 삭제 뒤 같은 항목을 지운다. 기본 제공 프로필만 계정 이름을
  알 수 있어 YAML 프로필 파일에는 토큰을 넣지 않는다.
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

supabase 3.3.0 도 같은 로그를 남겼다. 항목은 이미 `/usr/bin/security` 를 믿었지만,
CLI 가 스스로 읽으므로 그 믿음이 쓰이지 않았다:

```
displaying keychain prompt for /nix/store/4nvs…-supabase-cli-3.3.0/bin/supabase
  ACL: /usr/bin/security, …-supabase-cli-3.2.0/bin/supabase [cdhash H"8011…"]
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

**읽는 쪽을 바꾸지 않는다.** 키체인이 묻는 것은 "누가 읽느냐" 다. 그 "누구" 를
업데이트로 바뀌지 않는 프로그램으로 고정하면 두 관문 모두 한 번 통과한 뒤로는
다시 묻지 않는다. gh 는 처음부터 `/usr/bin/security` 로 저장하고 읽는다.

gws 는 키를 스스로 Security.framework 로 읽으므로 래퍼를 둔다:

1. `/usr/bin/security find-generic-password -s gws-cli -w` 로 키를 셸 변수에 읽는다.
   `/usr/bin/security` 는 `apple-tool:` 파티션이라 Nix 가 다시 빌드해도 그대로다.
2. 32바이트 base64 키인지 gws 를 띄우기 **전에** 확인한다. gws 는 복호화에 실패하면
   `credentials.enc` 를 지운다(`auth.rs`).
3. 키를 모드 0600 FIFO 로 fd 3 에 넣고, `~/.config/gws/.encryption_key` 를
   `/dev/fd/3` 을 가리키는 심볼릭 링크로 둔다. gws 는
   `GOOGLE_WORKSPACE_CLI_KEYRING_BACKEND=file` 로 그 파일을 읽는다. 키는 디스크에도
   인자 목록에도 남지 않는다. 파이프 대신 FIFO 인 것은 gws 가 그룹·기타가 읽을 수
   있는 키 파일에 경고를 찍는데, macOS 에서는 파이프의 모드를 바꿀 수 없어서다.
   FIFO 는 설정 폴더 안에 만든다. 설정 폴더는 gws 와 같은 규칙으로 고르고(변수,
   `~/.config/gws`, 옛 `~/Library/Application Support/gws` 순), 실제 경로로 풀어 그
   경로만 쓴다. 그 폴더가 이 사용자의 것이고 다른 사람이 접근할 수 없는지, 부모
   폴더도 다른 사용자가 바꿔치기할 수 없는지(이 사용자나 root 소유, 남이 쓸 수 있으면
   root 소유의 sticky) 먼저 확인한다. 공유 `TMPDIR` 아래라면 다른 프로세스가
   디렉터리를 바꿔치기해 키를 받아 갈 수 있다.
4. 그 링크는 실행할 때마다 되살린다. 래퍼를 거치지 않은 gws(키체인 모드)는 키를
   읽은 뒤 이 경로를 지우고, 링크가 없을 때 파일 모드 gws 는 새 키를 만들어
   기존 자격증명을 못 쓰게 만든다.
5. 키체인이 잠겨 있으면 읽기 자체가 잠금 해제 창을 띄운다. 그래서 먼저
   `keychain-unlocked`(`pkgs/keychain-unlocked`, `SecKeychainGetStatus`) 로 잠금
   여부만 보고, 잠겼으면 창 없이 실패한다. supabase 래퍼는 토큰 없이 실행만 하고
   알린다.
   `security show-keychain-info` 는 잠긴 키체인에서 창을 띄우므로 쓰지 않는다.
   `gws auth logout` 은 키를 읽지 않으므로 이 확인 없이 바로 넘긴다. 항목이 없거나
   키체인이 잠겨 있어도 로그아웃은 된다.
6. 항목이 없고 `credentials.enc` 도 없으면(새 기기) 래퍼가 키를 만들어
   `/usr/bin/security -i` 의 stdin 으로 `-T /usr/bin/security` 항목을 만든다. 항목이
   없는데 `credentials.enc` 가 있으면 키를 새로 만들지 않고 멈춘다.

## 다른 길은 왜 안 했나

- **"항상 허용" 을 누른다** — 다음 빌드까지만 간다.
- **`-A` 만** — 파티션 관문에서 여전히 막힌다. 위 실험이 그것이다.
- **로컬 인증서로 다시 서명** — Developer ID 가 아닌 서명은 여전히 `cdhash:`
  파티션으로 분류된다. 고정되지 않는다.
- **gws 를 파일 백엔드로** — 키가 디스크의 0600 파일로 나온다. 비밀은 키체인에
  둔다는 결정과 맞지 않는다.
- **서버 맥에서 switch 마다 파티션 목록을 새 cdhash 로 바꾸기** — 한동안 이렇게
  했다. 자동 로그인 비밀번호가 있는 서버 맥에서만 되고, 랩탑은 다시 빌드할 때마다
  창이 떴다.

## 한계

- 래퍼를 거치지 않은 gws·supabase(스토어 경로를 직접 실행) 는 여전히 키체인을 직접
  읽어 창을 띄울 수 있다. PATH 의 `gws`·`supabase` 는 래퍼다.
- supabase 의 `unlink` 는 키체인을 보지 않으므로, 옛 Go CLI 가 프로젝트별로 남긴
  `Supabase CLI` 항목이 있다면 지우지 않는다. `logout` 은 지운다.
- 키체인 항목이 다른 32바이트 키로 바뀌면 래퍼는 알아채지 못하고, gws 가 복호화에
  실패해 `credentials.enc` 를 지운다. 래퍼는 항목이 없을 때 키를 만들지 않으므로
  사람이 항목을 지우거나 바꾸지 않는 한 생기지 않는다.

## 한 번만 하는 이전

`/usr/bin/security` 를 아직 믿지 않는 항목(gws 가 Security.framework 로 만든 원래
항목) 은 래퍼가 처음 읽을 때 창이 한 번 뜬다. "항상 허용" 을 누르면 그 뒤로는
`/usr/bin/security` 가 바뀌지 않으므로 다시 뜨지 않는다. 키체인 비밀번호 없이 이
한 번을 미리 없앨 방법은 없다. 서버 맥의 항목은 예전 이전 때 `security -i` 로
다시 만들어 이미 `/usr/bin/security` 를 믿는다.

GitHub 쪽은 옮길 것이 없다. gh 가 이미 로그인돼 있다. 옛 `github.com` 인터넷
비밀번호 항목은 더 이상 읽히지 않는다.
