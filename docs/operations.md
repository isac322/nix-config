# 운영

손으로 해야 하는 절차만 모았다. 왜 이런 절차가 남아 있는지는 각 절이 가리키는
[결정 기록](decisions/)에 있다.

## 기기 간 독립성

각 기기는 자기 설정을 스스로 빌드하고 전환한다. 서버는 맥에 전혀 의존하지 않는다.
다만 두 가지를 기억할 것.

**`flake.lock`은 공유 상태다.** `switch`는 lock을 건드리지 않지만
`nix flake update`는 다시 쓴다. 기기마다 각자 update를 돌리면 lock이 갈라지고,
[단일 레포로 묶은 의미](decisions/0001-single-repo-single-lock.md)가 사라진다.
한 기기에서 update → commit → push 하고 나머지는 pull → switch 한다.

**평가는 크로스 플랫폼이지만 빌드는 아니다.** 맥에서 `nixosConfigurations.server`를
평가해 drv 를 얻는 것은 되지만 realise 는 안 된다 (`extra-platforms` 가 비어 있고
`/etc/nix/machines` 도 없다). 그래서 원격 switch 에 `--build-host` 를 준다. 맥에서
서버를 직접 빌드하고 싶다면 Determinate 의 네이티브 리눅스 빌더를 켠다.
`system-features` 에 `apple-virt` 가 이미 있으므로 Apple Silicon 에서는
aarch64-linux 가 나온다 — 서버와 같은 아키텍처다.

```nix
# modules/darwin.nix 또는 특정 호스트에서
determinateNixd.builder = {
  state = "enabled";
  memoryBytes = 8589934592;  # 8 GiB
  cpuCount = 4;
};
```

## 선언형 Borg 서버 백업

NixOS 서버와 Darwin 서버는 둘 다 Borg를 설치하고 같은
`local.borgBackup` 모듈을 쓴다. `local.borgBackup.repository`의 기본값은 `null`이며,
이 값이 `null`인 동안에는 systemd timer나 launchd daemon을 만들지 않는다. 모듈은
저장소도 자동으로 초기화하지 않는다.

저장소 주소와 비밀 파일 경로는 호스트마다 다르므로 각 서버의 호스트 설정에 넣는다.
아래 자리표시자를 실제 운영 값으로 바꾼다.

```nix
# NixOS server의 호스트 설정
local.borgBackup = {
  repository = "<NixOS 서버가 사용할 Borg repository>";
  scheduleTime = "03:00";
  passphraseFile = "<NixOS 서버의 런타임 passphrase 파일 경로>";
  sshIdentityFile = "<NixOS 서버의 SSH 개인키 파일 경로>";
  keepDaily = 7;
  keepWeekly = 4;
  keepMonthly = 6;
};
```

```nix
# Darwin server의 호스트 설정
local.borgBackup = {
  repository = "<Darwin 서버가 사용할 Borg repository>";
  scheduleTime = "03:00";
  passphraseFile = "<Darwin 서버의 런타임 passphrase 파일 경로>";
  sshIdentityFile = "<Darwin 서버의 SSH 개인키 파일 경로>";
  keepDaily = 7;
  keepWeekly = 4;
  keepMonthly = 6;
};
```

`scheduleTime`은 서버 현지 시각의 24시간제 `HH:MM` 값이다. 보존 기본값은
`keepDaily = 7`, `keepWeekly = 4`, `keepMonthly = 6`이며 호스트별로 바꿀 수 있다.
`passphraseFile`과 `sshIdentityFile`에는 런타임 파일 경로만 선언한다. passphrase와
SSH 개인키의 내용은 Nix 설정이나 Nix store에 들어가지 않는다. 해당 파일은 Borg를
실행하는 사용자가 읽을 수 있는 권한으로 서버에 따로 배치한다.

처음 활성화하기 전에 선언한 `repository`를 같은 자격증명으로 **직접 `borg init`**
한다. 암호화 방식과 저장소 주소는 운영자가 정하며, 이 레포는 어느 값도 미리
정하지 않는다. 초기화와 비밀 파일 배치를 마친 뒤 해당 서버에서 switch 한다.

```sh
# NixOS server
sudo nixos-rebuild switch --flake /etc/nix-darwin#server

# Darwin server
sudo darwin-rebuild switch --flake /etc/nix-darwin#bhyoo-macbook-pro
```

활성화 뒤에는 매일 `scheduleTime`에 홈 디렉터리에서 `.`을 아카이브한다. 따라서
공유 제외 목록 `/etc/borg-exclude`의 홈 기준 패턴이 그대로 적용된다. `create`가
성공한 경우에만 같은 실행에서 `prune`을 `keepDaily`, `keepWeekly`, `keepMonthly`
값으로 적용하고, 이어서 `compact`를 실행한다. `create`가 실패하면 `prune`과
`compact`는 실행하지 않는다.

MBA의 Vorta는 서버 job과 별개다. Nix activation은
`~/Library/Application Support/Vorta/settings.db`가 없을 때만 첫 실행용
`~/.vorta-init.json`을 놓는다. `settings.db`가 이미 있으면 기존 Vorta profile과
설정을 보존하며 bootstrap으로 덮어쓰지 않는다.

## GPG 키 가져오기

커밋 서명과 SSH 접속과 Arch 패키징이 [모두 이 키 하나를
쓴다](decisions/0004-one-gpg-key-for-ssh-signing-packaging.md). 키가 없으면 커밋이
실패하므로, activation 이 그 사실과 아래 명령을 함께 출력한다. **키는 자동
생성하지 않는다** — 이유는 결정 기록에 있다.

```sh
gpg --import secret.asc            # 개인키
gpg --import-ownertrust trust.asc  # 선택. 신뢰 설정 복원
gpg --edit-key bhyoo@bhyoo.com     # trust, 5, y, quit — 내 키로 표시

gpg-ssh-authorize                  # 인증 서브키를 SSH 에 노출시킨다
ssh-add -L                         # 키가 뜨면 성공
```

`gpg-ssh-authorize` 는 switch 때마다 자동으로 돌고 이미 표시된 키는 건드리지
않으므로 두 번 돌아도 조용하다. 키를 switch 사이에 가져왔다면 PATH 에도 있으니 그
자리에서 실행하면 된다.

키가 아직 없다면 인증 서브키를 붙여서 만들고, 다른 기계로 내보낸다. **사용자 ID 는
반드시 `Byeonghoon Yoo <bhyoo@bhyoo.com>`** — `home/common.nix` 의 이름·이메일과
정확히 같아야 git 이 키를 찾는다.

```sh
gpg --full-generate-key            # ed25519
gpg --edit-key bhyoo@bhyoo.com     # addkey → ECC → Authenticate

gpg --armor --export-secret-keys bhyoo@bhyoo.com > secret.asc
gpg --export-ownertrust > trust.asc
```

GitHub 에는 공개키를 GPG key 로 등록하면 커밋 검증이 되고, 접속용으로는 인증
서브키를 SSH key 로 따로 등록한다 (`gpg --export-ssh-key bhyoo@bhyoo.com`).

## 서버 맥에 SSH 로 들어갈 수 있게

서버 역할의 맥만 해당한다. 그 기계의 sshd 는 [키만 받고 암호는 두 경로 모두
막혀 있어서](decisions/0026-sshd-on-the-server-mac.md), `authorized_keys` 가
비어 있으면 아무도 못 들어간다. 첫 switch 가 정확히 그 상태다. **switch 는 이걸
알려주지 않는다** — 결정 기록에 이유가 있다.

**그 기계의 콘솔에서** 한 번 한다. 뚜껑을 열고 로그인해야 한다는 뜻이다 — SSH 로
하려면 SSH 가 이미 돼야 하니까.

```sh
mkdir -p ~/.ssh && chmod 700 ~/.ssh
ssh-add -L >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

`ssh-add -L` 이 뱉는 것은 [다른 기계가 쓰는 것과 같은
키](decisions/0004-one-gpg-key-for-ssh-signing-packaging.md)라, 기계 사이에 옮길
것이 없다. 아무것도 안 나오면 순서가 뒤집힌 것이다 — 위의 GPG 키부터 가져온다.

## WireGuard (서버 맥)

서버 역할의 맥만 해당한다. 랩탑은 App Store 앱을 그대로 쓰고 여기는 아무 절차도
없다. 서버 맥은 [앱 대신 루트 데몬](decisions/0029-wireguard-as-a-daemon-on-the-server-mac.md)
이 `wg-quick` 을 돌리고, 그 설정 파일만 손으로 놓는다 — **개인키가 들어 있어서
레포에 안 들어간다.**

인터페이스 이름은 레포에 안 적는다 — **파일 이름이 곧 인터페이스 이름**이고,
데몬은 `/etc/wireguard/*.conf` 를 전부 올린다. 이름을 양쪽에 두면 갈라질 자리만
생긴다.

```sh
sudo install -d -m 0700 /etc/wireguard
sudo tee /etc/wireguard/<iface>.conf >/dev/null <<'EOF'
[Interface]
PrivateKey = <...>
Address = 10.222.0.8/32

[Peer]
PublicKey = <...>
AllowedIPs = 10.222.0.0/24
Endpoint = <host>:<port>
PersistentKeepalive = 25
EOF
sudo chmod 0600 /etc/wireguard/<iface>.conf
sudo launchctl kickstart -k system/org.nixos.wireguard
```

확인:

```sh
sudo wg show
cat /var/log/wireguard.log
cat /var/run/wireguard-addresses   # 데몬이 발행한 주소. Orca·Camofox·noVNC 가 읽는다
```

파일이 없으면 데몬은 터널을 안 올리고 그 사실을 로그에 남긴다 — 설정이 깨지지는
않는다. `wg-quick up` 은 인터페이스를 올리고 끝나므로 데몬이 계속 떠 있지 않는
것이 정상이다. 살아 있게 하는 것은 wg-quick 이 떼어 놓는 `wireguard-go` 다.

## Nix 고정 Agent Skills (모든 노드)

검토한 공개 스킬은 `skills update`가 아니라 `flake.lock`으로 버전을 고정한다.
`home/agent-skills.nix`가 switch 때 `skills add --global --agent amp --copy`와 같은
디렉터리 내용을 `~/.agents/skills`에 복사한다.

- `Gentleman-Programming/gentle-ai`: `comment-writer`
- `blader/humanizer`: `humanizer`
- `obra/superpowers`: `receiving-code-review`
- `softaworks/agent-toolkit`: `writing-clearly-and-concisely`

`humanizer`는 repository root의 `SKILL.md`가 canonical entrypoint라서 repository
전체가 설치된다. 나머지는 각 repository의 선택한 skill directory만 설치된다.

네 upstream만 갱신하고 배포하는 절차:

```sh
nix flake update gentle-ai humanizer superpowers agent-toolkit
nix flake check
darwin-rebuild build --flake .#<hostname>
sudo darwin-rebuild switch --flake .#<hostname>
```

새 input을 처음 추가할 때는 `nix flake lock`이 기존 input을 재해석하지 않고 누락된
lock node만 만든다. 이후에는 위처럼 이름을 지정해 갱신한다. 설치 내용의 최종
authority는 `flake.lock`이므로 이 네 이름을 `skills update`나 evolve worker로 직접
수정하지 않는다.

SkillClaw의 주기 sync와 로그인 shell은 이 이름들을
`SKILLCLAW_SYNC_SKIP_PULL`로 **pull에서만 제외하고 push에는 포함한다.** 따라서
cloud에 남은 이전 revision이 switch 직후의 Nix 복사본을 되돌리지 않으며, 새로
고정한 revision은 다음 sync에서 공유 backend로 올라간다.


## SkillClaw 공유 스킬 (모든 노드)

`skillclaw` 클라이언트와 5분 주기 동기화는 모든 노드에 설치된다. 저장소는 이
repository가 새로 띄우지 않고 사용자가 이미 운영하는 S3-compatible backend를
사용한다. 모든 노드에서 같은 endpoint, bucket, region과 자격증명을 다음 0600 파일에
넣는다.

```sh
mkdir -p ~/.config/skillclaw
cat > ~/.config/skillclaw/shared.env <<'EOF'
SKILLCLAW_STORAGE_ENDPOINT=https://s3.example.com
SKILLCLAW_STORAGE_BUCKET=<existing bucket>
SKILLCLAW_STORAGE_REGION=<region>
SKILLCLAW_STORAGE_ACCESS_KEY=<access key>
SKILLCLAW_STORAGE_SECRET_KEY=<secret key>
EOF
chmod 600 ~/.config/skillclaw/shared.env
```

bucket은 미리 존재해야 하며 자격증명에는 그 bucket의 object read/write 권한이
필요하다. endpoint와 실제 자격증명은 Nix store에 넣지 않는다.

모든 노드와 evolve worker가 **같은 bucket 하나**와 group `omp`를 사용한다. 노드별
bucket은 만들지 않는다.

각 노드에서 로컬 proxy까지 쓰려면 별도로 0600인
`~/.config/skillclaw/llm.env`를 둔다. 이 파일은 노드마다 달라도 된다.

```sh
cat > ~/.config/skillclaw/llm.env <<'EOF'
SKILLCLAW_LLM_PROVIDER=custom
SKILLCLAW_LLM_API_BASE=https://example.invalid/v1
SKILLCLAW_LLM_API_KEY=<API key>
SKILLCLAW_LLM_MODEL_ID=<model id>
SKILLCLAW_LLM_API_MODE=responses
# 선택: evolve worker만 다른 모델을 쓸 때
# SKILLCLAW_EVOLVE_MODEL=<model id>
EOF
chmod 600 ~/.config/skillclaw/llm.env
```

`responses`를 받지 않는 OpenAI-compatible endpoint면 마지막 값을 `chat`으로 바꾼다.
Nix store에는 어느 비밀도 들어가지 않는다. 런타임 wrapper가 두 파일을 읽어
`~/.skillclaw/config.yaml`을 0600으로 다시 만들며, SkillClaw의 로컬 스킬 디렉터리는
여러 하네스가 읽는 Agent Skills 표준 위치 `~/.agents/skills`다. Claude Code 전용
디렉터리는 만들거나 동기화하지 않는다.

확인:

```sh
skillclaw config show
skillclaw skills list-remote
skillclaw-sync
curl http://127.0.0.1:30000/healthz   # llm.env를 둔 노드
```

서버 맥은 같은 외부 S3 backend를 사용하는 evolve worker 하나만 추가로 실행한다.

```sh
launchctl print gui/$(id -u)/org.nix-community.home.skillclaw-evolve
tail -f ~/Library/Logs/skillclaw-evolve.log
```

SkillClaw의 `auto_pull_on_start`와 원격 reload polling은 끈다. 둘은 cloud manifest에
없는 로컬 디렉터리를 mirror 삭제하는 경로라, 다음 5분 동기화 전에 OMP가 만든 스킬을
잃을 수 있다. 여기서는 `skills sync`의 incremental pull 뒤 push만 사용하고, proxy는
각 요청에서 로컬 디렉터리 변경을 다시 읽는다.

동기화는 upstream의 `pull` 뒤 `push` 의미를 그대로 쓴다. 서로 다른 노드에서 **같은
이름의 스킬을 동시에 수정하면 자동 merge하지 않고 마지막 업로드가 이긴다.** 같은
스킬을 병렬 편집하지 않는 것이 운영 규칙이다.


## 자동 로그인 (서버 맥)

Orca 런타임과 headful Camofox 가 Aqua 세션을 요구하고, LaunchAgent 는 세션이
만들어질 때만 뜬다
([0028](decisions/0028-orca-runtime-on-the-server-mac.md),
[0031](decisions/0031-camofox-native-macos-over-wireguard.md)).
sshd·WireGuard·키 매핑·noVNC 는 루트 데몬이라 이게 필요 없다.

**손으로 하는 것은 파일 하나다.** 나머지는 switch 가 한다 — `/etc/kcpassword`
생성과 FileVault 끄기 둘 다.

```sh
sudo install -d -m 0700 /var/lib/nix-darwin
sudo tee /var/lib/nix-darwin/login-password >/dev/null <<'EOF'
<그 계정의 로그인 비밀번호>
EOF
sudo chmod 0600 /var/lib/nix-darwin/login-password
```

그리고 switch. 이 파일이 있는 것 자체가 **FileVault 를 끄는 동의**다 — 파일이
없는 기계에서는 activation 이 무엇을 쓰라고만 말하고 아무것도 건드리지 않는다.

FileVault 는 켜져 있으면 자동 로그인이 불가능하다. 사전 부팅 잠금 해제가
네트워크보다 먼저라 무인 재부팅이 없는 키보드를 기다리며 멈춘다. 물리적으로
안전한 기계에서만 할 거래다.

`fdesetup disable` 은 man 페이지에 비대화형 인자가 없어서 stdin 으로 plist 를
넣는다. **30초 알람으로 감싸 두었다** — 답할 수 없는 프롬프트에서 activation 이
멈추는 것이 보고하고 넘어가는 것보다 나쁘기 때문이다. 실패하면 콘솔에서 할
명령을 낸다.

```sh
fdesetup status              # "FileVault is Off." 가 목표
defaults read /Library/Preferences/com.apple.loginwindow autoLoginUser
ls -l /etc/kcpassword
```

## GPG passphrase (서버 맥)

서버 역할의 맥만 해당한다. 자동 로그인이 로그인 키체인을 잠긴 채로 두고, 잠긴
키체인은 서명과 SSH 를 통째로 멈춰 세운다
([0030](decisions/0030-gpg-passphrase-without-a-console.md)). 그래서 두 가지가
자동으로 돈다 — LaunchAgent 가 키체인을 열고, `pinentry-keychain` 이 거기서
passphrase 를 읽는다.

**딱 한 번**, 키체인에 값을 넣어줘야 한다. 대화형 SSH 세션에서 한다 — 비대화형은
`~/.zshrc` 를 안 읽어서 `GPG_TTY` 가 없고, 그러면 프롬프트가 안 뜬다.

```sh
ssh <서버>
echo x | gpg --yes -o /dev/null -s -     # Passphrase: 가 뜨면 입력
```

친 값은 그 자리에서 키체인에 저장되고, 그 뒤로는 재부팅을 넘겨서도 조용히 쓰인다.

확인:

```sh
security find-generic-password -s GnuPG | grep acct   # 항목
cat ~/Library/Logs/pinentry-keychain.log              # 비어 있으면 정상
```

그 로그는 **문제가 있을 때만** 쓴다. 조회 실패, tty 없음, 저장 실패가 남는다.

## Linear MCP (모든 호스트)

Home Manager 가 `~/.omp/agent/mcp.json`에 Linear의 공식 remote MCP endpoint
`https://mcp.linear.app/mcp`를 항상 선언한다. transport는 streamable HTTP이고,
인증은 Linear의 OAuth 2.1 흐름을 쓴다. API key나 access token을 Nix 설정, Nix
store, `mcp.json`에 넣지 않는다.

처음 한 번 OMP 안에서 인증한다.

```text
/mcp reauth linear
/mcp test linear
```

첫 명령은 Linear 로그인·승인 페이지를 열고, 성공한 OAuth credential은 OMP의 auth
storage에 endpoint URL 기준으로 저장한다. 서버 맥에서 실행했다면 noVNC로 그 Aqua
세션의 브라우저를 열어 승인한다. 이후 OMP 재시작과 Home Manager switch를 넘어
재사용하며, definition-only MCP 선언이라 OMP 17.3.4는 read-only Home Manager
symlink에 auth stanza를 다시 쓰지 않는다.

계정을 바꾸거나 권한을 완전히 초기화할 때만 다음을 실행한다.

```text
/mcp unauth linear
/mcp reauth linear
```

`/mcp list`에서 `linear`가 보이고 `/mcp test linear`가 연결과 tool 목록을 반환하면
끝이다.

## Orca 런타임 (서버 맥)

`orca serve` 가 LaunchAgent 로 돈다
([0028](decisions/0028-orca-runtime-on-the-server-mac.md)). 선언은 끝났고 아래는
확인과 일회성 절차다.

**로그와 페어링 링크.** 창이 없는 기계라 준비 완료 줄은 로그에만 남는다.

```sh
tail -f ~/Library/Logs/orca-serve.log
```

`orca_server_ready` 한 줄에 `boundEndpoint`, `advertisedEndpoint`, 그리고
`pairing.url` 이 들어 있다. 그 URL 을 클라이언트의 Settings > Remote Orca
Servers > Add Server 에 붙인다. **URL 자체가 접근 권한**이니 비밀처럼 다룬다.
페어링한 기기의 키는 프로필에 남아서 재시작해도 다시 안 해도 된다.

```sh
launchctl print gui/$(id -u)/org.nix-community.home.orca-serve   # 상태
orca status --json                                               # 런타임 쪽에서 본 상태
```

**부팅 확인.** 자동 로그인이 실제로 걸렸는지가 곧 Orca 가 뜨는지다. 재부팅하고,
**아무것도 안 하고**, 랩탑에서:

```sh
ssh bhyoo@<주소> 'launchctl print gui/$(id -u)/org.nix-community.home.orca-serve | head -5'
```

`state = running` 이면 끝이다. `Could not find service` 면 Aqua 세션이 안 생긴
것이므로 위의 자동 로그인 두 조각을 다시 본다.

**에이전트 계정은 서버 쪽에서.** 원격 세션은 서버의 PATH·홈·자격증명을 쓰고
클라이언트의 것을 안 쓴다. 그래서 원격 클라이언트에서는 Add account 가 아예
막혀 있다.

```sh
orca account add --agent claude
orca account add --agent codex
orca account list
```

**포트는 0.0.0.0 에 열린다.** `--pairing-address` 는 광고 주소만 바꾸고 바인딩을
좁히는 플래그가 없다. 즉 그 기계가 붙어 있는 모든 네트워크에서 6768 이 열려
있으므로, 막는 것은 런타임이 아니라 네트워크 쪽 일이다. 공개 인터넷으로
포워딩하지 않는다.

## Camofox + noVNC (서버 맥)

Camofox API, DeskPad, macVNC는 `bhyoo`의 Aqua LaunchAgent가 함께 감독한다.
DeskPad 1.3.2가 전용 가상 모니터를 만들고, displayplacer 1.4.0이 그 화면을
1920×1080 main display로 배치한다. 상류 `LibVNC/macVNC`는 ScreenCaptureKit으로
그 디스플레이 전체를 캡처해 `127.0.0.1:5901`의 VNC로 내보낸다. root noVNC
LaunchDaemon은 이 loopback VNC를 WireGuard 주소의 HTTPS WebSocket으로 중계한다
([0031](decisions/0031-camofox-native-macos-over-wireguard.md)). 구성요소는 모두
고정한 upstream release 또는 source revision이다. 상류 Camofox Linux/Xvfb
플러그인은 계속 끈다.

native Screen Sharing은 최종 data path가 아니다. 현재 역할은
`local.camofox.retireScreenSharing = true`라 switch가 그 job을 disable·stop한다.
port 5900의 전체 데스크톱 경로를 migration console로 다시 써야 할 때만 이 값을
명시적으로 `false`로 바꾸며, noVNC 자체는 어느 상태에서도 port 5900을 쓰지 않는다.

noVNC framebuffer는 전용 가상 디스플레이 전체다. desktop·Dock·menu bar와 그
디스플레이 위에 놓인 모든 앱이 보이고 키보드와 포인터도 Aqua 세션 좌표로 전달된다.
따라서 다른 앱을 이 디스플레이로 옮기지 않는다. 여러 `userId`의 BrowserContext는
쿠키와 웹 스토리지를 나누지만 화면·포커스·키보드·마우스·클립보드는 공유한다.
noVNC는 사용자별 접속점이 아니라 신뢰된 운영자의 공용 콘솔이다.

Camofox browser는 활성 세션이 없으면 상류 기본 idle timeout인 약 5분 뒤 종료된다.
Node API daemon, DeskPad, macVNC, noVNC는 계속 실행되고 다음 요청이 Camoufox를 다시
띄운다.

LaunchAgent가 성공하면 로그에 macVNC의 다음 줄이 남고 port 5901이 열린다.

```text
Listening for VNC connections on TCP port 5901
```

이 줄이 없으면 noVNC를 반복해서 재접속하지 말고
`~/Library/Logs/camofox-browser.log`에서 DeskPad 준비, displayplacer layout,
Screen Recording, Accessibility 오류를 확인한다. DeskPad, macVNC, Camofox API
daemon 중 하나가 끝나면 LaunchAgent가 나머지도 끝내고 전체 스택을 재시작한다.

**주소.** API는 이 Mac 안에서만 열고, 원격 화면은 WireGuard 주소의 HTTPS noVNC로
연다.

```sh
wg_ip=$(sed -n '1p' /var/run/wireguard-addresses)
printf 'Camofox API: http://127.0.0.1:9377\n'
printf 'VNC backend: 127.0.0.1:5901\n'
printf 'noVNC:       https://%s:6080/vnc.html\n' "$wg_ip"
```

noVNC 인증에는 username이 없다. 브라우저가 묻는 VNC 비밀번호는
`/var/lib/nix-darwin/camofox-vnc-password`의 8자리 값이다. activation은 이 원문을
표준 LibVNCServer 형식으로 변환해 macVNC가 읽는 `/var/lib/camofox/vnc-auth`를
`bhyoo:staff 0400`으로 만든다. auth 파일은 로그인 입력값이 아니다.

인증서는 `/var/run/wireguard-addresses`의 현재 주소를 IP SAN으로 넣어 런타임에
`/var/lib/nix-darwin/camofox-novnc-tls` 아래에 생성하는 self-signed 인증서다.
첫 접속에서는 브라우저의 인증서 경고를 확인하고 진행한다. WireGuard 주소가 바뀌면
noVNC가 재시작되며 새 IP용 인증서를 만든다.

**새 서버 또는 privacy 권한 초기화 때만.** 새 macVNC에 Screen Recording과
Accessibility 권한이 없으면 migration 동안
`local.camofox.retireScreenSharing = false`로 바꾼다. 이 첫 switch는 native Screen
Sharing을 migration console로 남기지만 legacy 8자 VNC 인증은 제거한다. 먼저
Screen Sharing의 macOS 계정 인증이 실제로 동작하는지 확인한다. 서버의 port 5900은
loopback으로 제한했으므로 다른 Mac에서 SSH tunnel을 연다.

```sh
ssh -N -L 15900:127.0.0.1:5900 bhyoo@<server-WireGuard-IP>
open 'vnc://127.0.0.1:15900'
```

Screen Sharing.app에는 username `bhyoo`와 **macOS 로그인 비밀번호**를 입력한다.
`/var/lib/nix-darwin/camofox-vnc-password`의 8자 값이 아니다. 원격 포인터와
키보드로 System Settings를 열 수 있음을 확인하지 못하면 첫 switch를 실행하지 않는다.

```sh
sudo darwin-rebuild switch --flake /etc/nix-darwin#bhyoo-macbook-pro
```

첫 switch 뒤 migration console에서 다음 앱을 두 privacy pane에 모두 추가하고
허용한다.

```text
~/Applications/Home Manager Apps/macVNC.app
```

- System Settings > Privacy & Security > Screen & System Audio Recording
- System Settings > Privacy & Security > Accessibility

그 뒤 LaunchAgent를 재시작한다. macVNC는 권한이 없을 때 조용히 view-only로
후퇴하지 않고 종료하므로, port와 로그를 함께 확인한다.

```sh
launchctl kickstart -k gui/$(id -u)/org.nix-community.home.camofox-browser
tail -n 100 ~/Library/Logs/camofox-browser.log
nc -z 127.0.0.1 5901
```

새 HTTPS noVNC 세션에서 인증, 전용 1920×1080 디스플레이 전체, 화면 갱신,
키보드와 포인터 입력을 모두 확인한다. 진단용 앱을 그 디스플레이로 옮겼을 때
noVNC에 보이고 입력도 전달되는 것이 정상이다. 관찰만 진단하려면
`local.camofox.vncViewOnly = true`를 쓸 수 있지만, 그 상태에서는 migration
console을 폐기하지 않는다.

입력까지 검증했으면 현재 역할의 기본 상태인 다음 값으로 되돌리고 다시 switch한다.

```nix
local.camofox = {
  enable = true;
  retireScreenSharing = true;
};
```

```sh
sudo darwin-rebuild switch --flake /etc/nix-darwin#bhyoo-macbook-pro
nc -z 127.0.0.1 5900 && echo 'unexpected Screen Sharing listener'
nc -z 127.0.0.1 5901
```

macVNC 패키지 바이너리가 바뀌면 macOS가 privacy 권한을 다시 요구할 수 있다. 새
generation에서 noVNC 입력까지 재검증하기 전에는 Screen Sharing retirement를 함께
진행하지 않는다.

Camofox API는 loopback 밖에서 접근할 수 없다. OMP가
`~/.omp/agent/mcp.json`에 선언된 `camofox-browser-mcp-session omp`를 시작하면
wrapper가 현재 OMP transcript breadcrumb의 UUID를 `sessionKey`로 만들고, 그 아래의
stdio 어댑터가 기존 API로 전달한다. `CAMOFOX_USER_ID=omp`는 고정되어 쿠키와
localStorage는 공유하지만, 탭 목록과 탭 조작 권한은 OMP 대화별로 갈린다. OMP를
`--resume`해 같은 transcript를 열면 같은 UUID와 탭 namespace를 다시 쓴다.
상류 1.13.1은 탭을 만들 때만 `sessionKey`를 썼고 list와 `tabId` 조작은 같은
`userId`의 모든 group을 검색했다. wrapper만 바꾸면 격리가 아니므로 Nix 패키지가
MCP의 모든 탭 요청에 `sessionKey`를 전달하고 REST 서버도 그 group 안에서만 탭을
찾도록 함께 패치한다.

같은 wrapper를 Claude Code와 Codex에도 등록할 수 있다. 별도 플러그인은 필요 없다.

```sh
claude mcp add --scope user camofox \
  -e CAMOFOX_BASE_URL=http://127.0.0.1:9377 \
  -e CAMOFOX_USER_ID=omp \
  -- camofox-browser-mcp-session claude

codex mcp add camofox \
  --env CAMOFOX_BASE_URL=http://127.0.0.1:9377 \
  --env CAMOFOX_USER_ID=omp \
  -- camofox-browser-mcp-session codex
```

Claude Code는 stdio MCP 자식에게 `CLAUDE_CODE_SESSION_ID`를 전달하며 resume 때도 같은
값을 유지하므로 정확히 대화별 namespace가 된다. 현재 Codex 0.147.0은 thread ID를
MCP 자식 환경에 전달하지 않는다. 따라서 Codex는 adapter 프로세스마다 자동 UUID를
써서 동시에 실행한 프로세스끼리는 격리되지만, 종료 후 resume까지 같은 namespace를
되찾지는 못한다. 그 보장까지 필요하면 Codex가 thread ID를 MCP 환경에 전달하도록
상류가 바뀌거나 Codex 패키지를 패치해야 한다. wrapper는 향후 `CODEX_THREAD_ID` 또는
`CODEX_SESSION_ID`가 보이면 자동으로 우선 사용한다.

noVNC는 WireGuard 주소만 사용한다. 주소 파일이 없거나 첫 줄이 비어 있으면
`0.0.0.0`이나 LAN 주소로 물러서지 않고 실패한다. launchd가 10초 간격으로 다시
부르므로 터널이 뒤에 올라오면 그때 정확한 주소에 바인딩한다.

**VNC 비밀번호.** activation이 처음 한 번만 만든 정확히 8자의 영숫자다.

```sh
sudo stat -f '%Sp %Su:%Sg %N' /var/lib/nix-darwin/camofox-vnc-password
sudo sh -c 'wc -c < /var/lib/nix-darwin/camofox-vnc-password'
sudo cat /var/lib/nix-darwin/camofox-vnc-password; printf '\n'
stat -f '%Sp %Su:%Sg %N' /var/lib/camofox/vnc-auth
wc -c < /var/lib/camofox/vnc-auth
```

master는 `-rw------- root:wheel`, runtime RFB auth 파일은
`-r-------- bhyoo:staff`, 길이는 둘 다 8이어야 한다. 출력한 master 값은 noVNC
페이지의 VNC Password 칸에 넣는다. auth 파일은 고정 DES key로 변환한 binary이므로
로그인 값으로 쓰거나 출력하지 않는다. noVNC가 아니라 loopback macVNC의
LibVNCServer가 자격증명을 검사한다.

**상태·로그·재시작.**

```sh
launchctl print gui/$(id -u)/org.nix-community.home.camofox-browser
sudo launchctl print system/org.nixos.camofox-novnc

tail -f ~/Library/Logs/camofox-browser.log
sudo tail -f /var/log/camofox-novnc.log

launchctl kickstart -k gui/$(id -u)/org.nix-community.home.camofox-browser
sudo launchctl kickstart -k system/org.nixos.camofox-novnc
```

Camofox와 VNC 백엔드는 WireGuard와 무관하게 loopback에서 시작한다. noVNC 로그의
`refusing noVNC's all-interfaces default`는 넓은 주소로 열린 것이 아니라 의도적인
실패다. 터널과 `/var/run/wireguard-addresses`를 확인한다.

**바인딩과 VNC 경계 확인.**

```sh
wg_ip=$(sed -n '1p' /var/run/wireguard-addresses)
sudo lsof -nP -iTCP:9377 -sTCP:LISTEN
sudo lsof -nP -iTCP:5901 -sTCP:LISTEN
sudo lsof -nP -iTCP:6080 -sTCP:LISTEN

printf 'loopback VNC:  '
nc -w 2 127.0.0.1 5901 | head -1
printf 'WireGuard VNC: '
nc -w 2 "$wg_ip" 5901 | head -1
```

앞의 `lsof`에는 각각 **`127.0.0.1:9377`, `127.0.0.1:5901`,
`$wg_ip:6080`만** 있어야 한다. loopback VNC는 `RFB ...` 배너를 내지만 같은
5901 포트를 WireGuard 주소로 물으면 배너가 없어야 한다. TCP listener 자체가
loopback에 묶이므로 별도 macOS Screen Sharing 설정에 의존하지 않는다.

OMP 안에서는 `/mcp list`로 `camofox`의 출처를 확인하고 `/mcp test camofox`로
stdio 어댑터와 loopback REST 데몬의 연결을 검사한다. 노출되는 도구 이름은
`mcp__camofox_*` 형태다. 어댑터는 브라우저를 새로 실행하지 않는다.

8자 제한은 RFB VNCAuth의 한계다. 그래서 5901은 loopback 전용이고, 그 앞의
6080만 WireGuard 주소에 연다. 이 두 경계가 빠지면 이 비밀번호 길이는 인터넷에
직접 노출할 만한 보안 수준이 아니다.

## RSA 호스트 키가 3072 비트일 때

sshd 를 켠 기계만 해당하고, 프로파일보다 먼저 만들어진 키가 있을 때만 해당한다.
[ssh-audit 프로파일](decisions/0027-ssh-audit-profile-shared-by-every-host.md)은
4096 을 요구하는데 macOS 가 예전에 만든 키는 3072 이고, switch 는 **이미 있는
호스트 키를 바꾸지 않는다**. 그래서 activation 이 이 사실과 아래를 출력한다.

```sh
sudo rm /etc/ssh/ssh_host_rsa_key /etc/ssh/ssh_host_rsa_key.pub
sudo darwin-rebuild switch --flake /etc/nix-darwin
```

**그 키를 신뢰하던 클라이언트는 전부 접속을 거부한다.** 각자의 `known_hosts` 에서
해당 줄을 지워야 다시 들어간다. 콘솔에서 하거나, 끊겨도 되는 세션에서 한다.

ED25519 키가 우선순위에서 앞서므로 평범한 OpenSSH 클라이언트는 어느 쪽이든
차이를 못 느낀다. 이건 그 기계가 아직 **무엇을 내놓는가**의 문제다.

ECDSA 키 파일도 남아 있을 수 있는데, `HostKey` 줄에서 이름이 빠진 이상 읽히지
않는다. 지워도 되고 둬도 된다.

## WARP service token

서버 역할의 맥만 해당한다. service token 이 없으면 등록이 브라우저를 열어 Access
로그인을 요구하는데, 사람이 없는 기계에서는 그게 막힌다. 토큰을 넣으면 상호작용
없이 등록된다.

만드는 곳: Zero Trust > Access controls > Service credentials > Service Tokens.
그리고 Team & Resources > Devices > Management 에서 **Service Auth** 기기 등록
정책으로 그 토큰을 허용해야 한다.

**비밀은 레포에 들어가지 않는다.** activation 스크립트가
`/var/lib/cloudflare-warp/service-token`을 읽고, 있으면 `auth_client_id` /
`auth_client_secret`을 mdm.xml에 넣은 뒤 파일 권한을 `0600`으로 조인다. 없으면 그
두 키 없이 쓰고 경고만 남긴다 — 설정이 깨지지 않는다.

```sh
sudo install -d -m 0700 /var/lib/cloudflare-warp
sudo tee /var/lib/cloudflare-warp/service-token >/dev/null <<'EOF'
CLIENT_ID=<...>.access
CLIENT_SECRET=<...>
EOF
sudo chmod 0600 /var/lib/cloudflare-warp/service-token
```

agenix나 sops-nix로 레포에 암호화해 넣으면 이 한 단계도 사라진다. 조직 등록
자체가 어떻게 선언적으로 들어가는지는
[0017](decisions/0017-warp-enrollment-via-mdm-xml.md).

## 캐시 푸시
`pkgs/`의 브라우저 둘을 뺀 CLI 여섯은 어떤 공개 캐시에도 없어서 기기마다 새로
컴파일한다. 그것만 Cachix 에 올린다
([0018](decisions/0018-cachix-not-flakehub-cache.md)).

처음 한 번:

```sh
nix run nixpkgs#cachix -- authtoken <token>   # cachix.org 로그인 후 발급
nix run nixpkgs#cachix -- create <cache>      # 만들면 공개키가 출력된다
```

그 URL 과 공개키를 `lib/caches.nix` 의 표시된 자리에 넣는다. **미리 채워두지
않았다.** 키가 틀린 항목은 없는 것보다 나쁘다 — substituter 로 접속은 하면서
받아온 답을 매번 버리기 때문이다.

이후 패키지가 바뀔 때마다:

```sh
nix run /etc/nix-darwin#cache-push -- <cache>
```

푸시 대상 경로는 스크립트에 **박혀 있다**. 실행 시점에 `.#` 를 해석하지 않으므로
다른 디렉터리에서 불러도 맞고, 앱을 빌드하는 것이 곧 올릴 것을 빌드하는 것이다.
`cachix` 는 클로저가 344 MiB 라 홈 패키지에 상주시키지 않고 이 앱에만 매달아
두었다 — 쓸 때만 받아온다.

## App Store 전용 앱

**랩탑만 해당한다.** KakaoTalk 과 WireGuard 는 기계당 한 번 손으로 깐다.
선언적으로 설치할 방법이 없다는 것이 결론이고, 왜 없는지는
[0016](decisions/0016-mas-only-apps-installed-by-hand.md).

깔려 있지 않으면 switch 가 매번 알리고 App Store 페이지를 여는 명령을 같이
낸다. 알림 자체는 손으로 할 일을 없애 주지는 않지만, 잊은 채로 지나가지는
않게 한다.

서버 맥에는 WireGuard 앱을 깔지 않는다. 그 앱은 콘솔 로그인 없이는 터널을 못
올려서, 거기서는 `wireguard-tools` 가 데몬으로 돈다 —
[위](#wireguard-서버-맥) 와
[0029](decisions/0029-wireguard-as-a-daemon-on-the-server-mac.md).
