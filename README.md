# Scrapnote

Scrapnote는 짧게 포착한 생각과 이미지를 로컬 Markdown 파일로 보관하고,
나중에 Note와 Timeline으로 엮는 데스크톱 앱입니다. Flutter와 Forui로
구현하며 macOS를 첫 번째 실행 환경으로 삼습니다.

## 현재 구현 범위

- Braun/Dieter Rams에서 영감을 받은 최소한의 warm-paper 편집기 shell
- 로고와 텍스트 라벨을 덜어낸 48px 아이콘 activity rail
- Vault 미설정 시 폴더 선택부터 시작하는 단계형 onboarding
- 전체 높이 Inbox, 최근 문서 탭, 줄 번호가 있는 Markdown Scrap 편집기
- 수정 상태 점 표시, `⌘/Ctrl+S` 저장, `⌘/Ctrl+N` 새 문서,
  `⌘/Ctrl+W` 현재 Scrap/Note 닫기
- 탭이나 창을 닫을 때 Save / Don't Save / Cancel 확인
- 비정상 종료 뒤 저장하지 않은 편집 내용을 복구하는 로컬 draft snapshot
- drag & drop과 macOS 이미지 `⌘/Ctrl+V` 붙여넣기로 커서·드롭 위치에 이미지 블록 삽입
- 본문 이미지의 드래그 이동, 위·아래 이동, 좌·중앙·우 정렬과 삭제
- Inbox 항목 우클릭 → Delete scrap: 열린 탭을 닫고 문서를 `.trash/scraps`로 이동
- 사용자가 선택한 로컬 Vault에 YAML front matter + Markdown 원본 저장
- 첨부 파일 SHA-256 중복 제거와 상대 경로 링크
- 최초 저장 당시 GPS, 날짜·UTC offset·timezone 메타데이터와 지도 drawer
- 수정일 기준으로 정렬되는 Inbox
- 작성일 기준 Timeline과 작성 순서대로 위치 지점을 연결하는 지도
- Notes의 접고 펼치는 폴더·하위 폴더·문서 트리와 문서 탭
- 선택한 폴더 안에 새 Note·하위 폴더 생성
- Notes의 `Insert Scrap`으로 저장된 Scrap 검색 후 본문과 이미지를 현재 커서에 복사

이미지는 Markdown 본문 안에 저장되며, 정렬은 이미지 링크의 `"left"`,
`"center"`, `"right"` title로 유지합니다. Scrap을 Note에 삽입하면 현재 내용의
복사본이 들어가므로 원본을 나중에 수정해도 Note 내용은 바뀌지 않습니다.
Scrap 삭제 시 공유 이미지 파일은 보존됩니다.

지도는 위치가 기록된 Scrap만 연결합니다. 선은 작성 순서를 나타내며 실제 도로
이동 경로를 계산하지 않습니다. 배경 지도에는 인터넷 연결이 필요합니다.
위치 수동 보정과 Windows·웹의 이미지 클립보드 읽기는 아직 지원하지 않습니다.

## 로컬 Vault 구조

```text
Vault/
├── scraps/
│   └── 20260904-081500000--<uuid>.md
├── notes/
│   ├── 20260904-091500000--<uuid>.md
│   └── <folder>/
│       └── 20260904-101500000--<uuid>.md
└── assets/
    └── sha256/
        └── ab/
            └── <sha256>.png
```

Markdown 파일이 원본 데이터입니다. 앱 밖에서 파일을 열고 수정하거나 백업할
수 있습니다. macOS에서는 security-scoped bookmark로 선택한 Vault 접근 권한을
다음 실행에도 복원합니다.

## 실행과 검증

```bash
flutter pub get
flutter run -d macos
flutter analyze
flutter test
flutter build macos
```

Forui는 Flutter 3.44 / Dart 3.12와 맞는 `0.25.x`를 유지합니다.
