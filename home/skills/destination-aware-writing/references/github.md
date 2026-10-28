# GitHub destination adapter

Use this reference with `isac-github-publishing` and the caller's GitHub skill. This file selects the writing shape; it does not replace GitHub's posting, sanitization, duplicate, approval, or language rules.

## Draft artifact

Required source inputs:

- repository and target branch when known
- change summary or issue context
- actual diff or implementation record
- tests and command results
- unverified scope and risks

Recommended sections for a PR body:

1. Summary
2. Changes
3. Validation
4. Risks or limitations
5. Not verified

Keep each factual statement tied to a source record. A requested behavior belongs under intent or remaining work until an implementation or test source proves it. Do not add `Fixes #N`, owner, deployment, readiness, or test claims without evidence.

Public GitHub text is English by the existing repository contract. Apply `writing-clearly-and-concisely`, `humanizer`, and, for comments, `comment-writer` after the source facts and PR structure are fixed.

## Publish boundary

A draft must not call GitHub write tools. Publish only through `isac-github-publishing` and the global pull-request creation and approval rules. Recheck the current repository state immediately before posting.
