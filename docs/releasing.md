# Releasing

Omaset's marketplace identity is a **commit SHA**, not a version string. The
marketplace verifies and publishes one exact snapshot; the version number is
display metadata for that snapshot. Releasing follows from that.

## One version per published snapshot

- A version number describes a *published* snapshot. Review rounds — pushing
  fixes in response to verification findings — do not bump the version; they
  accumulate under the version currently being verified.
- `CHANGELOG.md` keeps the in-progress changes under `## Unreleased`. When a
  snapshot is accepted and published, rename that heading to
  `## <version> — <date>` and start the next change set at the next version.
- `manifest.json`'s `version` holds the version of the train in progress. It is
  left alone until the train is published; the next train bumps it once.

## Tags are release artifacts

A `v<version>` tag is created when a snapshot is accepted, pointing at the
exact accepted commit. It is never created per review commit, and a tag that
predates publication (i.e. was cut for an unreleased commit) is moved to the
accepted commit before it is published — nothing was released against it yet.

## Requesting verification of a new commit

Do not open a new issue per review round. Edit the existing verification
issue's `Target commit` field to the new 40-character SHA; editing reruns
compatibility validation and the Automated Security Baseline against that exact
commit. The previous marketplace snapshot stays unchanged until a maintainer
applies `approved-and-verified`.
