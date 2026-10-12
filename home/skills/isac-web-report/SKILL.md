---
name: isac-web-report
description: Use when the user wants a result, report, proposal, comparison, review artifact, or UI preview viewable in their own browser instead of a file path, including "10.222.0.7로 들어가서 볼 수 있게", "웹으로 만들어", "브라우저로 볼 수 있게", "프리뷰 만들어", "비교해볼 수 있게 프리뷰". Not for deploying a product, publishing a public site, or GitHub publishing.
---

# Web Report

사용자가 자기 기기 브라우저로 열어 보고 피드백할 수 있는 페이지를 만들어 서빙한다. 파일 경로(`/tmp/...`, `file://`)나 채팅 본문 출력으로 대신하지 않는다.

## 서빙 주소 찾기

호스트 IP를 하드코딩하지 않는다. 아래 순서로 사용자 기기에서 닿는 VPN 주소를 찾는다.

1. `/var/run/wireguard-addresses`가 있으면 그 파일의 주소를 쓴다(nix-darwin `local.wireguard` 모듈이 실제로 올라온 터널 주소를 써 두는 파일). 줄이 여러 개면 사용자에게 어느 것인지 묻는다.
2. 파일이 없으면 실행 중 인터페이스에서 찾는다. Linux는 `ip -4 -o addr show`에서 `wg*`·`tailscale*` 인터페이스, macOS는 `ifconfig`에서 IPv4가 붙은 point-to-point `utun*` 인터페이스. Cloudflare WARP처럼 사용자 기기와 연결되지 않은 VPN은 제외한다.
3. 후보가 정확히 하나가 아니면 추측하지 말고 사용자에게 주소를 묻는다.

`0.0.0.0`이나 공인 인터페이스에 바인딩하지 않는다. 찾은 주소에만 바인딩한다.

## 서빙

- 페이지는 저장소 밖 디렉터리에 둔다. 정적 페이지는 `bunx serve -l tcp://<addr>:<port> <dir>` 또는 `python3 -m http.server <port> --bind <addr> --directory <dir>`로 띄운다. 제품 UI 프리뷰는 실제 앱의 개발 서버를 `<addr>`에 바인딩해 가짜 데이터로 띄운다.
- 사용자가 보는 동안 꺼지지 않도록 장기 서비스로 띄운다(OMP에서는 이름을 붙인 장기 실행 `bash` 서비스). 포트가 사용 중이면 다음 포트를 쓴다.
- 사용자에게는 `http://<addr>:<port>/`를 준다. 시크릿·토큰·개인 경로를 페이지에 넣지 않는다.

## 자체 검증

호스트는 대개 자기 utun·WireGuard 주소로 자기 자신에게 접속하지 못한다. 그 주소로 `curl`이 실패해도 서버 문제로 단정하지 않는다.

- 같은 디렉터리나 같은 앱을 `127.0.0.1`에 바인딩한 루프백 인스턴스를 하나 더 띄워, 그 주소로 `curl -sI` 200, 모든 내부 링크, 이미지 로드, 브라우저 서브에이전트 렌더링(데스크톱·모바일 폭)을 확인한다.
- VPN 주소 쪽은 `lsof -nP -iTCP:<port> -sTCP:LISTEN`으로 `<addr>:<port>`에서 리슨 중인지 확인한다.
- 루프백 인스턴스는 검증이 끝나면 내린다.

## 내용

- 결론과 요약을 먼저 두고 세부로 내려간다. 기능·동작 수준으로 설명하고, 코드 수준 세부는 요청받았을 때만 넣는다.
- 긴 문단 대신 다이어그램, 표, 전후 비교, 실측 수치 같은 시각화를 쓴다. 문구는 `writing-clearly-and-concisely`와 `humanizer`를 적용해 짧게 쓰고, 내용이 원래 영어가 아니면 한국어로 쓴다.
- 방향이 여럿이면 각각을 독립된 인터랙티브 프리뷰로 만들고, 기존 화면을 바꾸는 작업이면 현재 디자인도 비교 기준으로 함께 넣어 한 인덱스 페이지에서 오가며 비교하게 한다. 인터랙티브 프리뷰를 정적 목업 스크린샷으로 대신하지 않는다. UI 작업은 `impeccable`을 쓴다.

## 피드백과 정리

- 피드백을 받으면 같은 URL을 갱신하고, 사용자가 승인할 때까지 반복한다.
- 사용자가 보는 동안 서버를 유지한다. 작업 정리 단계에서 서버를 내리고 스크래치 파일을 지운다. 사용자가 남겨 달라고 하면 예외.
