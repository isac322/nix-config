# 라벨 메커닉

`isac-github-publishing`의 GHP-14 세부 절차. **메커닉만** 소유한다.

- 이슈 라벨의 이름·description·색·배타성·부착 기준, 붙이지 않는 기본 라벨, 라벨과 코멘트의 정합: `isac-issue-triage` 스킬 소유.
- PR 리뷰 판정은 라벨이 아니라 리뷰 이벤트로 남긴다: `isac-pr-review` 스킬 소유.

## 절차

0. **권한** — 라벨 쓰기(부착·생성) 전에 권한을 확인한다: `gh api repos/<owner>/<repo> --jq .permissions`. 부착에는 triage, 생성에는 push 권한이 필요하다. 없으면 라벨 작업을 건너뛰고 코멘트 게시는 계속하며, 의도한 라벨을 최종 보고에 "not applied (no permission)"으로 나열한다. 라벨 쓰기가 권한 이유로 실패(403)하면 남은 라벨 작업을 멈추고 같은 방식으로 보고한다.
1. **조회** — 라벨 작업 전에 저장소 라벨을 확인한다. 읽기 전용이므로 초안 모드에서도 해서 매핑을 보고할 수 있다:
   `gh label list -R <owner>/<repo> --limit 200 --json name,description,color`
2. **의미 매핑** — 붙이려는 의미와 같은 기존 라벨이 있으면 그 라벨을 우선 쓴다(예: 저장소 고유의 needs-info 계열 라벨이 같은 의미를 이미 커버하면 그것을 사용). 매핑 결과는 최종 보고에 적는다. 매핑을 지속 기록하려면 사용자가 `isac-skill-correction`으로 교정한다.
3. **생성** — 게시 모드에서만, 그리고 같은 의미의 기존 라벨이 없을 때만, 소유 스킬이 정한 이름·영어 description·색으로 패밀리 네임스페이스(`repro:`, `triage:`) 라벨을 만든다:
   `gh label create <name> -R <owner>/<repo> --description "<English description>" --color <hex>`
   만든 라벨은 최종 보고에 나열한다.
4. **교체** — 상호배타 그룹(소유 스킬이 정의)은 하나를 붙일 때 같은 그룹의 다른 라벨을 한 번의 편집으로 함께 제거한다:
   `gh issue edit <N> -R <owner>/<repo> --add-label X --remove-label Y` (PR은 `gh pr edit`)

## 금지

- 기존 라벨의 rename·recolor·delete·description 변경(저장소 변경이며 타인의 결정).
- 네임스페이스 밖 신규 라벨 생성. GitHub 기본 라벨(`bug`, `enhancement`, `duplicate` 등)은 있으면 재사용하고 없으면 만들지 않는다.
- 호출 스킬이 정의한 전이·상호배타 교체 대상이 아닌 라벨의 제거. 그 밖의 라벨은 누가 붙였든 제거하지 않고, 필요하면 최종 보고에서 제안한다.
