# 바꿀 수 있는 기본값

에이전트 관례에서 온 기본값이다. 사용자 지시나 프로젝트 문서(`references/projects/<owner>__<repo>.md`)가 다르게 정하면 그쪽을 따른다. `[U]` 규칙과 전역 가드는 여기서 바꾸지 않는다.

## 리뷰어 관점 (PR 리뷰 프리셋)

변경이 크면 correctness, security, tests 관점 리뷰어를 나눠 병렬로 돌린다. 역할 분리, 구성 규모, 수정 → 재리뷰 루프와 GREEN 조건은 `multi-agent-consensus`, GitHub 쓰기 주체는 `github-publishing`을 따른다.

## claim 판정 어휘

PR 주장을 claim별로 판정할 때 `issue-validation`의 판정 토큰을 그대로 쓴다(정의는 그 스킬 소유).

- PR 설명의 주장에 근거가 없거나 사실과 다르면(예: 틀린 ABI 설명) 실행으로 반증됐으면 `NOT_REPRODUCED`, 가릴 수 없으면 `INCONCLUSIVE`로 판정하고 "PR claim unsupported" 메모를 붙인다. 별도 판정이 필요하면 `skill-correction`으로 `issue-validation`에 제안한다.
- 등급 척도(evidence grade)는 PR 리뷰에서 생략해도 된다.

## 게시

- 재리뷰는 새 리뷰 코멘트로 남기고 이전 finding의 Closed/Open을 첫 섹션에 둔다. 현재 head에 대한 리뷰 코멘트는 하나다.
- push한 수정 때문에 PR이 하는 일이 달라졌으면 PR 제목을 고친다(PRR-03).

## 사용자 보고 형식

- 한국어. PR별 판정을 결정 단위 표로 묶는다: `| 판정 | PR | 핵심 근거 |`.
- 표 아래에 main에 남은 문제(PRR-32), 검증 범위의 한계, 정리한 임시 자원을 적는다.
