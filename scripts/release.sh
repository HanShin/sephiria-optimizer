#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
REQUESTED_VERSION="${1:-}"
PUSH_RELEASE="${2:-}"

if [[ -z "$REQUESTED_VERSION" ]]; then
    echo "사용법: ./scripts/release.sh <patch|minor|major|0.2.1> [--push]" >&2
    exit 1
fi
if [[ -n "$PUSH_RELEASE" && "$PUSH_RELEASE" != "--push" ]]; then
    echo "두 번째 인자는 --push만 사용할 수 있습니다." >&2
    exit 1
fi

cd "$PROJECT_DIR"

if [[ "$(git branch --show-current)" != "main" ]]; then
    echo "릴리스는 main 브랜치에서 실행해 주세요." >&2
    exit 1
fi
if [[ -n "$(git status --porcelain)" ]]; then
    echo "커밋되지 않은 변경 사항이 있습니다. 먼저 커밋하거나 정리해 주세요." >&2
    exit 1
fi
if ! git remote get-url origin >/dev/null 2>&1; then
    echo "origin 원격 저장소가 설정되어 있지 않습니다." >&2
    exit 1
fi

CURRENT_VERSION="$(<VERSION)"
NEXT_VERSION="$(node scripts/version.mjs resolve "$REQUESTED_VERSION")"
TAG="v$NEXT_VERSION"
if git rev-parse "$TAG" >/dev/null 2>&1; then
    echo "이미 존재하는 태그입니다: $TAG" >&2
    exit 1
fi

VERSION_COMMITTED=0
rollback_version() {
    if [[ "$VERSION_COMMITTED" == "0" ]]; then
        node scripts/version.mjs set "$CURRENT_VERSION" >/dev/null 2>&1 || true
    fi
}
trap rollback_version ERR INT TERM

node scripts/version.mjs set "$NEXT_VERSION"
node scripts/version.mjs check

npm --prefix windows ci
npm --prefix windows test

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/sephiria-clang-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="${TMPDIR:-/tmp}/sephiria-swiftpm-module-cache" \
swift test --disable-sandbox --cache-path "${TMPDIR:-/tmp}/sephiria-swiftpm-cache"

git add VERSION Info.plist windows/package.json windows/package-lock.json
git commit -m "Release $TAG"
git tag -a "$TAG" -m "Release $TAG"
VERSION_COMMITTED=1
trap - ERR INT TERM

if [[ "$PUSH_RELEASE" == "--push" ]]; then
    git push origin main
    git push origin "$TAG"
    echo "GitHub Actions가 $TAG 릴리스 파일을 생성합니다."
else
    echo "릴리스 준비 완료: $TAG"
    echo "게시하려면 다음 명령을 실행하세요:"
    echo "  git push origin main"
    echo "  git push origin $TAG"
fi
