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

`hosts/<name>/` 의 `local.wireguard.interface` 가 이름을 정하고, 그게 곧 파일
이름이다.

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
```

파일이 없으면 데몬은 터널을 안 올리고 그 사실을 로그에 남긴다 — 설정이 깨지지는
않는다. `wg-quick up` 은 인터페이스를 올리고 끝나므로 데몬이 계속 떠 있지 않는
것이 정상이다. 살아 있게 하는 것은 wg-quick 이 떼어 놓는 `wireguard-go` 다.

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
launchctl print user/$(id -u)/org.nix-community.home.orca-serve   # 상태
orca status --json                                                # 런타임 쪽에서 본 상태
```

**부팅 확인 — 한 번은 해야 한다.** `LimitLoadToSessionType = "Background"` 는
콘솔 로그인 없이도 뜨라는 뜻인데, 아무도 로그인하지 않은 부팅 직후에
`user/<uid>` 도메인이 올라오는지는 그 기계에서만 확인된다. 재부팅하고, **콘솔에
로그인하지 말고** SSH 로만 들어와서:

```sh
launchctl print user/$(id -u)/org.nix-community.home.orca-serve | head -5
```

`state = running` 이면 끝이다. `Could not find service` 면 그 도메인이 부팅 때
안 올라온 것이고, 그때는 자동 로그인
(`system.defaults.loginwindow.autoLoginUser` + 손으로 넣는 `/etc/kcpassword`)
이 남은 방법이다.

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

`pkgs/` 의 여섯은 어떤 공개 캐시에도 없어서 기기마다 새로 컴파일한다. 그것만 Cachix
에 올린다 ([0018](decisions/0018-cachix-not-flakehub-cache.md)).

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
