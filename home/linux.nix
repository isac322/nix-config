# home-manager configuration for NixOS hosts only.
#
# Deliberately thin. Almost everything lives in home/common.nix, and the Vim
# config there is already written to degrade gracefully on a headless box (the
# clipboard setting is guarded by `has('clipboard')`). This file is the seam for
# what genuinely cannot be shared — put Linux-only programs and any
# `pkgs.firefox` desktop configuration here rather than widening common.nix.
{ ... }:

{
}
