.PHONY: build test app run install clean

build:
	swift build

test:
	swift test

app:
	./scripts/build-app.sh

run: app
	open dist/BetterDictation.app

# 安装到 /Applications 并在后台启动（不占用终端）
install:
	./scripts/install.sh

clean:
	rm -rf .build dist
