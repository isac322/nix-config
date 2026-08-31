---
description: Preserve the pending runbear-bot response guard across compaction after review or re-review is requested.
alwaysApply: true
---

# Pending runbear-bot review

- After requesting or re-requesting `runbear-bot`, only a response submitted after that request satisfies it; earlier reviews do not.
- While that response is pending, do not proceed to merge or report the review cycle as complete.
- If an external dependency prevents the response, report the state as pending rather than complete.
