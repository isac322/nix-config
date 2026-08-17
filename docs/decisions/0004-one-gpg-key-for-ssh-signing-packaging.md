# 0004. 열쇠 하나로 셋 다 — SSH · 커밋 서명 · 패키징

**결정** — SSH 키쌍을 따로 두지 않고 GPG 키 하나의 서브키로 세 가지를 다 한다.
키 반입 절차는 [운영 · GPG 키 가져오기](../operations.md#gpg-키-가져오기).

둘 다 **모든 맥** 공통이다 (`home/darwin.nix`). 목적은 같다 — 매번 암호를 치지
않는 것. 그런데 필요한 서명이 셋이었다: SSH 접속 인증, git 커밋 서명, 그리고 Arch
패키징(`makepkg --sign`)이다.

**셋을 GPG 키 하나로 한다.** `makepkg --sign` 과 PKGBUILD 의 `validpgpkeys` 는 PGP
전용이라 SSH 서명이 대신할 수 없다 — pacman 의 신뢰 모델이 PGP 이기 때문이다.
(AUR 자체는 커밋 서명을 보지 않는다. `aur-dev` 에서 SSH 서명 검증이 논의된 적은
있으나 구현되지 않았고, AUR 은 푸시 인증에만 SSH 를 쓴다.) 즉 GPG 키는 어차피
있어야 한다. 그렇다면 SSH 키쌍을 따로 두는 대신 GPG 의 **인증(authentication)
서브키**를 gpg-agent 가 ssh-agent 프로토콜로 내주게 하면 — `enableSshSupport` 가
하는 일이다 — 기계마다 만들고 백업하고 등록할 키가 하나로 준다. 키를 옮기면 셋이
같이 옮겨간다.

## 대가 — macOS 는 자기 ssh-agent 를 가리키고 있다

macOS 는 gpg-agent 를 내장하지 않지만 ssh-agent 는 `com.openssh.ssh-agent.plist` 로
띄우고, launchd 가 그 소켓 경로를 `SSH_AUTH_SOCK` 으로 **로그인 세션 전체**에 —
GUI 앱 포함 — 심는다. 그래서 방향을 돌리는 데 조치가 셋 필요하다. 이건 이 저장소가
고안한 게 아니라 이 설정을 다루는 모든 안내가 공통으로 말하는 셋이고, 다만 셸
프로파일에 붙여넣는 대신 선언으로 옮겨 적었을 뿐이다.

1. **에이전트를 띄운다** — `gpgconf --launch gpg-agent`. gpg 는 필요할 때 알아서
   에이전트를 띄우지만 **ssh 는 gpg-agent 라는 것을 모른다.** 소켓을 열어보고 없으면
   포기할 뿐이다. 로그인 직후 gpg 명령을 한 번도 안 돌린 시점이 정확히 그 상황이다.
   보통 셸 프로파일에 넣으라고 하는 줄인데, 세션 전체에 걸리는 게 목적이므로
   LaunchAgent 에 둔다.
2. **`~/.ssh/config` 의 `IdentityAgent`** — ssh 바이너리는 누가 실행하든 이 파일을
   읽는다. 셸을 거치지 않는 GUI 앱이 ssh 를 호출하는 경우까지 덮는다.
3. **`launchctl setenv SSH_AUTH_SOCK`** — home-manager 는 이 변수를 셸 초기화에서만
   내보내는데, 그건 터미널까지만 닿는다. launchd 로 뜬 앱은 셸 프로파일을 읽지
   않으므로, 변수를 직접 읽는 쪽을 위해 세션 전역으로 심는다.

세 조치가 **같은 하나의 소켓**을 가리키는 것이 핵심이다. 갈라지면 터미널에서는 되고
GUI 에서는 멈추는, 재현 조건이 이상한 버그가 된다.

## home-manager 의 gpg-agent LaunchAgent 는 끈다

`launchd.agents.gpg-agent.enable = mkForce false`. `services.gpg-agent` 는 darwin
에서 `/private/var/run` 아래 launchd 소켓을 걸고 `gpg-agent --supervised` 를 띄우는
잡을 만드는데, `--supervised` 는 **systemd 의 소켓 액티베이션 규약**(환경변수
`LISTEN_FDS`, 그리고 fd 3 에 걸린 리스닝 소켓)을 구현한 모드다. launchd 는 소켓을
자기 API 로 넘기므로 fd 3 은 결코 소켓이 아니고, 잡은 뜨는 즉시 죽는다.

```
Fatal: file descriptor 3 must be valid in --supervised mode if LISTEN_FDNAMES is not set
```

여기서 나쁜 건 실패 자체가 아니라 **실패하는 방식**이다. launchd 는 잡을 돌리기 전에
`Sockets` 에 적힌 소켓 파일을 미리 만들어 둔다. 그래서 파일은 존재하는데 아무도
응답하지 않는다 — 연결하면 에러가 아니라 **무한 대기**다. `ssh` 가 멈춰 있고
`ssh-add -L` 이 영영 돌아오지 않는데 소켓은 멀쩡히 거기 있는, 진단하기 가장 나쁜
모양이 된다. 그래서 이 잡을 끄고 GnuPG 자신의 기동 경로(`gpgconf --launch`)와
GnuPG 자신의 소켓(`~/.gnupg/S.gpg-agent.ssh`)을 쓴다. `services.gpg-agent` 가 하는
나머지 일 — `gpg-agent.conf` 생성, 셸 초기화에서의 `SSH_AUTH_SOCK` — 은 그대로 다
쓴다.

`enableDefaultConfig` 는 꺼 두었다. 자체 `*` 블록이 위 설정과 충돌하기 때문이고,
기본값들은 그대로 옮겨 적되 `AddKeysToAgent` 와 `UseKeychain` 은 뺐다 — 둘 다
macOS ssh-agent 의 옵션인데 그게 더는 경로에 없다.

## 패스프레이즈는 평생 한 번

nixpkgs 의 `pinentry_mac` 은 GPGTools 빌드(`org.gpgtools.pinentry-mac`)라
패스프레이즈를 로그인 키체인에 저장할 수 있고, GPGTools 는 "always allow" 로
저장한다. 그래서 캐시 TTL 은 관측되지 않는다: 만료될 때마다 pinentry 가 키체인에서
조용히 꺼내오므로 묻는 것은 최초 한 번뿐이다. 키가 하나이므로 이 한 번이 SSH 와
서명 양쪽을 덮는다. `UseKeychain` 과 `DisableKeychain = false` 가 둘 다 필요하다 —
후자의 기본값이 참이고, 그것이 켜져 있는 한 "Save in Keychain" 체크박스 자체가
나타나지 않는다.

## 커밋 서명에 `user.signingkey` 를 쓰지 않는다

키가 지정되지 않고 형식이 기본값 openpgp 이면 git 은 커미터 신원을 그대로 gpg 에
넘긴다 (`-u "Name <email>"`, `gpg-interface.c` 의 `get_signing_key`). 즉 **커밋이
누구 것이라고 말하는가로 키를 찾는다.** 키 ID 를 적어두면 기계마다 다르고 교체할
때마다 설정을 고쳐야 하는데, 이렇게 두면 그럴 일이 없다. 대신 조건이 붙는다 — 키의
사용자 ID 를 `Byeonghoon Yoo <bhyoo@bhyoo.com>` 으로, `home/common.nix` 의 이름과
이메일에 정확히 맞춰 만들어야 한다. 이메일만 같고 이름이 다르면 git 이 키를 찾지
못한다.

## 키는 자동 생성하지 않는다

패스프레이즈를 거는 것이 위 키체인 설정의 목적인데 activation 은 프롬프트를 띄울 수
없어, 자동 생성은 곧 패스프레이즈 없는 키를 디스크에 두는 것이 된다. 그리고 애초에
키 하나를 여러 기계가 공유하는 구성이라 기계마다 새로 만드는 것은 목적에 어긋난다.
그래서 없으면 가져오는 법만 알려주고 끝낸다 —
[activation 이 말을 거는 기준](0025-activation-speaks-only-when-needed.md).

## `gpg-ssh-authorize` 가 하는 일

gpg-agent 가 비밀키를 다 갖고 있어도 그중 무엇을 SSH 로 내줄지는 따로 지정해야
한다. 서명키까지 통째로 노출하지 않으려는 설계다. 그런데 지정에 쓰는 값이
**keygrip** — 키가 이 기계에 들어온 뒤에야 생기는 값이라 설정 파일에 미리 적어둘
수가 없다. 그래서 흔히 보이는 안내가 `gpg --list-secret-keys --with-keygrip` 을
눈으로 읽어 `~/.gnupg/sshcontrol` 에 붙여넣는 것인데, 사람이 화면에서 옮겨 적는
단계는 이 저장소의 전제와 어긋난다.

`gpg-ssh-authorize` (`home/darwin.nix` 에서 정의) 는 그 값을 키링에서 직접
읽어낸다. `--with-colons` 출력에서 sec/ssb 레코드의 12번째 필드가 그 키의 용도이고
`a` 가 인증이므로, 그 뒤에 따라오는 `grp` 레코드가 곧 찾던 keygrip 이다. 즉 **볼
것도 고를 것도 없이** 인증 가능한 키 전부가 대상이 된다.

표시가 저장되는 곳은 `~/.gnupg/sshcontrol` 이 아니라 **개인키 파일 안의
`Use-for-ssh` 속성**이고, `gpg-connect-agent` 의 `KEYATTR` 로 쓴다. GnuPG 매뉴얼이
2.3.7 부터 sshcontrol 을 두고 *"deprecated in favor of the `Use-for-ssh` attribute
in the key files"* 라고 명시하고 있다. 동작은 둘 다 하지만, 남는 쪽을 쓴다.

`allowed_signers` 는 SSH 서명 전용 파일이라 이제 없다 — GPG 검증은 키링이 한다.

## OrbStack 충돌

OrbStack 은 `~/.ssh/config` 맨 위에 자기 `Include` 를 넣고 지우면 다시 넣는다.
`programs.ssh.includes` 로 선언해 두면 home-manager 가 그 줄을 직접 맨 앞에 쓰므로
서로 싸우지 않는다. 이제 두 Mac 모두 OrbStack 을 쓰므로 선언은 공통
`home/darwin.nix` 에 있고 NixOS 호스트에는 적용되지 않는다.
