# Changelog

What our images contain, newest first. We rebase `greyfinch` onto each upstream
release, so shas change; this list is the record of what changed and when, and
what to expect when rolling back.

Add the entry in the **same commit** as the change (a commit can't name its own
sha, and amending later would break it). Don't edit it after the push; fix
forward with a new commit. Don't put a sha in the entry: identify the change by
the date of its commit (`git log --format='%h %ad %s' --date=short`) and its
commit subject. To find the image, pick the ECR tag `v<version>-<sha>` whose
commit is that one or a later one (`git log --oneline` shows the shas).

Entry format, as a heading `## 2026-01-07 feat(server): add log redaction for sensitive fields

- **Base:** upstream v2.51.6 (`ci: tag release v2.51.6`).
- **Changes:** log redaction (`feat(server): add log redaction for sensitive fields`,
  authored by Dario Cravero in his fork and applied here).
- **Behaviour:** new `HASURA_GRAPHQL_REDACTED_LOG_FIELDS` / `--redacted-log-fields`,
  a JSON array of field names (e.g. `["password", "token"]`). In every log entry, the
  values of JSON keys matching a name are replaced with `"[REDACTED]"`; matching
  ignores case, `_` and `-`, and is exact on the whole key (`token` does not match
  `access_token`). Secrets inside strings, such as literals in the logged `query`
  text, are not redacted. Default `[]`: no redaction, same as the official image.
  This is not in the official image.

## <commit date> <commit subject>`: upstream base,
what changed (`git log <marker>..HEAD` lists our changes), and any behaviour
difference from the official image.

New entries go at the top. The entries keyed by image tag further down are from
the earlier format and are kept as is.

## 2026-11-20 packaging: note rebase onto upstream v2.51.6

- **Base:** upstream v2.51.6 (`ci: tag release v2.51.6`), up from v2.51.0. The
  image tag changes from `v2.51.0-<sha>` to `v2.51.6-<sha>`, and the console
  assets now come from `hasura/graphql-engine:v2.51.6`.
- **Changes:** rebase only, plus everything upstream shipped between v2.51.0 and
  v2.51.6. Our patches are unchanged: multi-stage packaging, multiple admin
  secrets, ECR build from CircleCI, and skipping the metadata fetch and schema
  cache lock for one-off scheduled events (this last one had no entry before).
- **Image build:** `multistage.dockerfile` mirrors upstream's base image changes
  since v2.51.0: Ubuntu `noble-20260911` -> `noble-20261024.1`, `libbrotli1` and
  `apt-transport-https` installed, build fails if `ca-certificates`, `libbrotli1` or
  `apt` are older than the security-fixed versions, and `update-ca-certificates
  --fresh`. GHC and cabal are unchanged (9.14.1 / 3.16.1.0).
- **Behaviour:** as the entries below, plus the upstream fixes in v2.51.1 to
  v2.51.6. To roll back, deploy the newest ECR tag `v2.51.0-<sha>`.

## v2.51.0-b63bfebabf

- **Base:** upstream v2.51.0 (`ci: tag release v2.51.0`).
- **Changes:** support for multiple admin secrets via `HASURA_GRAPHQL_ADMIN_SECRETS`
  (`server: support multiple admin secrets with HASURA_GRAPHQL_ADMIN_SECRETS`), on
  top of the entry below.
- **Behaviour:** `HASURA_GRAPHQL_ADMIN_SECRETS` accepts a JSON array of admin
  secrets (e.g. `["secret1", "secret2"]`); any of them authenticates as admin. It
  takes precedence over `HASURA_GRAPHQL_ADMIN_SECRET` when both are set, and
  invalid JSON fails startup. This is not in the official image. Otherwise the same
  as the entry below.

## v2.51.0-a719f12ed0

- **Base:** upstream v2.51.0 (`ci: tag release v2.51.0`).
- **Changes:** image packaging only (`packaging/graphql-engine/`, `.dockerignore`).
- **Behaviour:** none; same as the official v2.51.0 image (community edition, no
  MSSQL ODBC drivers, Postgres only, console assets from the official image).
