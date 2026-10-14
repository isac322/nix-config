# brief 틀 (서브에이전트를 보낼 때 복사해 모든 칸을 채운다)

규칙은 E2V-50과 SKILL.md `## 경계`가 정한다. `{…}` 칸을 모두 채우고, 채울 수 없으면 보내지 않는다. 칸에는 경로, SHA, ID, 관점, 쓰기 경계 같은 값만 넣고 절차를 옮겨 적지 않는다. 절차는 "읽을 스킬" 칸의 owner 스킬과 규칙 ID가 정한다. 채운 brief는 scratch 파일로 남기고 경로를 ledger에 적는다.

## 공통 칸 (모든 역할)
- 역할: {role}
- 읽을 스킬: {skill} {rule_ids}
- 쓰기 경계: {write_paths | read-only}
- ledger: {ledger_path}
- 반환: {return_format} → {out_path}
- 만든 자원 반환: {created_resources_field} (종류·식별자·삭제 명령, E2V-45)

## 조사자 (수정 분기)
- 읽을 스킬: `isac-multi-agent-consensus` MAC-05, MAC-09, MAC-10, `isac-e2e-release` E2V-46
- 판정 질문·규칙 파일(E2V-23): {protocol_path} (sha256 {protocol_sha})
- 항목: {item_ids}
- 관점: {perspective}
- 결과 파일: {out_path}
- 2라운드 응답할 반박 파일(MAC-05): {rebuttal_path | 1라운드면 n/a}

## challenger
- 읽을 스킬: `isac-multi-agent-consensus` MAC-05, MAC-10, `isac-e2e-release` E2V-46
- 판정 질문·규칙 파일(E2V-23): {protocol_path} (sha256 {protocol_sha})
- 대상 조사 파일: {investigator_paths}
- 반박 파일: {out_path}

## 결정 작성자 (arbiter 또는 통합 조사자, 메인 아님)
- 읽을 스킬: `isac-multi-agent-consensus` MAC-11, MAC-12
- 조사·반박·응답 파일(MAC-05): {paths}
- 결정 파일: {decision_path} (머리에 `작성: <agent id>`, E2V-23)
- 필수 섹션(E2V-23): MAC-11 매트릭스(항목별 판정, 근거 위치, 판정 주체) / 규약 / slice(소유 파일, slice 사이 interface) / NEEDS-USER / 동작 변경 목록(E2V-47)

## 구현자
- 읽을 스킬: `isac-issue-to-pr` I2P-11, I2P-24, I2P-25, I2P-28
- 결정 파일: {decision_path}
- slice: {slice_id} / 소유 파일: {owned_files}
- worktree: {worktree} / 브랜치: {branch} (이 slice 전용, E2V-23)
- old-fail 대상 commit: {old_sha}
- 환경 능력 사실: {env_facts} (E2V-25)
- suite 실패 분류: {classification_path | 첫 라운드 n/a} (E2V-25)

## 리뷰어
- 읽을 스킬: `isac-multi-agent-consensus` MAC-16, MAC-17, MAC-19, MAC-20
- 리뷰 대상 commit(E2V-29): {head_sha} (working tree가 아님)
- 확인할 사실(E2V-29): {facts}
- 손 편집(E2V-29): {hand_edits | 없음}
- old-fail/new-pass 표(MAC-17): {old_fail_table_path}

## release PR 리뷰어 (E2V-34)
- 읽을 스킬: `isac-github-publishing`
- 저장소 노트 규칙 경로: {notes_rule_path}
- PR head: {head_sha}
- 대조: 버전 일관성 / changelog 연결 / 버전 주장 대 공개 인터페이스 delta / PR 본문 / 노트
