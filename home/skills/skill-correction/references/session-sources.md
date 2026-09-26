# 원본 세션 찾기

메인은 이 문서로 경로와 앵커만 해석하고 JSONL 내용은 읽지 않는다(앵커 확정용 스크립트 검색은 매치된 id와 시각만 출력). 표기: **확인** = 작성 시 읽기 전용으로 직접 확인한 사실, **[추론]** = 확인하지 못한 가정. 하네스가 업데이트되면 먼저 다시 확인한다.

메인이 분석 서브에이전트에 넘기는 것은 다음 하나다. `sessions`의 첫 항목은 지적이 나온 세션이다.

```json
{"harness": "omp|claude|codex", "cwd": "<세션 cwd>", "anchor_hint": "<사용자가 준 지적 요지·시각·키워드, 1줄>",
 "sessions": [{"session_file": "<절대경로>", "anchor_msg_id": "<id 또는 null>", "subagent_dir": "<경로 또는 null>"}]}
```

"이전에 말했잖아"처럼 이전 지시를 가리키는 교정이면, 사용자가 지목한 세션과 같은 cwd의 최근 세션 몇 개에서 해당 지시를 아래 스크립트 검색(id와 시각만 출력)으로 찾아 `sessions`에 더한다. 찾지 못해도 분석은 진행하고, 서브에이전트가 owner 스킬 `cases.md` 출처 색인에서 원래 지시를 찾는다.

## OMP

### 현재 세션

- 메인 `eval` 커널에서 `os.environ["PI_SESSION_FILE"]`을 읽는다. 값은 메인 세션 JSONL 경로다(확인).
- 이 변수는 커널 소유자 기준이다. 서브에이전트 커널에서는 그 서브에이전트 자신의 transcript를 가리킨다(확인). 그래서 반드시 메인이 읽어서 경로를 넘긴다. bash 환경에는 이 변수가 없을 수 있다.

### 폴백과 과거 세션

- 디렉터리: `~/.omp/agent/sessions/--<realpath(cwd)에서 앞의 / 를 빼고 / 를 - 로 바꾼 값>--/`(확인). macOS에서 `/etc/nix-darwin`은 realpath가 `/private/etc/nix-darwin`이므로 `--private-etc-nix-darwin--`가 된다.
- 파일명: `<ISO 시각, : 와 . 를 - 로 바꿈>_<sessionId>.jsonl`(예: `2026-09-26T12-18-11-514Z_<uuid>.jsonl`, 확인). 사용자가 세션 ID(앞 8자라도)를 주면 `*_<id>*.jsonl`로 찾는다.
- 사용자가 시각이나 키워드만 주면 해당 cwd 디렉터리의 최신 파일 몇 개에서 `role:"user"` 메시지를 스크립트로 검색하고, 매치된 msg id와 시각만 출력한다. 후보가 여럿이면 3개 이내로 제시해 사용자가 고르게 한다.
- 확정 조건: `type:"session"` record의 `cwd`가 기대한 cwd와 같고, 지적 문구 일부가 사용자 메시지에 있다. mtime만으로 확정하지 않는다(병렬 세션과 서브에이전트 파일 때문에 틀린다).

### 파일 구조 (확인)

- 1번째 record는 `type:"title"`, 2번째는 `type:"session"`(`id`, `timestamp`, `cwd`)이다. `cwd`에는 realpath가 아닌 원래 경로가 들어 있다.
- 서브에이전트 transcript: `<세션 파일명에서 .jsonl을 뺀 디렉터리>/<AgentName>.jsonl`. 그 `session` record에 `parentSession`(메인 JSONL 경로)이 있다. 같은 디렉터리의 `<n>.<tool>.log`는 잘린 도구 출력의 원본이다. `.<Agent>.jsonl.lock.os`는 무시한다.
- record 종류:
  - `message`: `id`(8자 hex, msg id로 인용), `parentId`, `timestamp`, `message.role`이 `user`, `assistant`, `toolResult` 중 하나.
  - `custom_message`: 하네스가 주입한 내용. `customType`이 `goal-mode-context`이면 사용자가 설정한 goal 텍스트이므로 사용자 근거로 읽는다. `orchestrate-notice`, `jevify-notice`, `async-result`, `xdev-mount-notice` 등은 하네스·서브에이전트 산출물이다.
  - `model_usage`, `custom`(`tool_execution_start`), `mode_change` 등: 분석에서 제외한다. 대부분의 줄이 `model_usage`다.
- ask 답변: `message.role:"toolResult"`, `message.toolName:"ask"`. `content` 텍스트가 `User answers:\n<질문 id>: <답>` 형식이고, `details.results`에 질문 원문과 답이 있다(확인). 1차 사용자 근거이므로 반드시 채굴한다.
- 사용자 메시지에 `<system-notice>`, `<system-reminder>` 블록이 섞일 수 있다. 이 블록은 하네스 주입이므로 사용자 발화에서 제거하고 읽는다.
- `history://`는 현재 세션에 등록된 에이전트만 보여 주므로 과거 세션 탐색에 쓰지 않는다.

## Claude Code

- 경로: `~/.claude/projects/<인코딩된 cwd>/<sessionId>.jsonl`(확인). 인코딩은 cwd의 `/`와 `.`을 `-`로 바꾼 값이다(확인). 다른 특수문자도 `-`로 바뀐다고 본다 [추론].
- 서브에이전트: `<project 디렉터리>/<sessionId>/subagents/agent-<id>.jsonl`(확인).
- record의 `type`은 `user`, `assistant` 등이고 `sessionId`, `cwd`, `uuid`, `parentUuid`, `isSidechain`, `timestamp` 필드가 있다(확인). msg id로는 `uuid` 앞 8자를 쓴다.
- 현재 세션 ID를 알려 주는 환경변수는 확인하지 못했다. cwd 디렉터리의 최신 파일에서 앵커 문구로 확정한다.

## Codex

- `~/.codex/state_5.sqlite`의 `threads` 테이블에 `id`, `rollout_path`, `cwd`, `first_user_message`, `updated_at_ms`, `agent_path`, `git_origin_url` 열이 있다(확인). 작성 시 실제 thread 행으로는 검증하지 못했다.
- 후보 조회: `sqlite3 -readonly ~/.codex/state_5.sqlite "select id, rollout_path from threads where cwd = '<cwd>' order by updated_at_ms desc limit 3"`. `rollout_path`가 가리키는 JSONL이 세션 원본이다 [추론]. rollout 파일 형식과 현재 thread ID 환경변수는 [추론]이므로 쓰기 전에 확인한다.
