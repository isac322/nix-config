# 0030. 콘솔 없는 맥에서 GPG passphrase 를 꺼내오는 법

**결정** — 서버 역할의 맥은 `pinentry-mac` 을 안 쓴다. `pkgs/pinentry-keychain`
이 로그인 키체인에서 passphrase 를 읽고, 없으면 `pinentry-tty` 로 떨어져 SSH 에서
묻고, 받은 값을 `-A` 로 저장한다. tty 도 없으면 **즉시 실패한다.**

[0028](0028-orca-runtime-on-the-server-mac.md) 이 켠 자동 로그인이 만든 문제다.
그 결정의 청구서가 여기 있다.

## 어떻게 드러났나

`ssh -T git@github.com` 이 멈췄다. 키 문제처럼 보였지만 아니었다 — 지문은 GitHub
에 등록된 그 키가 맞고, 서버도 받아들인다:

```
debug1: Server accepts key: ... SHA256:7mubl... agent
(여기서 영원히)
```

`Server accepts key` 다음이 **서명 요청**이다. 즉 인증이 아니라 서명이 막힌
것이고, 같은 이유로 커밋 서명도 죽어 있었다. `ssh-add -L` 은 멀쩡히 답했다 —
목록 조회에는 비밀이 필요 없기 때문이다. 그래서 "키는 있는데 안 된다" 로 보였다.

원인은 `pinentry-mac` 이 아무도 안 앉은 콘솔에 창을 그리고 있던 것이다. 그
프로세스가 49분째 서 있는 것을 보고 확정했다.

## 층이 하나가 아니었다

세 번 틀렸고 세 번 다 증거로 갈랐다.

**하나. 키체인이 잠겨 있었다.** 사람이 로그인 창에 비번을 치면 그 한 번의 입력이
로그인과 키체인 잠금 해제를 **둘 다** 한다. `/etc/kcpassword` 자동 로그인은 앞의
절반만 한다. 해제 전후를 대조해 확인했다:

```
해제 전  "User interaction is not allowed"
해제 후  Keychain "..." no-timeout
```

그래서 `home/roles/darwin-server.nix` 의 LaunchAgent 가 세션이 생길 때 연다.
비밀번호는 자동 로그인이 이미 쓰는 파일에서 오고, `security -i` 의 stdin 으로
넘겨 `ps` 에 안 뜬다.

**둘. 열어도 못 읽었다.** 키체인 항목은 **어느 바이너리가 조용히 읽어도 되는지**를
기억한다. `pinentry-mac` 이 만든 항목은 다른 프로그램을 모르므로, 다른 것이 읽으려
하면 macOS 가 확인 창을 띄운다 — 콘솔에. 잠금을 풀어도 층이 하나 더 있었던 것이다.

이건 랩탑에서 눈앞에 재현됐다. 진단하려고 `security find-generic-password` 를
돌렸더니 확인 창이 떴다.

**셋. 저장이 조용히 실패했다.** `security add-generic-password -w` 는 비밀번호를
**두 번** 묻는다 — `password data for new item:` 다음 `retype password for new
item:`. 한 줄만 보내면 재입력이 EOF 로 가서 `passwords don't match` 로 끝나는데,
그 오류는 stderr 로 사라진다. gpg-agent 캐시가 8시간 들고 있어서 그 자리에서는
성공한 것처럼 보인다.

## 그래서 기성품이 아니라 직접 만들었다

gpg-agent 에는 키체인 지원이 없다. 모든 경로가 pinentry 교체를 거치는데:

- **pinentry-mac** — 키체인 저장은 자체 구현(`KeychainSupport.m`)이지만 창을 콘솔에 그린다
- **pinentry-mac-keychain** — 그것에 프록시하므로 같은 병을 물려받는다
- **pinentry-touchid** — 뚜껑 닫힌 기계가 줄 수 없는 지문을 요구한다

뒤의 둘은 nixpkgs 에도 없다. 그런데 pinentry 는 Assuan 을 말하는 작은 프로그램일
뿐이고, 필요한 것은 세 명령이다 — `SETKEYINFO` 가 keygrip 을 주고, `GETPIN` 이
묻고, 답은 `D` 줄 다음 `OK`.

두 줄이 이 설계의 전부다.

**조회를 알람 아래 둔다.** 남이 쓴 항목이면 macOS 가 확인 창을 그리고 `security`
는 기다린다. 헤드리스에서 그 대기는 무한이고, 그건 이 프로그램이 없애려는 바로 그
실패다. 3초 안에 답이 없으면 미스로 친다.

**저장은 `-A` 로 한다.** 한 바이너리에 묶인 항목은 nixpkgs 가 그 바이너리를 새
store 경로로 옮기는 순간 못 읽게 되고, 그러면 아무도 안 보는 콘솔에 확인 창이
뜬다. 이런 기계의 키체인은 이미 `/etc/kcpassword` 만큼만 강하고 그건 고정 XOR 로
되돌려지므로, `-A` 가 내주는 것은 보기보다 적다.

## 무한 대기가 아니라 즉시 실패

```
gpg-agent 캐시(8h) → 키체인(-A, 만료 없음) → pinentry-tty(SSH 에서 답 가능)
→ tty 도 없으면 즉시 ERR
```

마지막 줄이 이 결정에서 제일 중요하다. 무인 기계에서 최악이 "멈춤" 이면 원인을
알아낼 방법이 없다. 지금은 1초 만에 `Operation cancelled` 가 나오고, 로그에
어느 단계였는지가 남는다.

`~/Library/Logs/pinentry-keychain.log` 가 그 로그다. 이 프로그램은 gpg-agent 의
자식으로 돌고 stdout 은 프로토콜이 쓰고 있어서, 그 파일이 아니면 무슨 일이
있었는지 볼 데가 없다. 위의 세 실패 중 둘은 그 로그가 없어서 오래 걸렸다.

## `gpg-preset-passphrase` 는 왜 안 쓰나

한때 넣었다가 뺐다. passphrase 를 평문 파일에 두고 로그인 때 에이전트 캐시에
밀어 넣는 방식이고, 무인으로는 잘 돈다. 그런데 키체인이 도는 이상 하는 일이
겹치고, 평문 파일과 6시간 타이머와 `allow-preset-passphrase` 를 셋 다 들고 갈
이유가 없어졌다. 키체인 쪽에는 만료가 없다.

## 랩탑은 그대로다

`pinentry-mac` 이 맞는 자리다. 사람이 앉아 있고, 창이 보이고, Touch ID 도 있다.
이 결정은 화면 없는 기계에만 해당한다 — `home/darwin.nix` 는 안 건드렸고 서버
역할이 `mkForce` 로 덮는다.
