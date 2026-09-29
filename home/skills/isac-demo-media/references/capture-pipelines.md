# Capture pipelines by product type

`SKILL.md`의 MED-12~MED-21을 제품 유형별로 구체화한다. 명령은 예시이며 저장소에 이미 있는 도구·규약이 우선한다. 모든 경로에 공통으로 적용한다.

- 실제 제품만 녹화한다(MED-01). 최신 기본 브랜치에서 빌드하고 촬영 SHA를 `NOTES.md`에 적는다(MED-02).
- 스크립트는 산출물 옆에 커밋한다(MED-12). 기본 배치(저장소 규약이 없을 때):

```
assets/media/
  capture/            # 세션 기동, 입력 스크립트, 녹화, 인코딩, 포스터 추출
    run.sh            # 전체 재생성 단일 진입점
    NOTES.md          # 명령, 도구 버전, 촬영 SHA, 알려진 한계
  background/         # 승인된 배경 + 생성 스크립트 + LICENSE/출처 (MED-09, MED-10)
  clips/<shot>.{webm,mp4,webp}
  stills/<shot>.png
```

- 새 환경을 만들기 전에 기존 인프라를 찾는다(MED-14): 오너의 IaC·홈 인프라 저장소에서 `/dev/dri`, 하드웨어 인코더 장치, GPU 노드, 컨테이너 장치 마운트를 쓰는 서비스(미디어 서버 등), self-hosted CI 러너, 원격 빌드 호스트를 검색한다.
- 본 촬영 전 길이를 아는 동작으로 실시간성을 검증하고(MED-15), 단계별 시간을 기록한다(MED-17). 실험마다 15–20분 시간 박스(MED-18).

## 1. Desktop GUI app

**목표:** 실제 앱을 실제 창 관리자·컴포지터 위에서, 스크립트 입력으로 녹화.

| 플랫폼 | 세션 | 입력 | 녹화 |
|---|---|---|---|
| Linux Wayland | 대상 데스크톱 컴포지터의 가상·헤드리스 모드, 또는 `weston --backend=headless`, `sway` headless, `cage` | 컴포지터 스크립팅 API, `ydotool`, 앱의 테스트 훅 | `wf-recorder`, 컴포지터 내장 녹화, PipeWire 스크린캐스트 |
| Linux X11 | `Xvfb`/`Xephyr` + 대상 데스크톱 셸 | `xdotool`, 하나의 연결로 press/move/release를 유지하는 작은 입력 스크립트 | `ffmpeg -f x11grab` |
| macOS | 실제 로그인 세션(전용 사용자 권장) | AppleScript/`osascript`, 앱의 UI 테스트 러너 | `screencapture -v`, ScreenCaptureKit 기반 도구 |
| Windows | 실제 세션 또는 VM | UI Automation, AutoHotkey | `ffmpeg -f gdigrab`, OBS CLI |

**절차**
1. 컨테이너(예: 배포 대상 배포판 이미지)에서 앱을 빌드하거나, 공개 패키지를 설치하는 별도 타깃을 둔다. 런타임 버전을 사용자가 쓰는 조합에 맞춘다.
2. 세션을 한 번 띄우고, 준비 신호(창 등장, D-Bus 이름, 로그 줄, 첫 프레임)를 기다린다. 고정 `sleep` 금지(MED-16).
3. 클립마다 상태를 초기화하고, 스크립트 입력으로 동작을 수행한다. 드래그처럼 연결 상태가 필요한 입력은 한 프로세스·한 연결에서 유지한다(연결이 끊기면 mousedown이 사라진다).
4. 무손실 중간 포맷(예: `-c:v utvideo` 또는 `-c:v ffv1`, `.mkv`)으로 녹화하고, 인코딩은 병렬로 돌린다.
5. 앱 아이콘·이름이 제품 것인지(개발용 기본 아이콘 아님) 확인한다.

**함정**
- 소프트웨어 렌더링(llvmpipe 등)은 CPU 병목으로 fps가 떨어진다. 목표 fps를 못 내면 하드웨어 GPU 경로를 찾는다(MED-14). 재생이 실제보다 덜 부드러우면 그렇게 보고한다.
- 시계 조작(`libfaketime` 등)으로 느린 환경을 보정하지 않는다. 일부 시계만 늦춰져 애니메이션이 빨라지거나 떨린다(MED-15).
- 헤드리스 세션은 테마·폰트·아이콘이 빠지기 쉽다. 스틸로 먼저 확인한다.

## 2. Web UI / web service

**목표:** 시드된 데모 데이터를 가진 실제 인스턴스를 브라우저 자동화로 녹화.

1. 로컬 또는 일회용 환경에 실제 서비스를 띄운다(`docker compose up` 등, dev 서버보다 프로덕션 빌드 권장). 데모 계정과 합성 데이터를 시드 스크립트로 넣는다(MED-25).
2. Playwright로 녹화한다.

```ts
const context = await browser.newContext({
  viewport: { width: 1280, height: 640 }, deviceScaleFactor: 2,
  recordVideo: { dir: 'capture/raw', size: { width: 2560, height: 1280 } },
  colorScheme: 'dark', reducedMotion: 'no-preference',
});
```

3. 네트워크 대기(`waitForLoadState('networkidle')`)나 특정 요소를 기다린다. 커서 움직임이 보여야 하면 보이는 커서 오버레이를 주입하되 제품 UI를 바꾸지 않는다.
4. Playwright 녹화 품질이 부족하면 헤드풀 브라우저를 가상 디스플레이에서 띄우고 GUI 절차(§1)로 녹화한다.
5. 스틸은 `page.screenshot({ fullPage: false })`로 표면 규격 크기에서 찍는다.

## 3. CLI / TUI

**목표:** 실제 바이너리를 실제 셸에서 실행한 터미널 녹화. 텍스트가 선명하고 재생성 가능해야 한다.

- **`vhs`** (기본): `.tape` 파일을 커밋하고 `vhs demo.tape`로 MP4/WebM/GIF를 동시에 만든다.

```
Output assets/media/clips/quickstart.mp4
Output assets/media/clips/quickstart.webm
Output assets/media/clips/quickstart.gif   # 영상이 안 되는 표면에만 (MED-06)
Set FontSize 22
Set Width 1600
Set Height 800
Set Theme "<brand-matched theme>"          # 배경 승인 대상 (MED-09)
Set TypingSpeed 40ms
Hide
Type "export PATH=$PWD/bin:$PATH && clear" Enter
Show
Type "mytool init demo" Sleep 300ms Enter
Wait /Created/                             # 고정 sleep 대신 출력 대기
Sleep 1.5s
```

- **`asciinema rec`** + **`agg`**: 사이트에 텍스트 선택 가능한 플레이어(asciinema-player)를 두거나 `.cast`를 보관할 때. `agg`로 GIF가 필요할 때만 파생.
- 실행 환경: 깨끗한 컨테이너에서 README의 설치 방법 그대로 설치한 뒤 녹화한다(설치 계약은 `isac-discovery-surfaces`가 소유). 프롬프트는 짧게(`$ `), 호스트명·사용자명·경로를 숨긴다.
- 실시간 검증: tape 안에 `sleep 3`처럼 길이를 아는 명령을 넣어 결과 길이를 잰다. `TypingSpeed`로 인한 인위적 지연은 따로 적는다.
- TUI: 터미널 크기를 고정하고, 색 테마를 브랜드 팔레트에 맞춘다. 256색/트루컬러 지원을 확인한다.

## 4. Library / SDK

**목표:** 동작을 보여 줄 UI가 없으므로 "실제로 실행되는 코드 + 실제 출력"을 보여 준다.

1. 예제는 저장소의 테스트되는 파일(예: `examples/quickstart.<ext>`, doctest, 예제 테스트)에서 가져온다. 카드용으로 따로 쓴 코드 금지.
2. 예제를 실행해 실제 출력을 캡처하고, 코드와 출력을 한 카드에 둔다.
3. 코드 스니펫 카드 렌더러: `freeze`(charmbracelet), `silicon`, `carbon-now-cli` 등. 폰트·테마는 브랜드 킷을 따르고, 렌더 스크립트를 커밋한다.

```
freeze examples/quickstart.py --theme <brand-theme> --window --padding 40 \
  --font.family "<brand mono>" -o assets/media/stills/quickstart-code.png
python examples/quickstart.py | freeze --language text -o assets/media/stills/quickstart-out.png
```

4. 움직임이 가치가 있으면(예: 스트리밍 출력, REPL) CLI 절차(§3)로 REPL 세션을 녹화한다.
5. 가능하면 실행 가능한 playground 링크(공식 playground, Codespaces/devcontainer)를 함께 둔다. 카드 이미지는 복사 가능한 코드 블록과 짝지어 쓴다(MED-07).

## 5. Kubernetes operator / controller

**목표:** 일회용 클러스터에서 실제 리소스를 적용하고 컨트롤러가 만든 상태 변화를 보여 준다.

1. `kind`/`k3d`로 클러스터를 만들고, 공개 설치 경로(OCI Helm chart 등)로 설치한다. 외부 계정·클라우드 자격증명이 필요한 경로는 데모용 격리 계정을 쓰고, 불가능하면 자격증명 없이 가능한 부분(`helm template`, dry-run, CRD 검증)만 보여 준다.
2. 터미널 녹화(§3)로 `kubectl apply -f examples/...` → `kubectl get <kind> -w` 또는 `kubectl wait --for=condition=Ready` → 결과 확인(예: `curl`로 라우팅 결과, PVC 바인딩, 생성된 하위 리소스)을 보여 준다. 고정 sleep 대신 `kubectl wait`.
3. 결과에 UI가 있으면(대시보드, 외부 서비스 콘솔) 브라우저 녹화(§2)로 같은 순간을 찍고, 터미널과 브라우저를 나란히 합성할 때도 두 소스 모두 실제 녹화여야 한다.
4. 네임스페이스·도메인·클러스터 이름은 합성 값(`demo`, `example.com`)을 쓴다(MED-25).
5. 아키텍처 다이어그램은 이 스킬이 아니라 브랜드·사이트 쪽 자산이다. 데모 미디어에 섞을 때는 "다이어그램"으로 표시한다.

## 6. MCP server / AI tool server

**목표:** 실제 클라이언트에서 도구가 호출되고, 그 결과로 실제 효과가 일어나는 것을 한 화면에서 보여 준다.

1. README의 설치 방법 그대로 실제 클라이언트(데스크톱 AI 클라이언트, CLI 에이전트, MCP Inspector)에 서버를 등록한다. 저장소에서 직접 실행하는 경로로 대체하지 않는다.
2. 녹화 대상은 두 부분이다: 클라이언트의 도구 호출·결과(대화 또는 Inspector 패널)와 그 도구가 바꾼 실제 대상(창 이동, 파일 생성, 클러스터 상태, 브라우저 페이지). 대상이 GUI면 §1, 웹이면 §2, 터미널이면 §3을 따른다.
3. 모델 응답은 비결정적이다. 프롬프트를 고정하고 여러 번 찍어 동작이 실제로 일어난 테이크를 고른다. 편집으로 응답을 꾸미지 않는다. 대기 시간이 길면 컷을 넣되 컷 위치를 캡션에 표시하거나 "배속" 표기를 붙인다.
4. API 키·계정명·대화 기록의 개인 정보가 보이지 않게 데모 전용 프로필을 쓴다.

## 7. 인코딩과 파생 (공통)

```
# WebM (VP9, 2-pass, 무음)
ffmpeg -y -i raw.mkv -an -c:v libvpx-vp9 -b:v 0 -crf 32 -row-mt 1 -pass 1 -f null /dev/null
ffmpeg -y -i raw.mkv -an -c:v libvpx-vp9 -b:v 0 -crf 32 -row-mt 1 -pass 2 clip.webm
# MP4 (H.264, 스트리밍 시작 빠르게)
ffmpeg -y -i raw.mkv -an -c:v libx264 -preset slow -crf 22 -pix_fmt yuv420p -movflags +faststart clip.mp4
# 고정 프레임레이트 강제
ffmpeg -i raw.mkv -vf fps=60 ...
# poster (첫 프레임 또는 대표 프레임, 표시 크기에 맞춰)
ffmpeg -y -ss 0 -i clip.mp4 -frames:v 1 -vf scale=1280:-1 -c:v libwebp -quality 85 clip.webp
# GIF (영상이 안 되는 표면만, MED-06)
ffmpeg -i clip.mp4 -vf "fps=15,scale=800:-1:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse" clip.gif
#   또는 gifski --fps 15 --width 800 -o clip.gif frames/*.png
# APNG
ffmpeg -i clip.mp4 -vf "fps=20,scale=800:-1" -plays 0 -f apng clip.png
```

- 예산을 넘으면 CRF 사다리(VP9 CRF 22→37, x264 CRF 16→28)를 내려가며 가장 높은 품질로 예산 안에 넣는다. 그래도 넘으면 억지로 넣지 말고 길이·해상도 선택지를 보고한다.
- 루프 클립은 첫 프레임과 끝 프레임을 맞춘다(같은 상태에서 시작·종료).
- 스틸 PNG는 `oxipng -o 4 --strip safe`로 무손실 압축한다.

## 8. 검수 명령 (공통)

```
# 프레임 pts와 간격 (CFR/드롭 확인)
ffprobe -v error -select_streams v:0 -show_entries frame=pts_time -of csv=p=0 clip.mp4
# 길이 검증 (MED-15): 움직임 시작·끝 프레임의 pts 차이를 계산
# 컨택트 시트 (MED-20): 30프레임마다 한 장, 4x3 타일
ffmpeg -i clip.mp4 -vf "select=not(mod(n\,30)),scale=480:-1,tile=4x3" -frames:v 1 sheet.png
# 시작/중간/끝 프레임
ffmpeg -ss 0 -i clip.mp4 -frames:v 1 start.png   # 중간·끝도 같은 방식
# 두 이미지 차이 (MED-23): 평균 픽셀 오차
magick compare -metric MAE baseline.png ours.png null:
```

- 컨택트 시트·프레임은 **직접 열어 본다**. 명령이 성공했다는 것만으로 동작이 찍혔다고 판단하지 않는다.
- 움직임 기능의 안정성 지표(MED-21)는 프레임에서 추적 대상의 위치를 추출하는 작은 스크립트(Python + Pillow/OpenCV)로 계산한다: 가장자리 jitter(px, 연속 프레임 간 비단조 변위), 방향 반전 수, 기대 대상과 실제 대상 일치율(예: 129/129), 프레임 간격 중앙값·p95(ms).
- 결과는 리뷰 페이지(MED-11)의 각 클립 옆에 표로 둔다.

## 9. 단계별 시간 표 (MED-17, MED-19)

| 단계 | 개선 전 | 개선 후 | 병목·조치 |
|---|---|---|---|
| 세션 기동 | | | 예: 클립마다 재기동 → 1회 기동 + 상태 초기화 |
| 촬영 | | | 예: 고정 sleep → 준비 신호 대기 |
| 인코딩 | | | 예: 직렬 → `xargs -P` 병렬 2-pass |
| 검수 | | | 예: 수동 → 컨택트 시트 자동 생성 |

시간 박스를 넘기면 이 표와 함께 멈추고 보고한다(MED-18).

## Sources

- charmbracelet/vhs — https://github.com/charmbracelet/vhs
- asciinema / agg — https://asciinema.org · https://github.com/asciinema/agg
- charmbracelet/freeze — https://github.com/charmbracelet/freeze · silicon — https://github.com/Aloxaf/silicon
- Playwright video recording — https://playwright.dev/docs/videos
- gifski — https://gif.ski · oxipng — https://github.com/shssoichiro/oxipng
- 조사된 외부 스킬(흡수만, 설치하지 않음): `b-open-io/prompts` `cli-demo-gif`(VHS tape → GIF), `oil-oil/beautify-github-readme`(GIF는 opt-in, 정적 대체 유지), `ParthJadhav/app-store-screenshots`(스토어 스크린샷 파이프라인).
