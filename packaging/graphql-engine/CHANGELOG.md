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
