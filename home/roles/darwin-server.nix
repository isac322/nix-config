# home-manager configuration for the Macs that run unattended.
#
# Empty by design. A server Mac runs the same shell, editor and CLI tools as
# any other — those are in home/common.nix — and the only thing it does not
# want is the desktop applications, which it gets by not importing the laptop
# role. This file is the seam for server-only user tooling.
{ ... }:

{
}
