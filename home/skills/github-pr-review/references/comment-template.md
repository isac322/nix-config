# 리뷰 코멘트 템플릿

GitHub에 올리는 본문은 영어다. 문체, 길이, 공개 위생, 기존 코멘트 수정 여부, 승인 초안 대조는 `github-publishing`을 따른다. 아래는 PR 리뷰가 담아야 할 요소와 순서다. 해당 없는 섹션은 지운다.

## 리뷰 코멘트 (`gh pr review <N> --comment --body-file <file>`)

```markdown
**Verdict: BLOCKING** (PR-ready: false) reviewed at <head-sha>

<One or two sentences: does this PR fix the claimed problem at its root cause, and what must change before merge.>

## Blocking
- **P1** `path/to/file.go:123`: <mechanism: what breaks, for whom, under which input>. Fix: <smallest change>. Evidence: <command or line reference>.

## Non-blocking
- **P2** `path/to/file_test.go:45`: <issue>. Suggestion: <change>.

## Verified
- Reproduced <symptom> on merge-base <sha> with `<command>` (<version, environment>): fails.
- Same reproducer on this head rebased onto main <sha>: passes. Healthy control: passes.
- CI: <passing | failing: job name, deterministic or transient>.

## Not verified
- <area or environment not exercised, and why>.
```

`GREEN`일 때 첫 줄. `PR-ready`는 required check 통과와 충돌 없음까지 확인된 경우에만 `true`다(PRR-24):

```markdown
**Verdict: GREEN** (PR-ready: true) reviewed at <head-sha>. No blocking findings.
```

```markdown
**Verdict: GREEN** (PR-ready: false: <required check failing | merge conflict with main>) reviewed at <head-sha>. No blocking findings in the diff.
```

공개 저장소의 보안 finding은 세부 없이 적고, 사용자가 비공개 보고 경로를 정한 뒤에 게시한다(`references/review-dimensions.md` §5):

```markdown
## Blocking
- **P0** A security concern affects this change. Details will be shared with the maintainers privately.
```

일부만 main에 반영된 PR(`partially superseded`)은 `BLOCKING` 리뷰 코멘트로 남긴다. 요약 문단에 반영된 부분(main 커밋)과 main에 아직 없는 부분을 나눠 적고, 남은 부분만 남기도록 PR을 좁히는 방법을 blocking finding의 수정안으로 적는다.

- 첫 줄에 판정, PR-ready, 리뷰한 head SHA를 둔다.
- 요약 문단에 넣을 것: 무엇을 어떤 버전·환경에서 실행했는지, 재현 결과, 근본 원인(모르면 unknown이라고), PR이 그 원인을 고치는지, main이 무엇으로 이 PR을 대체했는지(해당 시), 머지하려면 무엇을 바꿔야 하는지.
- 추론이면 "by source reading, not run"처럼 표시한다.

## 재리뷰 코멘트

```markdown
**Verdict: GREEN** (PR-ready: true) re-reviewed at <new-head-sha> (previous: <old-head-sha>)

## Previous findings
- Closed: P1 `file.go:123` <short title>. Fixed at `file.go:130`; regression test `TestX` fails without the fix.
- Open: P2 `file_test.go:45` <short title>. Unchanged.

## New findings
- None.
```

## 닫기 코멘트 (외부·오래된 PR)

작성자가 저장소 소유자일 수 있으니 비례적인 어조를 유지한다. 닫기 지시가 있어 실제로 닫을 때와 권고만 할 때를 구분한다.

닫기 지시가 있어 닫을 때:

```markdown
Thanks for this PR. The problem it targets is already fixed on main by <commit-sha> (<#PR>), first released in <tag>.

Verification: <discriminating reproducer> fails on <old version> and passes on <released version> (<environment>).

Please use <version> or later. Closing this PR for that reason. If you still see the problem on <version>, please reopen with the traceback and your environment.
```

닫기 지시가 없어 권고만 할 때는 마지막 문단을 "Please use <version> or later. I recommend closing this PR. If you still see the problem on <version>, please reopen with the traceback and your environment."로 바꾼다.

main에는 있지만 릴리스되지 않았으면 버전 문장을 "The fix is merged but not yet in a published release."로 바꾼다(PRR-35).

## 라벨

게시 모드에서 리뷰 코멘트와 함께 하나를 붙인다(PRR-27). "확인만"이거나 쓰기 범위를 코멘트로 한정한 실행, 라벨 권한이 없을 때는 붙이지 않고 최종 보고에 제안한다. 상호배타다. 한 PR에 하나만 둔다. 라벨 권한 확인은 `github-publishing`의 라벨 메커닉을 따른다. 저장소에 같은 의미의 라벨이 있으면 그것을 쓴다. 생성·매핑 메커닉과 생성 가능 조건은 `github-publishing` 소관이다.

| 이름 | 설명(라벨 description, 영어) | 붙이는 조건 |
|---|---|---|
| `review:no-blocking-findings` | Agent review found no blocking findings as of the head SHA in the latest review comment. | 판정 `GREEN` |
| `review:changes-needed` | Blocking findings are listed as of the head SHA in the latest review comment. | 판정 `BLOCKING` |
| `review:superseded` | The change is already on the default branch or replaced by another PR, as of the head SHA in the latest review comment. | superseded 증명 완료(`references/stale-pr-audit.md`) |

- 판정을 바꾸면 이전 라벨을 제거하고 새 라벨을 붙인다(`gh pr edit <N> --remove-label A --add-label B`).
- head가 바뀌었는데 재리뷰하지 않을 거면 판정 라벨을 제거한다.
- P0–P3는 라벨로 만들지 않는다. 코멘트 본문에만 적는다.
