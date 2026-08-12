# 0022. Vim 이 vim-sensible 위에 얹히는 방식

**결정** — sensible 이 이미 주는 옵션은 vimrc 에 다시 쓰지 않는다.

nixpkgs는 sensible의 `s:MaySet`에 패치를 넣어, 옵션이 이미 `/nix/store` 경로에서
설정됐으면 건드리지 않게 한다. 우리 vimrc가 거기 있으므로 겹치면 우리 설정이 이긴다.
그래서 sensible이 이미 주는 것(backspace, smarttab, incsearch, ruler, laststatus,
wildmenu, autoread ...)은 `home/common.nix`에 다시 쓰지 않는다.

예외가 하나 있다. `history`는 vimrc 2번 줄의 `set nocompatible`이 이미 값을
바꿔놓고, 그 줄이 `/nix/store`에 있어서 sensible이 자기 `history=1000`을 건너뛴다.
그래서 명시적으로 설정한다.
