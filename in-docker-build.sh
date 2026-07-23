#!/bin/bash -xe

# Most people won't need the ability to compile firmware themselves, as you
# can't load custom firmware unless you have a developer OnlyKey.
# https://github.com/trustcrypto/OnlyKey-Firmware/issues/59

# Local-only build: firmware and libraries come from the sibling checkouts
# mounted at /onlykey/OnlyKey-Firmware and /onlykey/libraries (see Makefile's
# docker-build target), not from a remote fork/branch.
firmware_git_path=/onlykey/OnlyKey-Firmware
libraries_git_path=/onlykey/libraries
firmware_file=OnlyKey/OnlyKey.ino

cd /builds
rm -rf /builds/arduino-1.6.5-r5*
#get clean arduino
cp -a /onlykey/arduino-1.6.5-r5-teensy_127/arduino-1.6.5-r5 /builds/.

rm -rf /builds/OnlyKey-Firmware
#get firmware
cp -a $firmware_git_path /builds/OnlyKey-Firmware

##get firmware-commit
cd /builds/OnlyKey-Firmware
commit=$(git rev-parse --verify HEAD | cut -c1-7)
cd /builds

#copy firmware
cp /builds/OnlyKey-Firmware/*.c ./arduino-1.6.5-r5/hardware/teensy/avr/cores/teensy3/.
cp /builds/OnlyKey-Firmware/*.h ./arduino-1.6.5-r5/hardware/teensy/avr/cores/teensy3/.

#copy custom libraries
cp -a $libraries_git_path/* /builds/arduino-1.6.5-r5/libraries/.

cd /builds/arduino-1.6.5-r5
mv ./libraries/onlykey/onlykey.h ./libraries/onlykey/onlykey.h_orig
sed "s/.0\-test/.0\-${commit}/g" ./libraries/onlykey/onlykey.h_orig > ./libraries/onlykey/onlykey.h
/usr/bin/xvfb-run -- ./arduino --verify ../OnlyKey-Firmware/$firmware_file \
  --preferences-file ./preferences.txt \
  -v

cd /builds
rm -rf /builds/*.hex
cp /builds/build/*.hex /builds/.
rm -rf /builds/arduino-1.6.5-r5
rm -rf /builds/build
