#!/usr/bin/env bash
#
# Build OnlyKey firmware on a Raspberry Pi, through an emulated amd64 container.
#
# The Makefile beside this file does the same job on an ordinary x86-64 Linux
# host and is deliberately untouched. This is the same two docker commands with
# --platform linux/amd64 pinned on both, because the pinned 2015 toolchain is
# x86-64 only and a Pi is not. pi-setup.sh explains that at length and installs
# what makes it possible; run it first.
#
# The platform has to be pinned on BOTH the build and the run. Pinning only the
# run leaves you with an arm64 image whose apt-installed Java and GTK are arm64,
# executed under an amd64 personality - which fails in ways that look like
# anything but a platform mismatch.
#
# Everything else is the Makefile's docker-build target verbatim:
#
#   /builds   <- this directory's builds/, where the .hex lands
#   /onlykey  <- the parent directory, so the container sees OnlyKey-Firmware/
#               and libraries/ as siblings (in-docker-build.sh reads them there)
#   -u        <- run as the invoking user, so the .hex is not left root-owned
#
# What gets built is the WORKING TREE AT HEAD of the OnlyKey-Firmware checkout,
# not a pinned release - in-docker-build.sh does `git rev-parse HEAD` and stamps
# that commit into the version string. Building a specific release is the next
# problem, and not this script's.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="onlykey/onlykey-firmware-toolchain"
PLATFORM="linux/amd64"

say() { printf '\n== %s\n' "$*"; }

cd "$HERE"

# Fail early and say which step is missing, rather than letting docker produce
# its own message about a socket or a manifest three minutes into a build.
command -v docker >/dev/null 2>&1 || { echo "!! docker is not installed - run ./pi-setup.sh" >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo "!! cannot talk to the docker daemon. If you were just added to the
   docker group, this shell predates it - open a new one or run: newgrp docker" >&2; exit 1; }
[ -e /proc/sys/fs/binfmt_misc/qemu-x86_64 ] || { echo "!! qemu-x86_64 is not registered in binfmt_misc - run ./pi-setup.sh" >&2; exit 1; }

for d in ../OnlyKey-Firmware ../libraries; do
  [ -d "$d" ] || { echo "!! missing checkout: $d (expected beside this one)" >&2; exit 1; }
done

mkdir -p builds

# Dockerfile.pi, not the Dockerfile beside it. Same packages, but with ldconfig
# neutered and the install split into layers - both because this is emulated.
# See the comments in Dockerfile.pi; the short version is that ldconfig
# segfaults under qemu-user and takes the whole apt step down with it.
if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  say "building the toolchain image (once, ~30min emulated: arduino + GTK + Java)"
  docker build --platform "$PLATFORM" -f Dockerfile.pi -t "$IMAGE" .
else
  say "toolchain image present; skipping build (delete it to force: docker rmi $IMAGE)"
fi

say "building firmware from $(git -C ../OnlyKey-Firmware rev-parse --short HEAD) (working tree HEAD)"
echo "   this is emulated x86-64 - it will take a while"

START=$(date +%s)
# --ulimit nofile: the Arduino IDE is a Java program, and the JVM sizes its file
# descriptor table from RLIMIT_NOFILE at startup. Docker hands a container
# 1073741816 by default - a billion - where this host's own shell gets 1024. The
# JVM believes it and tries to allocate for all of them:
#
#     library initialization failed - unable to allocate file descriptor table
#       - out of memory
#     qemu: uncaught target signal 6 (Aborted) - core dumped
#
# which aborts before the IDE loads a single file. It is not an emulation bug
# and not a memory shortage in any meaningful sense; the limit is simply a lie
# the JVM takes at face value. 1024 matches the host and is far more than a
# compile needs.
docker run --rm \
  --platform "$PLATFORM" \
  --ulimit nofile=1024:1024 \
  -v "$HERE/builds:/builds" \
  -v "$HERE/..:/onlykey" \
  -u "$(id -u):$(id -g)" \
  "$IMAGE" "onlykey/arduino-1.6.5-r5-teensy_127/in-docker-build.sh"
ELAPSED=$(( $(date +%s) - START ))

# in-docker-build.sh cleans up after itself and copies the hex to /builds, so an
# empty builds/ here means the arduino step failed without a non-zero exit -
# which it can, since the IDE is quite willing to report success having produced
# nothing. Check for the artefact rather than trusting the exit code.
say "done in ${ELAPSED}s"
if compgen -G "builds/*.hex" >/dev/null; then
  ls -l builds/*.hex
else
  echo "!! no .hex in builds/ - the arduino step did not produce one" >&2
  exit 1
fi
