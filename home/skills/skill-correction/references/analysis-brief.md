# 분석 서브에이전트 위임문

메인은 아래 위임문의 `<…>`를 채워 읽기 전용 서브에이전트 하나를 띄우고, 결과는 outputSchema로만 받는다. 세션이나 후보 스킬이 여럿이면 세션별로 나눠 병렬로 띄운다(SKC-08). 메인은 `diff_draft`와 `case_draft`를 사용자에게 그대로 보이지 않고, 승인 후 PR 서브에이전트에 넘긴다.

## 위임문

```text
# Goal
사용자가 지적한 스킬 동작 문제의 원인 규칙을 찾아 최소 수정안을 만든다.

# Write boundary
읽기 전용이다. 어떤 파일, 저장소, git 메타데이터, memory, GitHub에도 쓰지 않는다.
fetch·checkout도 하지 않는다. 필요한 계산은 스크래치 없이 메모리 안에서 한다.

# Inputs
- 세션: <session-sources 산출물 JSON. sessions 배열에 현재 세션과 사용자가 지목한 이전 세션을 담는다>
- 사용자 지적 요지: <현재 대화에서 사용자가 말한 내용 1–3줄>
- 후보 스킬: <레지스트리 이름 1–3개>
- 대상 저장소 확인 결과: <owner/repo, visibility 또는 unknown>

# Steps
1. 세션 JSONL 전체를 코드로 순회한다. model_usage, custom, mode_change record는 버린다.
   사용자 메시지(<system-notice>/<system-reminder> 블록 제거), goal-mode-context,
   ask 답변(toolResult toolName=ask), assistant 텍스트와 toolCall 이름·인자 요약,
   toolResult 앞부분을 시간순으로 모은다. 잘린 출력은 서브에이전트 디렉터리의
   <n>.<tool>.log를 본다. 필요한 서브에이전트 transcript도 같은 방식으로 순회한다.
   앞뒤·검색 샘플만 읽는 것은 실패다.
2. 앵커(사용자 지적)를 찾고, 직전 에이전트 행동, 그때 적용된 스킬·규칙 문구
   (read skill://… 결과나 위임문에 인용된 문구), 같은 지적의 이전 반복을 추출한다.
   "이전에 말했다"는 교정이면 받은 이전 세션들과 owner 스킬 cases.md 출처 색인에서
   원래 지시를 찾는다. 찾지 못하면 missing_info에 적고 missing으로 단정하지 않는다.
   지적이 나온 상황과 대상(작업 종류, 저장소 소유권·가시성, 산출물 종류, 위험도)을
   context에 적는다(SKC-34).
3. 근거 가중치: 사용자 지시·교정·ask 답변 > 승인된 제안 > 에이전트 관례.
   에이전트의 위임문 제약, 사후 설명, 자기 보고를 사용자 근거로 쓰지 않는다.
4. 정본을 읽는다(쓰기 없이):
   gh api -H "Accept: application/vnd.github.raw" \
     "repos/isac322/nix-config/contents/home/skills/<name>/<path>?ref=<ref>"
   ref는 main이다. SKILL.md, references/cases.md(있으면), references/projects/<owner>__<repo>.md(있으면)를
   읽고, skill-correction의 references/cases-format.md도 읽는다. 스킬이 main에 없어 404면
   그 스킬 경로를 바꾸는 열린 PR head(5단계)를 ref로 쓰고 canonical_ref에 적는다.
   세션 당시 문구와 정본 문구를 비교해 이미 고쳐졌으면 status=already-fixed.
5. 열린 교정 PR을 확인한다:
   gh pr list --repo isac322/nix-config --state open --json number,title,headRefName,url,files \
     --jq '.[] | select((.headRefName|startswith("skill-fix/")) or any(.files[].path; startswith("home/skills/<name>/")))'
   같은 규칙을 다루는 PR이나 같은 케이스가 있으면 duplicates에 적고, 새 케이스 대신
   재발 기록 + not-followed 처리 안을 낸다.
6. 원인 스킬, 규칙 ID(의존 스킬은 섹션 제목), 원인 분류를 정한다. 규칙 부재면 가장 가까운
   단계 스킬에 추가하는 안을 낸다. 맞는 규칙이 처음 안 지켜진 not-followed면 규칙은 두고
   change_kind=case-only로 케이스만 낸다. 원인이 레지스트리 밖(전역 segment, 기타 스킬)이면
   status=out-of-family로 소유 자산을 적는다.
   발화 하나를 그대로 규칙으로 만들지 않는다. 규칙 안에는 context에서 도출한 적용 조건을
   applicability_ko로 적고, 그 상황에만 해당하는 일회성 지시면 change_kind=case-only로 한다.
7. 반영 위치(destination)를 skill-correction SKC-11 순서대로 분류한다. 먼저 맞는 것을 고른다.
   - memory: 특정 저장소·대상에만 적용되는 사용자 작업 방식 선호. 레지스트리 규칙이 다루는
     행동이라도 그 저장소 한정 예외면 여기다. 커밋되는 파일에 넣지 않는다.
   - skill: 레지스트리 규칙이 다루는 행동을 저장소와 무관하게 바꾸는 교정(질문·승인 방식이라도
     레지스트리 규칙이 다루면 여기), 또는 저장소 무관한 새 패밀리 행동 규칙.
   - out-of-family: 레지스트리 규칙이 다루지 않는 전역 정책 의미나 레지스트리 밖 스킬.
   - repo-harness: 그 저장소의 모든 에이전트가 따를 공유 규칙·암묵지, 비공개 저장소 사실.
   - project-reference: 공개 저장소 자체의 사실·기본값.
   [U] 규칙을 완화·삭제·의미 변경하면 overrides_user_rule=true로 하고 cases.md 출처 색인의
   원 근거를 user_rule_source에 적는다.
8. 최소 수정 diff를 만든다. 반증된 문구만 고치고, 새 규칙 ID는 cases-format 채번 규칙을
   따른다. 케이스 블록 초안을 cases-format 스키마로 쓰고 공개 위생 검사를 한다
   (비밀값, 호스트, 비공개 저장소명, 로컬 절대경로, 사용자 원문 제거).
9. 근거가 부족하면 추측하지 말고 status=insufficient-evidence와 필요한 정보를 적는다.

# Output
outputSchema에 맞는 JSON만 반환한다. 산문 설명을 붙이지 않는다.
```

## outputSchema

```json
{
  "type": "object",
  "additionalProperties": false,
  "required": ["status", "problem_ko", "evidence", "context", "destination", "change_kind", "overrides_user_rule"],
  "properties": {
    "status": {"enum": ["proposal", "already-fixed", "out-of-family", "insufficient-evidence"]},
    "problem_ko": {"type": "string", "description": "사용자에게 보인 현상, 기대 vs 실제. 2문장 이내"},
    "evidence": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["session", "msg_id", "kind", "gist"],
        "properties": {
          "session": {"type": "string", "description": "세션 ID 앞 8자"},
          "msg_id": {"type": "string", "description": "record id 또는 ASK@시각"},
          "kind": {"enum": ["user", "ask-answer", "goal", "agent-action", "skill-text"]},
          "gist": {"type": "string", "description": "요지 1줄, 원문 인용 금지"}
        }
      }
    },
    "context": {
      "type": "object",
      "required": ["task", "repo", "artifact", "risk"],
      "properties": {
        "task": {"type": "string", "description": "작업 종류(예: 이슈 판독, PR 리뷰)"},
        "repo": {"type": "string", "description": "저장소 소유권·가시성(예: 사용자 소유 공개, 타인 소유)"},
        "artifact": {"type": "string", "description": "산출물 종류(예: 공개 댓글, 코드, 라벨)"},
        "risk": {"type": "string", "description": "위험도와 이유 1줄"}
      }
    },
    "cause": {
      "type": "object",
      "properties": {
        "skill": {"type": "string"},
        "rule_id": {"type": "string", "description": "예: TRI-07, 의존 스킬은 섹션 제목, 없으면 new"},
        "class": {"enum": ["wrong", "loose", "missing", "conflict", "not-followed"]},
        "current_text": {"type": "string", "description": "현재 정본 문구 요지 1줄"}
      }
    },
    "change_kind": {"enum": ["rule-change", "case-only"], "description": "case-only: 첫 not-followed 또는 일회성 지시"},
    "change_ko": {"type": "string", "description": "before → after 요지 2문장 이내. case-only면 '규칙 유지, 케이스 기록'"},
    "applicability_ko": {"type": "string", "description": "rule-change일 때 규칙의 적용 조건(상황·대상 경계) 1–2문장"},
    "canonical_ref": {"type": "string", "description": "정본을 읽은 ref. main 또는 열린 PR head 브랜치"},
    "destination": {"enum": ["skill", "project-reference", "repo-harness", "memory", "out-of-family"]},
    "out_of_family_owner": {"type": "string"},
    "overrides_user_rule": {"type": "boolean"},
    "user_rule_source": {"type": "string"},
    "side_effects_ko": {"type": "string", "description": "의존 스킬이면 패밀리 밖 영향 명시. 1문장"},
    "diff_draft": {"type": "string", "description": "canonical_ref 기준 unified diff. case-only면 케이스 항목만"},
    "case_draft": {"type": "string", "description": "cases-format 스키마의 케이스 블록. destination이 skill 또는 project-reference일 때만"},
    "recipe": {"type": "string", "description": "원 사례 검증을 다시 돌리는 절차. 없으면 빈 문자열"},
    "duplicates": {"type": "array", "items": {"type": "string"}},
    "missing_info": {"type": "string"}
  }
}
```

## 결과 처리 (메인)

- `proposal`: `SKILL.md`의 제안 형식(SKC-15)으로 사용자에게 보인다.
- `already-fixed`: 고쳐진 커밋·문구 요지와 "아직 배포되지 않았을 수 있음(머지 후 switch 필요)"을 보고한다.
- `out-of-family`: 소유 자산과 instruction-architect 경로를 안내하고 끝낸다.
- `insufficient-evidence`: 부족한 정보만 한 번 묻는다(질문 형식은 `decision-brief`).
