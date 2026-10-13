# Greyfinch graphql-engine image (Hasura v2)

We build our own `graphql-engine` image from this fork, so we can carry patches
Hasura doesn't support, while behaving like the official image otherwise.
[multistage.dockerfile](multistage.dockerfile) compiles the server and builds a
runtime image in one `docker build`; [build.sh](build.sh) wraps it (version, tag,
push).

## Key decisions

- **Released code only.** The `greyfinch` branch is upstream's
  `ci: tag release vX.Y.Z` commit on `master` plus our commits on top. `master`
  itself is a mirror that also contains unreleased upstream work, so we never
  build from it directly.
- **One long-lived branch**, rebased onto each new upstream release. No branch
  per release.
- **Behaves like the official image:** the server reports the upstream version
  (`v2.51.0`), and console assets are copied from the official image of the same
  release (the console is built in a separate pipeline we don't run).
- **Postgres only** (no MSSQL ODBC drivers), single-architecture images: build
  natively on the target arch (arm64 for our ECS tasks); QEMU cross-builds are
  far too slow for GHC.

## How releases work

Upstream marks each release with a `ci: tag release vX.Y.Z` commit on `master`
(it adds a line to `server/src-rsr/catalog_versions.txt`). The source at that
commit equals the official release; the release tag itself lives on a separate
chain that only adds empty files under `releases/`. Release tags are therefore
not ancestors of `master`, and `git describe` gives the wrong version, so
`build.sh` reads these marker commits instead (the one nearest to `HEAD`).

```sh
git log --grep='^ci: tag release' --format='%h %s' -3   # markers in history
git log <marker>..greyfinch                             # exactly what we changed
```

**Image tag:** `v<upstream version>-<10-char git sha>`, e.g. `v2.51.0-514ca3f7ef`.
The version says which Hasura release we are based on; the short sha pins the exact
source including our patches (`git rev-parse <sha>` expands it).

What changed, and when, is recorded in [CHANGELOG.md](CHANGELOG.md); add an entry in the same commit as each change.

### Moving to a new upstream release

```sh
git remote add upstream https://github.com/hasura/graphql-engine   # once
git fetch upstream master && git fetch upstream tag vX.Y.Z

OLD=$(git log --grep='^ci: tag release' --format=%H -1)    # current base
NEW=$(git log upstream/master --grep='^ci: tag release vX.Y.Z$' --format=%H -1)

git diff --stat "$NEW" vX.Y.Z -- . ':!releases'   # must print nothing: marker == release
git rebase --onto "$NEW" "$OLD" greyfinch
git push --force-with-lease origin greyfinch
```

Always rebase onto a marker commit of a **released** version, never an arbitrary
`master` commit. Rebasing rewrites our shas, which is why the changelog identifies
changes by commit date and subject rather than by sha.

## Build and publish

### CircleCI (normal path)

Every push to `greyfinch` runs [.circleci/config.yml](../../.circleci/config.yml)
on an arm64 machine executor: it calls `build.sh --push`, which builds the image
and pushes `v<version>-<sha>` plus `latest` to all four ECR repositories. This
file replaces Hasura's upstream CircleCI config (which can't run for us); if it
conflicts during a rebase onto a new release, keep ours
(`git checkout --theirs .circleci/config.yml`; "theirs" is our commit in a rebase).

One-time setup: CircleCI project for `teamgreyfinch/graphql-engine`, and a context
`hasura-ecr-push` with `AWS_ACCOUNT_ID`, `AWS_DEFAULT_REGION` (together they give the
registry `<account>.dkr.ecr.<region>.amazonaws.com`), `AWS_ACCESS_KEY_ID` and
`AWS_SECRET_ACCESS_KEY` (an IAM user allowed `ecr:GetAuthorizationToken` and push
actions on the four repositories) and optionally `DOCKERHUB_USERNAME` /
`DOCKERHUB_PASSWORD`. To rebuild without a new commit, use "Rerun workflow" in
the CircleCI UI. A build takes about an hour (no layer cache in CI). CI does not
deploy to ECS.

### Locally

```sh
packaging/graphql-engine/build.sh --print-tag   # show the tag only
packaging/graphql-engine/build.sh               # build locally, no AWS needed
```

To push to ECR, log in with AWS SSO first (only needed when pushing, so you can
do it while the build runs), then pass the profile and repositories as
environment variables to the command, no `export` required:

```sh
aws sso login --profile greyfinch-admin

R=<account-id>.dkr.ecr.us-east-1.amazonaws.com
AWS_PROFILE=greyfinch-admin \
ECR_REPO="$R/gf-training-hasura-graphql-engine $R/greyfinch-demo-hasura-graphql-engine $R/greyfinch-staging-hasura-graphql-engine $R/hub-production-hasura-graphql-engine" \
  packaging/graphql-engine/build.sh --push
```

`ECR_REPO` takes one or more repositories (whitespace separated); the same image
and tag go to each. The region is read from the repository URL. If the SSO
session expires mid-push, log in again and rerun the same command: the image is
already built, so it only logs in, tags and pushes.

`build.sh` refuses to run with uncommitted changes in the build inputs (the sha
would not identify the source). `--push` pushes the versioned tag and also moves
`latest` to the new image in every repository (tags are mutable), so anything
that pulls `latest` gets it on its next task start. To roll back, re-point
`latest` at the previous tag, e.g. with
`aws ecr batch-get-image` / `put-image`, or `docker buildx imagetools create -t <repo>:latest <repo>:<old-tag>`.
Environment: `AWS_PROFILE`, `ECR_REPO`, `PLATFORM`, `BUILD_JOBS`, `HGE_VERSION`, `CONSOLE_ASSETS_IMAGE`, `ALLOW_DIRTY=1`.

The first build takes ~1 hour and ~12-16 GB of RAM for Docker; later builds reuse
cached layers unless the Haskell sources or `HGE_VERSION` change.

Dockerfile build args (set by `build.sh` where noted):

| Arg | Default | Purpose |
| --- | --- | --- |
| `HGE_VERSION` | `v2-greyfinch`; `build.sh` passes the release, e.g. `v2.51.0` | Written to the gitignored `server/CURRENT_VERSION` and compiled in; what `graphql-engine version` reports. |
| `CONSOLE_ASSETS_IMAGE` | `hasura/graphql-engine:v2.51.0`; `build.sh` passes the matching release | Official image the console assets are copied from. |
| `BUILD_JOBS` | `4` | Parallel GHC jobs, ~2 GB RAM each. Lower it if GHC gets OOM-killed. |
| `GHC_VERSION`, `CABAL_VERSION` | from `server/VERSIONS.json` | Toolchain. |

Without `build.sh`, from the repo root:
`docker buildx build -f packaging/graphql-engine/multistage.dockerfile -t my-hge .`

## Running and deploying

Use the same environment as the official image; replace the `image:` in compose,
or the container image in the ECS task definition. Console:
`HASURA_GRAPHQL_ENABLE_CONSOLE=true` and
`HASURA_GRAPHQL_CONSOLE_ASSETS_DIR=/srv/console-assets`.

- **ECS:** `runtimePlatform.cpuArchitecture` must match the image (`ARM64` for
  images built on Apple Silicon/Graviton), otherwise tasks fail with
  `exec format error`.
- **Env vars matter:** if metadata references env vars (`{{HASURA_ACTIONS_URL}}`
  etc.) that aren't set, Hasura reports inconsistent metadata.
- **One instance per metadata DB** for anything beyond a quick test: every
  instance runs event-trigger and scheduled-trigger workers.
- Back up the database and metadata before moving to a newer Hasura version.
