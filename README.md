# arduino-1.6.5-r5-teensy_127

Expects `libraries/` and `OnlyKey-Firmware/` checked out as siblings of this
directory, not nested inside it.

Build the Docker toolchain image (one-time, or after `Dockerfile` changes)
```
make docker-build-toolchain
```

Build firmware from the local `../libraries` and `../OnlyKey-Firmware` checkouts
```
make docker-build
```

Output `.hex` files land in `builds/`; print them with
```
make show-build
```
