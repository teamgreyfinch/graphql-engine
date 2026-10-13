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

Entry format, as a heading `## <commit date> <commit subject>`: upstream base,
what changed (`git log <marker>..HEAD` lists our changes), and any behaviour
difference from the official image.

New entries go at the top. The entries keyed by image tag further down are from
the earlier format and are kept as is.

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
