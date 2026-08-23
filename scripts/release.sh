#!/bin/sh

# usage: scripts/release.sh <patch|minor|major>
#        scripts/release.sh set <x.y.z>
set -eu

fail() {
    echo "error: $1" >&2
    exit 1
}

usage() {
    echo "usage: $0 <patch|minor|major>" >&2
    echo "       $0 set <x.y.z>" >&2
    exit 2
}

branch="$(git rev-parse --abbrev-ref HEAD)"
[ "$branch" = "master" ] || fail "releases are cut from master (current branch: $branch)"
[ -z "$(git status --porcelain)" ] || fail "working tree is not clean"
grep -q '^## \[Unreleased\]' CHANGELOG.md ||
    fail "CHANGELOG.md has no [Unreleased] section"

mode="bump"
bump=""
if [ "$#" -eq 1 ]; then
    case "$1" in
        patch|minor|major) bump="$1" ;;
        *) usage ;;
    esac
elif [ "$#" -eq 2 ] && [ "$1" = "set" ]; then
    mode="set"
else
    usage
fi

# Strict x.y.z split: exactly three non-empty numeric components.
parse_version() {
    rest="$1"
    case "$rest" in
        *.*) ;;
        *) return 1 ;;
    esac
    _v_major="${rest%%.*}"
    rest="${rest#*.}"
    case "$rest" in
        *.*) ;;
        *) return 1 ;;
    esac
    _v_minor="${rest%%.*}"
    _v_patch="${rest#*.}"
    case "$_v_major$_v_minor$_v_patch" in
        *[!0-9]*|"") return 1 ;;
    esac
}

# Current version is read from the language-neutral document header.
version="$(sed -n 's/^\*\*Version:\*\*[ `]*\([0-9][0-9.]*\).*/\1/p' SPECIFICATION.md | head -n 1)"
[ -n "$version" ] || fail "could not read a numeric version from the SPECIFICATION.md header"
parse_version "$version" || fail "unsupported version format '$version' in SPECIFICATION.md"
cur_major="$_v_major"; cur_minor="$_v_minor"; cur_patch="$_v_patch"

if [ "$mode" = "set" ]; then
    parse_version "$2" || fail "set expects strict numeric x.y.z, got '$2'"
    next="$2"
    next_major="$_v_major"; next_minor="$_v_minor"; next_patch="$_v_patch"
    if [ "$next_major" -ne "$cur_major" ]; then
        increasing=$((next_major > cur_major))
    elif [ "$next_minor" -ne "$cur_minor" ]; then
        increasing=$((next_minor > cur_minor))
    else
        increasing=$((next_patch > cur_patch))
    fi
    [ "$increasing" -eq 1 ] ||
        fail "new version $2 must be greater than current $version"
else
    major="$cur_major"; minor="$cur_minor"; patch="$cur_patch"
    if [ "$bump" = "major" ]; then
        major=$((major + 1)); minor=0; patch=0
    elif [ "$bump" = "minor" ]; then
        minor=$((minor + 1)); patch=0
    else
        patch=$((patch + 1))
    fi
    next="$major.$minor.$patch"
fi

# Rewrite only the numbers so file formatting survives untouched. Replica
# manifests are matched number-agnostically so drift heals toward the
# header instead of silently no-oping.
sed -i "s/^\(\*\*Version:\*\*[ \`]*\)[0-9][0-9.]*/\1$next/" SPECIFICATION.md
if [ -f package.json ]; then
    sed -i "0,/\"version\": *\"[0-9][0-9.]*\"/s//\"version\": \"$next\"/" package.json
fi

grep -q "^\*\*Version:\*\*[ \`]*$next" SPECIFICATION.md ||
    fail "SPECIFICATION.md header update did not apply"
if [ -f package.json ]; then
    grep -q "\"version\": *\"$next\"" package.json ||
        fail "package.json version sync did not apply"
fi

today="$(date +%Y-%m-%d)"
sed -i "s/^## \[Unreleased\]\$/## [$next] - $today/" CHANGELOG.md

git add SPECIFICATION.md CHANGELOG.md
[ ! -f package.json ] || git add package.json
git commit -m "chore(release): $next"
git tag -a "v$next" -m "v$next"

echo ""
echo "release $next committed and tagged locally."
echo "publish when ready:"
echo "  git push --follow-tags origin master"
