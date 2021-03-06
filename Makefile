install: build-release
	cp ./.build/release/munin ~/bin/.

publish: build
	scp ./.build/release/munin root@storage.terra.fap.no:/storage/nfs/k8s/builds/munin/.

generate:
	sourcery
	swift test --generate-linuxmain

build:
	swift build -c debug --sanitize=thread

build-release:
	swift build --configuration release

test:
	swift test

build-core-graphics:
	swift build -c debug --sanitize=thread -Xswiftc '-DCORE_GRAPHICS'

build-core-graphics-release:
	swift build --configuration release -Xswiftc '-DCORE_GRAPHICS'

dev:
	swift package generate-xcodeproj

upgrade:
	echo "Not implemented"

clean:
	rm -rf .build

reinstall:
	echo "Not implemented"

lint:
	swiftlint
	# swiftformat --lint Sources

fmt:
	swiftlint autocorrect
	swift-format --recursive --in-place Sources/ Package.swift

run: build
	./.build/x86_64-apple-macosx/debug/munin

run-cross: build-cross
	./.build/x86_64-apple-macosx/debug/munin
