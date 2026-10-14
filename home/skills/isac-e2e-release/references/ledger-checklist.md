# 단계별 증거 체크리스트 (0단계에 ledger 끝으로 복사한다)

<!--
복사: 0단계에서 이 파일을 `cat <이 파일> >> <ledger>`로 붙인다. 손으로 옮겨 적지 않는다.
칸: 산출물 경로(파일, run URL, SHA, msg id) 또는 `n/a: <이유>`.
블록 면제: 모드 범위 밖이거나 run이 들어가지 않은 블록(예: 수정 없는 릴리스의 F와 G-REQA, analysis·qa 모드의 3단계 이후)은 블록 제목 바로 아래 한 줄 `n/a: <이유>`로 닫는다. 그 한 줄이 블록의 모든 칸을 채운 것으로 친다. 면제한 블록의 G 줄은 쓰지 않는다. 면제는 게이트 통과가 아니다.
G 줄: `G-<이름>: <통과 시각> / <대상 SHA·산출물> / <판정 주체>`. 이 줄이 게이트 통과 주장이다. 빈 칸이 있는 블록의 G 줄은 쓰지 않는다.
재진입: 수정 PR이 머지되면 G-VERSION과 G-GO 블록을 다시 붙여 새 SHA로 채운다. 이전 블록은 지우지 않는다.
행 추가: 각 행은 owner 규칙 ID(또는 state-machine.md §3 게이트 행)를 단다. 행을 추가하는 조건은 `isac-skill-correction`의 학습 규약을 따른다.
복사·G 줄·빈 칸·재개 규칙은 E2V-51이 소유한다. 조건과 방법은 SKILL.md 규칙과 state-machine.md §3 게이트 행이 소유한다. 이 파일은 어느 산출물이 그 규칙을 증명하는지만 적는다.
-->

## G-INTAKE
- [ ] E2V-02 모드·권한 지도(ledger 머리 위치): ____
- [ ] E2V-04·state-machine §3 G-INTAKE 읽은 저장소 하네스·릴리스·노트 지침 파일 목록(없으면 "없음"과 찾아본 경로): ____
- [ ] state-machine §3 G-INTAKE: 기준 브랜치 열린 PR·진행 중 변경 조회 출력: ____
- [ ] E2V-06·E2V-07·state-machine §3 G-INTAKE 단위별 직전 릴리스, baseline 상태, 후보 SHA: ____
- [ ] E2V-08 대상 환경 probe 결과(닿지 않으면 미검증 범위 행): ____
- G-INTAKE: ____

## G-VERSION
- [ ] E2V-10 직전 릴리스 이후 변경 목록: ____
- [ ] E2V-11·E2V-46 버전 근거 표와 반론·리뷰 판정 경로: ____
- G-VERSION: ____

## G-GO
- [ ] E2V-15·state-machine §3 G-GO 레인별 행(ran / not_applicable / blocked, NO-GO여도 전부): ____
- [ ] E2V-15 CI 실행 범위 대 저장소 테스트 단위: workflow의 테스트 명령 인용, 저장소 테스트 단위 목록(러너가 나누는 단위), CI 밖 단위마다 E2V-26 환경의 실행 결과(SHA) 또는 `blocked` 사유: ____
- [ ] E2V-21 커버리지 표(분모 = 표면 목록): ____
- [ ] 결과별 판정 경로: NO-GO면 blocker마다 발견자 아닌 에이전트의 재현과 결함 판정(E2V-19, state-machine §6.7). GO면 regression·new-bug 가설마다 challenger 판정(E2V-21). 그 밖의 finding은 목록에 "미검증"으로 남는다: ____
- [ ] E2V-22 GO/NO-GO 보고(보내기 전 확인 통과): ____
- G-GO: ____

## F 수정 분기 (첫 두 행은 첫 조사자 파견 전에)
- [ ] E2V-23 finding 목록(모든 항목 "미검증"): ____
- [ ] E2V-23 판정 질문·강제 규칙·판정 집합 고정 파일 경로 + sha256: ____
- [ ] MAC-05·MAC-10 조사·반박 파일과 반박 파일마다 원 조사자의 2라운드 응답 파일(구성과 응답자는 MAC-05): ____
- [ ] E2V-46·MAC-11 합의되지 않은 쟁점의 arbiter 판정 경로: ____
- [ ] E2V-23 결정 파일 경로 + 작성 agent id(메인 아님): ____
- [ ] E2V-46 결정 파일 판정 행마다 판정 주체 2인 이상(MAC-05): ____
- [ ] E2V-24 NEEDS-USER 항목마다 질문 msg id·보낸 시각과 HOLD를 보낸 slice: ____
- [ ] E2V-23·E2V-47 동작 변경 목록 경로: ____
- [ ] E2V-23 slice → worktree·브랜치 표(slice마다 다른 worktree 경로와 브랜치)와 통합 브랜치에 합친 commit SHA(slice가 하나면 n/a): ____
- [ ] E2V-25 통합 head suite 실행(SHA·로그)과 실패마다 분류(테스트 산출물 / 제품 결함)·진단 증거 경로(구현자에게 넘기기 전에 채운다): ____
- [ ] E2V-50 채운 brief 파일 목록(briefs.md 틀, 읽을 스킬 칸 포함): ____
- [ ] E2V-27·I2P-25 old-fail/new-pass 표(테스트 × 이전 코드 × 새 head)와 통과 control 이름: ____
- [ ] E2V-29·MAC-20 리뷰 대상 commit SHA와 라운드별 판정 경로: ____

## G-REQA
- [ ] E2V-28 최종 head SHA의 baseline suite, 계약 표면 A/B, 문서대로 설치 행: ____
- G-REQA: ____

## G-MERGE (PR마다 복사)
- [ ] E2V-02 근거 지시 msg id: ____
- [ ] MAC-16·MAC-20 리뷰 루프 종료 기록(리뷰된 head SHA): ____
- [ ] E2V-30 그 head의 required context 전부 보고(ruleset 조회 출력)와 전역 pull-request-merge 가드 처분: ____
- G-MERGE <PR>: ____

## G-CUT
- [ ] E2V-12 버전 재도출 기준 commit: ____
- [ ] E2V-35 승인 기록 또는 위임 근거 지시(프로필 Overrides가 질문을 요구하면 질문 msg id·보낸 시각과 답): ____
- [ ] E2V-04·E2V-05 적용한 릴리스 절차 출처: 저장소 하네스 파일 경로, 없으면 G-INTAKE 조회 기록 위치와 직전 릴리스에서 도출한 절차의 ledger 위치(bot 소유 PR이면 `n/a: E2V-13`): ____
- [ ] E2V-32 release PR diff 모양 대조: ____
- [ ] E2V-34 release PR head SHA의 독립 리뷰 판정 경로(노트, PR 본문, 버전 주장): ____
- G-CUT: ____

## G-PUB
- [ ] E2V-37 tree 일치 assertion과 후보..게시 commit 목록: ____
- [ ] E2V-38 게시 단계별 명령과 exit 기록(`&&`·`;`·파이프로 묶지 않음): ____
- [ ] E2V-39·E2V-40 채널별 공개 확인과 릴리스 객체: ____
- G-PUB: ____

## G-POST
- [ ] E2V-41 머지 SHA마다 기본 브랜치 CI 결과·분류: ____
- [ ] E2V-42 공개 채널에서 문서대로 깨끗한 설치와 주요 변경·수정 smoke 기록: ____
- [ ] E2V-45 cleanup ledger 처분: 삭제 신호 msg id와 행별 exit, 또는 최종 보고에 적은 남은 행과 삭제 명령: ____
- [ ] E2V-44 최종 보고(보내기 전 확인 통과): ____
- G-POST: ____

## 늦게 나온 관찰 (모든 단계, 관찰마다 복사)
- [ ] E2V-46·MAC-05 사소 구성: 조사자 1 + challenger 1 판정 경로(한 에이전트의 판정은 판정이 아니다): ____
