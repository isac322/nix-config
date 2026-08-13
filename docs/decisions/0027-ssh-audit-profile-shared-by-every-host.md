# 0027. ssh-audit 권장값을 프로파일 하나로, 세 기기 전부에

**결정** — [ssh-audit](https://github.com/jtesta/ssh-audit) 가 지금 권장하는
알고리즘 목록 전부를 `lib/ssh-audit.nix` 에 데이터로 두고 맥과 NixOS 양쪽에
적용한다. 가이드를 베껴 넣지 않고, 도구에서 뽑아내 옮긴 뒤 그 대조를
`.claude/skills/ssh-audit/` 로 자동화한다.

[0026](0026-sshd-on-the-server-mac.md) 이 "누가 들어올 수 있나" 라면 이건 "들어올
때 무엇으로 말하나" 다. 겹치지 않고, 파일도 갈라져 있다.

## 어디서 가져왔나

sshaudit.com 의 OS별 가이드 페이지를 읽는 대신 도구가 직접 뱉게 했다.

```sh
nix run nixpkgs#ssh-audit -- --get-hardening-guide "Ubuntu 26.04 Server"
```

출력의 본문이 곧 sshd_config 텍스트라서 사람이 옮겨 적을 여지가 없고, 같은 표에서
`-P` 정책도 생성되므로 스캔 기준과 설정 기준이 어긋나지 않는다. 그리고 이게 스킬이
매번 다시 돌리는 그 명령이다 — 레포에 든 것은 사본이고, 사본은 상하니까.

가이드는 OS 별로 있지만 지시자 목록은 현대 OS 셋이 전부 같다. 다른 것은 파일을 어디
두고 서비스를 어떻게 재시작하느냐뿐이고, 그 부분은 우리 둘 다에 해당하지 않는다.
macOS 용 공식 가이드는 없다 (커뮤니티 위키에 Ventura·Sonoma 것이 있을 뿐이다).
맥이 돌리는 것은 10.3p1, NixOS 는 10.4p1 이고 정책은 v10.0–v10.4 가 전부 동일하다.

## 무엇이 바뀌었나

가장 큰 변화는 키 교환이 **전부 post-quantum 으로 갈렸다**는 것이다. Debian 12 →
13 개정에서 고전 알고리즘이 하나도 남지 않았다.

```
KexAlgorithms mlkem768x25519-sha256,sntrup761x25519-sha512,sntrup761x25519-sha512@openssh.com
```

여기 딸려오는 것 둘. `/etc/ssh/moduli` 를 걸러내는 절차가 사라졌다 — moduli 는
group-exchange 에서만 읽히는데 그게 목록에 없다. DHEat 대비 연결수 제한도 사라졌다
— OpenSSH 가 기본으로 막는다. 즉 이 결정에는 **손으로 할 일이 붙지 않는다**.

대신 이 한 줄이 사람을 잠글 수 있는 유일한 줄이기도 하다. 협상해서 내려오지 않고
핸드셰이크가 그냥 실패한다. `sntrup761x25519-sha512@openssh.com` 은 클라이언트
OpenSSH 8.5+, `mlkem768x25519-sha256` 은 10.0+ 를 요구한다. 여기 있는 기계는 전부
한참 위지만, 빌린 노트북이나 폰의 SSH 앱은 아닐 수 있다.

## 왜 `extraConfig` 가 아니라 `010-` 파일인가

맥에서만 생기는 문제이고, 조용히 틀리는 종류다.

`/etc/ssh/sshd_config` 첫 줄이 `Include /etc/ssh/sshd_config.d/*` 이고, glob 은
사전순으로 펼쳐지며, sshd 는 **먼저 본 값**을 지킨다. 애플은 `100-macos.conf` 를
깔고 그게 `/etc/ssh/crypto.conf` 를 include 하는데, 거기서 `Ciphers`,
`KexAlgorithms`, `MACs` 를 `^` 로 — 기본값 앞에 덧붙이는 형태로 — 정한다. 그리고
nix-darwin 은 `services.openssh.extraConfig` 를 `100-nix-darwin.conf` 에 쓴다.
`100-macos` 가 `100-nix-darwin` 보다 앞선다.

그래서 제일 그럴듯한 자리가 진다. `extraConfig` 로 넣고 `sshd -T` 를 돌리면
`kexalgorithms ecdh-sha2-nistp256,…` 로 시작해서 curve25519 와 NIST 곡선 둘이
따라오는 목록이 나온다. 의도의 정반대인데 파일만 보면 멀쩡하다. 같은 내용을
`010-ssh-audit-hardening.conf` 로 옮기면 `kexalgorithms mlkem768x25519-sha256`
하나만 남는다.

인증 세 줄은 `crypto.conf` 가 건드리지 않으므로 `extraConfig` 에 그대로 둔다.
같은 파일에 몰아넣지 않은 것은 그게 역할별 결정이기 때문이다 — 아래.

NixOS 에는 이 문제가 없다. sshd_config 전체를 자기가 렌더링하니 앞서 읽히는
남의 조각이 없다.

## 왜 랩탑에도 거는가

sshd 를 켜는 것은 서버 역할뿐이지만 (0026), 알고리즘 프로파일은
`modules/darwin.nix` 에 있어서 맥 두 대 다 받는다.

역할로 갈리는 것은 "누가 들어올 수 있나" 이지 "무엇으로 말하나" 가 아니다. 후자는
어느 맥이든 답이 같고, sshd 가 꺼진 기계에 걸어봐야 비용이 없다. 반대로 누군가
시스템 설정에서 원격 로그인을 켰을 때 그 기계만 약한 편이 훨씬 나쁘다.

호스트 키도 같은 이유로 공용이다. ECDSA 를 목록에서 뺀 것이 곧 제시하지 않는 것이고,
남아 있는 키 파일은 `HostKey` 줄에서 이름이 빠진 순간 무의미해진다.

## GSSAPIKexAlgorithms 는 왜 빠졌나

가이드에는 있고 우리에게는 없다. GSSAPI 키 교환은 상류 OpenSSH 가 아니라
Debian/Ubuntu 패치다. 애플의 10.3p1 도 nixpkgs 의 10.4p1 도 이 지시자를 모르고,
모르는 지시자를 만난 sshd 는 무시하지 않고 **뜨지 않는다**:

```
/etc/ssh/sshd_config.d/010-…: line 7: Bad configuration option: GSSAPIKexAlgorithms
terminating, 1 bad configuration options
```

사람이 없는 맥에서 그건 문을 잠그고 열쇠를 안에 두는 것이다. 그래서 뺐고, 뺀
사실과 이유를 `lib/ssh-audit.nix` 와 스킬의 무시 목록 양쪽에 적어 두었다 — 이유
없이 빠진 항목은 대조할 때마다 drift 로 되살아난다.

## RSA 호스트 키 4096 은 왜 메시지인가

`RequiredRSASize 3072` 는 받아줄 최소치고, 생성할 크기는 4096 이다. 정책은 실제로
제시된 키의 비트수를 본다.

nix-darwin 도 NixOS 도 없는 호스트 키는 만들지만 **있는 키는 바꾸지 않는다**. 옳은
동작이다 — 호스트 키 교체는 그 기계에 접속해 본 모든 클라이언트의 known_hosts 를
깨고, 그걸 switch 가 알아서 할 일은 아니다. 그래서 프로파일보다 먼저 만들어진
3072 짜리 키는 그대로 남고, activation 이 그 사실과 지우는 명령을 출력한다
([0025](0025-activation-speaks-only-when-needed.md)). sshd 가 켜진 기계에서만
말한다.

## 스킬로 만든 이유

권장값은 연 단위로 움직이고, 움직였다는 사실은 알려주지 않는다. 레포에 든 목록은
그 시점의 사본일 뿐이라서, 다시 대조하는 방법이 레포 안에 없으면 이 결정은
만들어진 날이 가장 정확한 날이 된다.

`.claude/skills/ssh-audit/check-drift.py` 가 가이드를 다시 뽑아 `lib/ssh-audit.nix`
와 지시자 단위로 대조하고, 차이를 사람이 읽을 형태로 낸다. 판단은 하지 않는다 —
새 지시자가 우리 sshd 에 있는지, 좁아진 목록이 누구를 잠그는지는 사람이 정한다.
프로젝트 레벨로 레포 안에 둔 것은, 이게 이 레포의 파일 하나에 대한 절차이지
기계에 대한 것이 아니기 때문이다.
