# 0007. switch 가 비밀번호를 두 번 묻던 이유

**결정** — sudo 타임스탬프 수명을 30분으로 늘리고, 랩탑에서는 그 프롬프트를
Touch ID 가 받게 한다. NOPASSWD 는 쓰지 않는다.

`sudo darwin-rebuild switch` 로 한 번 인증했는데 brew 차례에서 또 묻는 일이
있었다. 버그가 아니라 권한이 한 번 내려갔다 다시 올라오기 때문이다.

1. activation 전체가 **root** 로 돈다.
2. 그런데 Homebrew 는 root 로 도는 것을 거부하므로, nix-darwin 이 brew 단계에서
   일부러 사용자로 **내려간다**:
   `sudo --preserve-env=PATH --user=bhyoo --set-home env brew bundle …`
3. 캐스크 중 아티팩트가 `app` 이 아니라 `pkg` 인 것들은 `/usr/sbin/installer` 를
   root 로 불러야 한다. 지금 선언된 것 중에는 `cloudflare-warp` 과 `zoom` 둘이다.
   그래서 사용자로 내려간 Homebrew 가 **sudo 를 다시 부른다**.
4. root 의 권한은 강등된 자식에게 흘러내리지 않고, 1번의 sudo 타임스탬프는
   수명이 5분(sudoers(5) `timestamp_timeout` 기본값)이라 빌드가 그 시간을
   넘긴다.

그래서 **brew 가 할 일이 있을 때만** 묻는다. 할 일이 없으면 sudo 를 아예 안
부른다. `onActivation.upgrade` 가 켜져 있어 저 두 캐스크가 새 버전을 낼 때마다
걸린다.

두 곳을 고쳤고, 둘은 다른 질문에 답한다.

- **얼마나 자주 뜨는가** — `security.sudo.extraConfig` 의
  `Defaults timestamp_timeout=30` (`modules/darwin.nix`, 모든 맥). 리빌드
  하나를 덮되 하루 종일 인증된 채로 두지는 않는 길이다. 기록은 터미널 단위라
  (`timestamp_type` 기본값 `tty`) 다른 세션에 창을 열어주지 않는다.
- **떴을 때 무엇을 하는가** — `security.pam.services.sudo_local` 의
  `touchIdAuth` + `reattach` (`modules/roles/darwin-laptop.nix`, 랩탑만).
  지문 센서가 필요한 설정이라 SSH 로 닿는 헤드리스 기계에는 의미가 없다.
  `reattach`(pam_reattach)를 같이 켜는 이유는 pam_tid 가 사용자 bootstrap 세션
  안에서만 프롬프트를 그릴 수 있어서다 — tmux 안의 셸이 그 밖이고, root 에서
  `sudo --user=bhyoo` 로 들어가는 brew 단계도 그 밖이다. `auth optional` 줄이라
  필요 없는 곳에서는 비용이 없다.

nix-darwin 이 쓰는 `/etc/pam.d/sudo_local` 은 애플이 macOS 14 에서 **로컬 수정이
시스템 업데이트를 넘어 살아남으라고** 추가한 파일이다. `/etc/pam.d/sudo` 자체는
봉인된 볼륨에 있고 이 파일을 include 한다.

sudoers 파일은 문법이 틀리면 sudo 전체가 막히므로, 병합된 결과를
`visudo -c -f` 로 검증하고 나서 넣었다 — nix-darwin 은
`/etc/sudoers.d/10-nix-darwin-extra-config` 하나에 terminfo 용 `env_keep` 줄과
위의 `Defaults` 를 같이 쓴다.

NOPASSWD 규칙은 쓰지 않았다. 프롬프트는 사라지지만 그건 인증 정책을 통째로 내리는
것이라 질문에 대한 답이 아니다.
