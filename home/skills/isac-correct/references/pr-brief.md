# PR 서브에이전트 위임문

사용자가 제안을 승인한 뒤에만 띄운다. 승인된 변경 요지, 분석 결과의 `diff_draft`, `case_draft`, `recipe`, 원인 규칙 ID를 `<…>`에 채운다. PR 생성·머지 조건은 전역 `pull-request-creation`, `pull-request-merge-authorization` 가드가 소유하므로 여기서 다시 쓰지 않는다.

## 위임문

```text
# Goal
승인된 스킬 교정 1건을 isac322/nix-config에 PR로 올린다.

# Write boundary
쓰기 허용 범위는 다음뿐이다: $TMPDIR 아래 스크래치 clone, 원격 브랜치 skill-fix/<skill>-<slug>
하나, PR 하나. /etc/nix-darwin 작업 트리와 .git, 배포된 ~/.omp·~/.claude·~/.codex·~/.agents
파일, memory는 건드리지 않는다. 머지, darwin-rebuild switch, 강제 push를 하지 않는다.

# Approved change
- 대상 스킬: <name>   원인 규칙: <ID 또는 섹션 제목>   분류: <class>
- 변경 요지: <before → after 또는 "규칙 유지, 케이스 기록">   적용 조건: <applicability 또는 없음>
- 정본 기준: <canonical_ref: main 또는 열린 PR head 브랜치>
- diff 초안: <diff_draft>
- 케이스: <case_draft>
- 재실행 레시피: <recipe 또는 없음>

# Steps
1. 먼저 instruction-architect 스킬을 읽고 따른다. 이어서 isac-correct 스킬의
   references/cases-format.md를 읽는다.
2. clone:
   dir="${TMPDIR:-/tmp}/isac-correct/<CASE-ID>"
   git clone --reference-if-able /etc/nix-darwin --dissociate \
     git@github.com:isac322/nix-config.git "$dir"
   cd "$dir" && git switch -c skill-fix/<skill>-<slug> origin/<canonical_ref>
   (--reference-if-able은 객체를 읽기만 하고 --dissociate가 참조를 끊는다.)
   canonical_ref가 main이 아니면(스킬이 아직 열린 PR에만 있음) PR base도 그 브랜치로 하고
   본문 Problem 첫 줄에 기반 PR을 적는다.
3. diff 초안을 origin/<canonical_ref> 기준으로 다시 확인하고 최소 수정만 적용한다. 반증된 문구만
   고치고 무관한 규칙은 건드리지 않는다. 새 규칙 ID는 SKILL.md와 규칙 이력을 통틀어
   최대 번호 + 1이다. 변경 요지가 "규칙 유지, 케이스 기록"이면 규칙 문구는 고치지 않는다.
4. owner 스킬의 references/cases.md에 케이스를 추가한다. 파일이 없으면(의존 스킬 첫 교정)
   cases-format의 세 섹션으로 만든다. [U] 규칙을 추가·변경했으면 출처 색인 행을 갱신하고,
   폐기·대체·의미 변경이면 규칙 이력 행을 추가한다.
5. 새 파일 스테이징 등 편집 절차는 instruction-architect를 따른다.
6. 검증(실행한 것만 기록한다):
   - 변경된 .nix 파일이 있으면 그 파일에만 nixfmt --check. 없으면 "변경된 .nix 없음".
   - nix flake check --no-update-lock-file
   - darwin 호스트: darwin-rebuild build --flake ".#$(scutil --get LocalHostName)"
     NixOS 호스트: nixos-rebuild build --flake ".#$(hostname)"   (switch 금지)
   - 빌드 closure에서 배포될 스킬 파일에 새 문구가 있는지 확인한다. 스킬 디렉터리는
     스킬 이름으로 끝나는 store 경로로 복사된다. 예:
     nix-store -qR ./result | grep -- '-<name>$' 로 찾은 경로의 SKILL.md(또는 바꾼
     references 파일)에서 새 문구를 grep한다. 찾지 못하면 closure를 검색해 찾고 그 방법을
     기록한다.
   - 재실행 레시피가 있으면 수정 후 문구에 대해 다시 적용해 기대 결과를 확인한다.
   실패하면 고칠 수 있는 범위에서 고치고, 못 고치면 PR을 만들지 않고 보고한다.
7. 자체 점검(단일 규칙 수정 기준): 의미 중복이 생기지 않았는지, 다른 스킬 파일 경로를
   참조하지 않는지, references 링크가 실제 파일을 가리키는지, description 트리거가
   다른 스킬과 충돌하지 않는지, cases-format의 공개 위생을 지켰는지 확인한다.
8. 서명 커밋: git commit -S -m "fix(skills): <skill> <rule-id> <English summary>"
   git log -1 --format=%G? 가 G가 아니면 중단하고 보고한다. 무서명 커밋으로 대체하지 않는다.
9. git push -u origin skill-fix/<skill>-<slug>
   gh pr create --repo isac322/nix-config --base <canonical_ref> --head skill-fix/<skill>-<slug> \
     --title "<영어 제목>" --body-file <아래 템플릿으로 쓴 파일>
   본문 문체는 isac-publish, writing-clearly-and-concisely, humanizer 스킬을 따른다.
10. 스크래치 clone을 지운다. 절차를 어겼거나 금지된 동작을 실수로 했으면 숨기지 않고 보고한다.

# Output
PR URL, head SHA, 브랜치, 실행한 검증 명령과 결과, 변경 파일 목록과 파일별 한 줄 요지.
```

## PR 본문 템플릿 (영어)

```markdown
## Problem
<What the user observed and expected, in one or two sentences. No raw quotes.>

## Direction
<What changes in which skill, stated as behavior.>

## Rationale
<Why this change removes the cause with the smallest side effect. Summarize the user's
correction in English and name the rule that caused it: `<skill>` <RULE-ID>.>

## Source case
<CASE-YYYYMMDD-slug>, <harness> session <8 chars>, message <id>.

## Changed rules
- <RULE-ID>: <before gist> → <after gist>
- <RULE-ID>: added / retired (moved to rule history)

## Verification
- `<command>`: <result>
- Not run: <check> (<reason>)
```

- 언어와 공개 위생은 `isac-publish`를 따른다.
- Verification에는 실제로 실행한 명령과 결과만 쓴다. 실행하지 못한 검사는 이유와 함께 "Not run"으로 적는다.

## 편집 기본값 (바꿀 수 있음)

- 분할된 스킬 사이에는 명시적 handoff 계약을 두고, 교정이 트리거 description을 바꾸면 다른 스킬과의 충돌을 검사한다.
- frontmatter는 `name`과 `description`만 둔다. 필드를 추가하면 로딩 동작이 바뀔 수 있다.
- 스킬 로딩·discovery 동작은 가정하지 말고 확인한다. 실패가 조용한지 드러나는지 구분한다.
- 스킬에는 실제로 존재하는 명령, 타깃, 경로만 쓰고, 알려진 위험은 사실대로 적는다.
- 빌드 산출물은 정확히 pin하고, 문서와 스킬은 pin된 위치를 읽게 한다.
- 검증 상태는 정직하게 적는다(미검증, live-blocked, 측정값). 지향 설계가 아니라 실제 구현에 맞춘다.
- line-anchored 편집이 파일을 망가뜨리면 덧대지 말고 한 번에 다시 쓴다. 부분 손상이 의심되면 불일치를 모두 열거한 뒤 복구하고, 실수로 지운 내용은 `origin/main`에서 복원한다.
