

all: docker-build-toolchain docker-build

help: 
	@echo "Build Docker Image for building"
	@echo "make docker-build-toolchain"
	@echo ""
	@echo "build firmware from local files"
	@echo "make docker-build"
	@echo ""

DOCKER_TOOLCHAIN_IMAGE := "onlykey/onlykey-firmware-toolchain"

docker-build-toolchain:
	docker build -t $(DOCKER_TOOLCHAIN_IMAGE) .

docker-build:
	docker run --rm -v "$(CURDIR)/builds:/builds" \
					-v "$(CURDIR)/..:/onlykey" \
					-u $(shell id -u ${USER}):$(shell id -g ${USER}) \
				    $(DOCKER_TOOLCHAIN_IMAGE) "onlykey/arduino-1.6.5-r5-teensy_127/in-docker-build.sh"

show-build:
	cat ./builds/*.hex

	
