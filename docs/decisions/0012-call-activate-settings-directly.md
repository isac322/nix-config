# 0012. `activateSettings` 를 직접 부른다

**결정** — `system.defaults` 를 쓴 뒤 macOS 에 다시 읽으라고 직접 말한다.

nix-darwin은 `system.defaults`의 plist를 쓰기만 하고 macOS에 다시 읽으라고 말하지
않는다. 그래서 키보드·트랙패드 설정이 파일에는 들어갔는데 다음 로그인까지 반영되지
않는다. `modules/keyboard.nix`가 activation 끝에 시스템 설정 앱이 하는 것과 같은
새로고침을 부른다. 사용자 도메인의 defaults라 사용자 권한으로 실행한다.
