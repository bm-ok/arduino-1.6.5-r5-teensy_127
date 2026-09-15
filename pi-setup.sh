#!/usr/bin/env bash
#
# One-time host setup for building OnlyKey firmware on a Raspberry Pi.
#
# WHY THIS EXISTS AS A SEPARATE SCRIPT
#
# The Makefile and in-docker-build.sh in this directory work perfectly on an
# ordinary x86-64 Linux box and are left alone. A Pi is not one. The difference
# is not the distro, it is the instruction set, and it is not negotiable:
#
#   $ readelf -h arduino-1.6.5-r5/hardware/tools/arm/bin/arm-none-eabi-gcc
#   Machine: Advanced Micro Devices X86-64
#
# The pinned toolchain is Arduino 1.6.5 + Teensyduino 1.27, from 2015. Its
# arm-none-eabi-gcc 4.8.4 was only ever shipped as an x86 Linux binary - there
# is no aarch64 build of it and there never was. So on a Pi the compiler cannot
# run natively, and the only way to use THE EXACT COMPILER THAT BUILT THE
# RELEASES is to emulate x86-64.
#
# That constraint is worth stating plainly, because the tempting shortcut -
# installing a modern aarch64-hosted arm-none-eabi-gcc from Debian - produces a
# DIFFERENT BINARY. This whole project exists to build firmware from pinned
# commits so that what runs on a developer key is what shipped. A different
# compiler throws that away while still looking like it worked.
#
# WHAT GOES WRONG WITHOUT THIS
#
# ubuntu:focal has an arm64 image. So on a Pi, `docker build` and `docker run`
# both succeed, the container comes up, and the build fails deep inside with
# the arm-none-eabi compiler reporting "No such file or directory" - because
# the kernel cannot exec an x86-64 ELF and says so in the least helpful way
# available. That reads as a broken toolchain rather than a wrong platform,
# which is a bad afternoon. Hence --platform linux/amd64, everywhere, pinned.
#
# Run this once. It needs sudo and will ask for your password.

set -euo pipefail

say()  { printf '\n== %s\n' "$*"; }
fail() { printf '\n!! %s\n' "$*" >&2; exit 1; }

ARCH="$(uname -m)"

say "host is $ARCH, $(. /etc/os-release && echo "$PRETTY_NAME")"

if [ "$ARCH" = "x86_64" ]; then
  cat <<'MSG'
This host is already x86-64, so it does not need any of this. Use the ordinary
path instead - it is faster and has no emulation layer:

    make docker-build-toolchain
    make docker-build

MSG
  exit 0
fi

# Debian's own docker.io, not docker-ce. Docker's upstream repository has no
# packages for Debian 13 (trixie) - `apt-cache policy docker-ce` returns no
# candidate at all - and adding an unofficial repo to get a newer daemon buys
# nothing here. docker.io 26.1.5 runs a foreign-platform image just fine.
# Skipped when the packages are already there. This script asks you to run it a
# SECOND time once the docker group has taken effect, and an unconditional apt
# would mean a password prompt on that pass for no work at all - which teaches
# you to stop reading what it says.
if command -v docker >/dev/null 2>&1 && [ -e /usr/libexec/qemu-binfmt/x86_64-binfmt-P ]; then
  say "docker and qemu-user already installed; skipping apt"
else
  say "installing docker.io, qemu-user-static, binfmt-support"
  sudo apt-get update
  sudo apt-get install -y docker.io qemu-user-static binfmt-support

  say "enabling docker"
  sudo systemctl enable --now docker
fi

# Group membership does NOT apply to shells that already exist. Saying so here
# is cheaper than the alternative, which is the next command failing with
# "permission denied on /var/run/docker.sock" and looking like a broken install.
if ! id -nG "$USER" | tr ' ' '\n' | grep -qx docker; then
  say "adding $USER to the docker group"
  sudo usermod -aG docker "$USER"
  NEEDS_RELOGIN=1
else
  NEEDS_RELOGIN=0
fi

# qemu-user-static's postinst registers the handlers through systemd-binfmt.
# Verify rather than trust: a registration that silently did not happen is
# indistinguishable, at the point of failure, from the platform flag missing.
say "checking binfmt registration for x86_64"
if [ ! -e /proc/sys/fs/binfmt_misc/qemu-x86_64 ]; then
  sudo systemctl restart systemd-binfmt || true
fi
if [ -e /proc/sys/fs/binfmt_misc/qemu-x86_64 ]; then
  grep -E '^(enabled|interpreter)' /proc/sys/fs/binfmt_misc/qemu-x86_64 || true
else
  fail "qemu-x86_64 is not registered in binfmt_misc. Without it an amd64
   container cannot execute anything. Try: sudo systemctl restart systemd-binfmt"
fi

if [ "$NEEDS_RELOGIN" = "1" ]; then
  cat <<'MSG'

== docker group added, but this shell does not have it yet

Open a new shell (or run `newgrp docker`), then re-run this script to finish
the verification. Everything above is done.
MSG
  exit 0
fi

# The actual question this script exists to answer. If this prints x86_64, the
# pinned 2015 compiler can run on this Pi and the build is merely slow. If it
# does not, no amount of work on the build scripts will help and the answer is
# to build on an x86-64 machine instead.
say "verifying emulated amd64 actually runs"
GOT="$(docker run --rm --platform linux/amd64 ubuntu:focal uname -m)"
if [ "$GOT" != "x86_64" ]; then
  fail "an amd64 container reports '$GOT', not x86_64. Emulation is not working."
fi

cat <<'MSG'

== ready

An emulated amd64 container runs on this host, so the pinned x86-64 toolchain
will run too. Build with:

    ./pi-build.sh

Expect it to be slow. Every instruction the 2015 Arduino IDE and the
arm-none-eabi compiler execute is being translated, and a Pi has little memory
to spare for it.
MSG
