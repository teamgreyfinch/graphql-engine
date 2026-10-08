#!/usr/bin/env bash
# Build (and optionally push) the graphql-engine image, deriving the upstream
# Hasura version from the git history so the console assets and the image tag
# stay in line with what this checkout is based on.
#
#   ./build.sh --print-tag     print the image tag and exit (v<version>-<git sha>)
#   ./build.sh                 build the image locally as hasura-graphql-engine:<tag>
#   ./build.sh --push          build, then push to $ECR_REPO and move `latest` to it
#
# Environment:
#   AWS_PROFILE     AWS profile for --push (log in first: aws sso login --profile <profile>)
#   ECR_REPO        repository to push to, e.g. 123456789012.dkr.ecr.eu-west-1.amazonaws.com/name
#                   (several, whitespace separated, are pushed with the same tag)
#   PLATFORM        default: native (linux/arm64 or linux/amd64)
#   BUILD_JOBS      passed through to the Dockerfile (default there)
#   CONSOLE_ASSETS_IMAGE  official image to take console assets from (default: hasura/graphql-engine:<version>)
#   HGE_VERSION     version the server reports (default: the upstream release, e.g. v2.51.0)
#   ALLOW_DIRTY=1   build even with uncommitted changes in the build inputs
set -euo pipefail

mode=build
case "${1:-}" in
  --print-tag) mode=print ;;
  --push) mode=push ;;
  "") ;;
  *) echo "usage: $0 [--print-tag|--push]" >&2; exit 2 ;;
esac

root=$(git rev-parse --show-toplevel)
cd "$root"

# Upstream Hasura release this checkout is based on: the newest "ci: tag release vX.Y.Z"
# marker commit reachable from HEAD, i.e. the one nearest to HEAD. The greyfinch branch sits
# on such a commit of upstream master, whose source equals the official release (see README),
# and our patches on top don't change it. Nearest rather than highest version, because
# maintenance lines (v2.45.x, v2.49.x) are marked on master too.
# (git describe doesn't work here: release tags are not ancestors of master.)
version=$(git log --format=%s --grep='^ci: tag release v' \
  | awk '!v && /^ci: tag release v[0-9][0-9.]*$/ { v = $4 } END { print v }')
[ -n "$version" ] || { echo "no 'ci: tag release' commit found in history" >&2; exit 1; }

sha=$(git rev-parse --short=10 HEAD)
tag="${version}-${sha}"

if [ "$mode" = print ]; then echo "$tag"; exit 0; fi

# Only paths that go into the binary/image count (ignores unrelated untracked files).
build_inputs=(server cabal cabal.project cabal.project.freeze preload-mimalloc metadata-api-types packaging)
if [ -n "$(git status --porcelain -- "${build_inputs[@]}")" ] && [ "${ALLOW_DIRTY:-}" != 1 ]; then
  git status --short -- "${build_inputs[@]}" >&2
  echo "uncommitted changes in build inputs, so tag $tag would not identify the source." >&2
  echo "commit them first (or ALLOW_DIRTY=1 to override)." >&2
  exit 1
fi

# Console assets come from the official image of the same release.
console_image="${CONSOLE_ASSETS_IMAGE:-hasura/graphql-engine:${version}}"
if ! docker manifest inspect "$console_image" >/dev/null 2>&1; then
  echo "official image $console_image is not published (yet); cannot take console assets from it." >&2
  echo "pick an older release explicitly, e.g. CONSOLE_ASSETS_IMAGE=hasura/graphql-engine:v2.50.0." >&2
  exit 1
fi

if [ -z "${PLATFORM:-}" ]; then
  case "$(uname -m)" in
    arm64|aarch64) PLATFORM=linux/arm64 ;;
    *) PLATFORM=linux/amd64 ;;
  esac
fi

args=(--platform "$PLATFORM"
  --build-arg "CONSOLE_ASSETS_IMAGE=$console_image"
  -f packaging/graphql-engine/multistage.dockerfile
  -t "hasura-graphql-engine:$tag")
[ -n "${BUILD_JOBS:-}" ] && args+=(--build-arg "BUILD_JOBS=$BUILD_JOBS")
# Version the server reports about itself; same as upstream's release by default.
args+=(--build-arg "HGE_VERSION=${HGE_VERSION:-$version}")

echo "==> upstream version: $version"
echo "==> image tag:        $tag ($PLATFORM)"
docker buildx build "${args[@]}" --load .

if [ "$mode" = push ]; then
  : "${ECR_REPO:?set ECR_REPO to push}"
  # ECR_REPO may list several repositories (whitespace separated); same image, same tag.
  logged_in=" "
  for repo in $ECR_REPO; do
    registry=${repo%%/*}
    region=$(echo "$registry" | sed -n 's/.*\.ecr\.\([^.]*\)\.amazonaws\.com/\1/p')
    if [[ "$logged_in" != *" $registry "* ]]; then
      aws ecr get-login-password --region "$region" \
        | docker login --username AWS --password-stdin "$registry"
      logged_in+="$registry "
    fi
    docker tag "hasura-graphql-engine:$tag" "$repo:$tag"
    docker push "$repo:$tag"
    echo "==> pushed $repo:$tag"
    # `latest` always follows the most recent push (repositories have mutable tags).
    docker tag "hasura-graphql-engine:$tag" "$repo:latest"
    docker push "$repo:latest"
    echo "==> latest -> $tag in $repo"
  done
fi
