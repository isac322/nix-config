# 0026. 서버 맥의 sshd — 키 전용, 그리고 열쇠는 레포에 안 넣는다

**결정** — `services.openssh.enable` 은 서버 역할에만 켠다. 암호 인증은 두 경로
모두 막고 root 로는 못 들어오게 한다. `authorized_keys` 는 선언하지 않고, 없을 때
switch 가 알려준다.

`modules/roles/darwin-server.nix` 의 나머지가 전부 "아무도 앞에 없는 기계" 를
전제하는데, 그 전제를 실제로 참으로 만드는 것이 이 항목이다.

## 왜 랩탑에는 없나

`services.openssh.enable` 은 `nullOr bool` 이고 기본값이 `null` 이다. 이건
`false` 와 다르다 — `null` 은 "macOS 가 알아서 하게 둔다" 이고, `false` 는 매번
switch 마다 데몬을 내린다. 랩탑의 Remote Login 은 그때그때 사람이 정할 일이라
`null` 이 맞고, 그래서 이 블록은 `modules/darwin.nix` 가 아니라 역할 파일에 있다.

## 어떻게 켜지는가

nix-darwin 은 `systemsetup -setremotelogin` 을 쓰지 않는다. 그 명령은 Full Disk
Access 를 요구해서 switch 에서 부를 수 없다. 대신 launchd 잡을 직접 건드린다:

```sh
launchctl enable system/com.openssh.sshd
launchctl bootstrap system /System/Library/LaunchDaemons/ssh.plist
```

시스템 설정의 Remote Login 토글이 켜는 것과 같은 데몬이고, 도는 sshd 도 애플
것이다. 이 옵션이 정하는 것은 그것이 올라오는지와, `/etc/ssh/sshd_config.d` 에
어떤 조각을 쥐여줄지 둘뿐이다.

## 세 줄 다 필요하다

```
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
```

macOS 의 `/etc/ssh/sshd_config` 는 셋 다 주석 처리해 두었다. 즉 무엇도 말하지
않으면 상류 기본값인 `yes`, `yes`, `prohibit-password` 가 적용된다.

`KbdInteractiveAuthentication` 이 놓치기 쉬운 쪽이다. macOS 는 `UsePAM yes` 라
PAM 이 keyboard-interactive 를 통해 암호 인증을 **한 번 더** 제공한다.
`PasswordAuthentication no` 만으로는 암호 프롬프트가 그대로 남는다.

읽히는 순서도 확인해 둘 값어치가 있다. `Include /etc/ssh/sshd_config.d/*` 는
`sshd_config` 맨 위에 있고 glob 은 사전순으로 펼쳐지며 sshd 는 **먼저 본 값**을
지킨다. 그래서 애플의 `100-macos.conf` 가 우리 `100-nix-darwin.conf` 보다 앞서
읽히지만, 거기 들어 있는 것은 `UsePAM`·`AcceptEnv`·`crypto.conf` include 뿐이라
이 세 줄과는 겹치는 것이 없다.

`crypto.conf` 가 정하는 것들과는 겹친다. 그쪽은 이 파일에 들어올 수 없어서
`010-` 로 시작하는 별도 파일로 나가고, 그 이야기는
[0027](0027-ssh-audit-profile-shared-by-every-host.md) 에 있다.

## 열쇠는 왜 선언하지 않나

`users.users.<name>.openssh.authorizedKeys` 로 선언할 수 있고, 공개키가 비밀도
아니다. 그런데 **이 레포는 공개**이고 [열쇠는 기기마다 다르지 않다](0004-one-gpg-key-for-ssh-signing-packaging.md)
— GPG 인증 서브키 하나가 모든 기계의 SSH 신원이다. 그걸 커밋하면 세 기계를 여는
자격증명의 이름을 한 줄에 공개하는 셈이 된다. 개인키를 레포 밖에 두는 이유와
같고, 처리 방식도 같다: switch 가 무엇을 하라고 말하고, 사람이 그걸 한다
([0025](0025-activation-speaks-only-when-needed.md)).

그래서 다른 기계에서 무엇을 들고 올 필요도 없다. 이 기계의 gpg-agent 가 이미
같은 신원을 쥐고 있으므로, 자기 에이전트에서 자기를 인가한다 — 절차는
[운영](../operations.md) 에 있다.
