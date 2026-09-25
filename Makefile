.PHONY: build build-full cmake cmake-minimal cmake-full debug run pack appimage install install-deb install-rpm clean dump-seed load-seed act release opencode-check fennel-check constraints test test-e2e test-live-hot-reload test-slow test-integration test-all-lua profile commit prof download-models-data resize-logo docs devlog test-windows-wine

SPACE_TEST_ENV = SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_LOG_DIR=/tmp/space/tests/log SPACE_ASSETS_PATH=$(CURDIR)/assets
SPACE_FENNEL_ENV = FENNEL_PATH=$(CURDIR)/assets/lua/?.fnl\;$(CURDIR)/assets/lua/?/init.fnl FENNEL_MACRO_PATH=$(CURDIR)/assets/lua/?.fnl\;$(CURDIR)/assets/lua/?/init.fnl
SPACE_RUNTIME_ENV = $(SPACE_TEST_ENV) $(SPACE_FENNEL_ENV)
VALIDATION_OUTPUT = $(if $(VERBOSE),json,summary)

BUILD_DIR = build
BUILD_LOG = $(BUILD_DIR)/logs/build.log
BUILD_JOBS ?= 1
CMAKE_RELEASE = cmake -B $(BUILD_DIR) -DCMAKE_BUILD_TYPE=Release
CMAKE_MINIMAL = $(CMAKE_RELEASE) -DSPACE_BUILD_PROFILE=minimal -DSPACE_ENABLE_CEF=OFF
CMAKE_FULL = $(CMAKE_RELEASE) -DSPACE_BUILD_PROFILE=full -DSPACE_ENABLE_CEF=ON
BUILD_LOG_RUNNER = ./scripts/build-log-runner.sh --log $(BUILD_LOG)

cmake: cmake-minimal

cmake-minimal:
	$(CMAKE_MINIMAL) .

cmake-full:
	$(CMAKE_FULL) .

build:
	@$(BUILD_LOG_RUNNER) --label "space minimal build" -- bash -lc '$(CMAKE_MINIMAL) . && cmake --build $(BUILD_DIR) -- -j$(BUILD_JOBS)'

build-full:
	@$(BUILD_LOG_RUNNER) --label "space full CEF build" -- bash -lc '$(CMAKE_FULL) . && cmake --build $(BUILD_DIR) -- -j$(BUILD_JOBS)'

debug:
	mkdir -p build/debug && cd build/debug && cmake -DCMAKE_BUILD_TYPE=Debug ../..
	cd build/debug && $(MAKE) -j$(shell nproc)
	cd build/debug && gdb ./space

run:
	cd build && SPACE_FENNEL_PROFILE=1 SPACE_ASSETS_PATH=../assets ./space -m main --remote-control=ipc:///tmp/space-rc.sock

docs:
	cd docs && npm run docs:dev

devlog:
	cd docs && node scripts/open-devlog-entry.mjs

commit:
	codex exec "run `git add -A` and commit with a fitting message"

pack: build-full
	cd build && cpack

appimage: build-full
	./scripts/build-appimage.sh

install:
	@echo "ambiguous install target; use 'make install-deb' or 'make install-rpm'" >&2
	@exit 1

install-deb:
	@pkg=$$(find ./build -maxdepth 1 -type f \( -name 'space-linux-*.deb' -o -name 'space-*-Linux.deb' \) | head -n 1); \
	if [ -z "$$pkg" ]; then \
		echo "no DEB package artifact found in ./build"; \
		exit 1; \
	fi; \
	if ! command -v dpkg >/dev/null 2>&1; then \
		echo "dpkg not found"; \
		exit 1; \
	fi; \
	dpkg -i "$$pkg" || apt install -f

install-rpm:
	@pkg=$$(find ./build -maxdepth 1 -type f \( -name 'space-linux-*.rpm' -o -name 'space-*-Linux.rpm' \) | head -n 1); \
	if [ -z "$$pkg" ]; then \
		echo "no RPM package artifact found in ./build"; \
		exit 1; \
	fi; \
	if ! command -v dnf >/dev/null 2>&1; then \
		echo "dnf not found"; \
		exit 1; \
	fi; \
	dnf install "$$pkg"

clean:
	rm -rf build/*

fennel-check: build
	@$(SPACE_RUNTIME_ENV) ./build/space -m tools.fennel-check:main -- --output $(VALIDATION_OUTPUT) --target repo

constraints: fennel-check
	@$(SPACE_RUNTIME_ENV) ./build/space -m constraints.runner:main -- --output $(VALIDATION_OUTPUT) --target repo

test: constraints
	@$(SPACE_RUNTIME_ENV) xvfb-run -a python3 scripts/ctest-summary.py --test-dir build --output-on-failure -E "^space_fnl_tests_integration$$"

test-e2e:
	$(SPACE_RUNTIME_ENV) SDL_VIDEODRIVER=x11 xvfb-run -a -s "-screen 0 1280x720x24" ./build/space -m tests.e2e:main

test-slow:
	$(SPACE_RUNTIME_ENV) ./build/space -m tests.slow:main

test-integration:
	$(SPACE_RUNTIME_ENV) ./build/space -m tests.integration:main

test-all-lua:
	$(SPACE_RUNTIME_ENV) ./build/space -m tests.all:main
	$(SPACE_RUNTIME_ENV) ./build/space -m tests.slow:main

test-live-hot-reload:
	$(SPACE_RUNTIME_ENV) ./scripts/test-live-hot-reload.sh

test-windows-wine:
	./scripts/test-windows-under-wine.sh

prof:
	@if [ -z "$(target)" ]; then \
		echo "usage: make prof target=<name>"; \
		exit 1; \
	fi
	python3 scripts/prof.py $(target) $(args)

dump-seed:
	python scripts/seed.py dump

load-seed:
	python scripts/seed.py load

# test github workflows
act:
	gh act

# find last version tag, increment, create new tag and push
release:
	@last_tag=$$(git tag --list 'v*' | sort -V | tail -n1); \
	if [ -z "$$last_tag" ]; then \
		new_version="v1"; \
	else \
		num=$$(echo $$last_tag | sed 's/^v//'); \
		new_num=$$((num + 1)); \
		new_version="v$${new_num}"; \
	fi; \
	echo "Creating new annotated tag $$new_version"; \
	git tag -a $$new_version -m "$$new_version"; \
	git push origin $$new_version

opencode-check:
	python3 scripts/check_opencode_permissions.py --repo-root .
	python3 -m pytest scripts/tests/test_check_opencode_permissions.py scripts/tests/test_opencode_capabilities.py scripts/tests/test_opencode_git_integrate.py scripts/tests/test_opencode_pr_operator.py scripts/tests/test_opencode_windows_ci_repro.py scripts/tests/test_opencode_windows_ci_policy_docs.py

download-models-data:
	wget -O assets/data/models-dot-dev.json https://models.dev/api.json

resize-logo:
	mv assets/pics/space.png assets/pics/space.old.png
	ffmpeg -i assets/pics/space.old.png -vf "scale=256:-1:flags=lanczos" assets/pics/space.png
