# Changelog

What each image pushed to ECR contains, newest first. We rebase `greyfinch` onto
each upstream release, so shas change; this list is the record of what a tag
holds and what to expect when rolling back.

Add an entry when you push (`build.sh --push`), in a separate commit after the
image commit; the tag's sha is the commit that was built, not the one adding the
entry. Tag that commit too: `git tag image/<tag> && git push origin image/<tag>`.

Entry format: tag, push date, upstream base, our changes on top of upstream
(`git log <marker>..<sha>` lists them), and any behaviour difference from the
official image.

## v2.51.0-a719f12ed0

- **Base:** upstream v2.51.0 (`ci: tag release v2.51.0`).
- **Changes:** image packaging only (`packaging/graphql-engine/`, `.dockerignore`).
- **Behaviour:** none; same as the official v2.51.0 image (community edition, no
  MSSQL ODBC drivers, Postgres only, console assets from the official image).

## v2.51.0-b63bfebabf

- **Base:** upstream v2.51.0 (`ci: tag release v2.51.0`).
- **Changes:** support for multiple admin secrets via `HASURA_GRAPHQL_ADMIN_SECRETS`
  (`server: support multiple admin secrets with HASURA_GRAPHQL_ADMIN_SECRETS`), on
  top of the previous entry.
- **Behaviour:** `HASURA_GRAPHQL_ADMIN_SECRETS` accepts a JSON array of admin
  secrets (e.g. `["secret1", "secret2"]`); any of them authenticates as admin. It
  takes precedence over `HASURA_GRAPHQL_ADMIN_SECRET` when both are set, and
  invalid JSON fails startup. This is not in the official image. Otherwise the same
  as the previous entry.
