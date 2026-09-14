# Scrapnote

Scrapnote는 짧게 포착한 생각과 이미지를 로컬 Markdown 파일로 보관하고,
나중에 Note와 Timeline으로 엮는 데스크톱 앱입니다. Flutter와 Forui로
구현하며 macOS를 첫 번째 실행 환경으로 삼습니다.

## 현재 구현 범위

- Braun/Dieter Rams에서 영감을 받은 최소한의 warm-paper 편집기 shell
- 로고와 텍스트 라벨을 덜어낸 48px 아이콘 activity rail
- Vault 미설정 시 폴더 선택부터 시작하는 단계형 onboarding
- 전체 높이 Inbox, 최근 문서 탭, 자동 줄바꿈 위치에 맞춰 줄 번호를 표시하는 공통 편집기
- 수정 상태 점 표시, `⌘/Ctrl+S` 저장, `⌘/Ctrl+N` 새 문서,
  `⌘/Ctrl+W` 현재 Scrap/Note 닫기
- 탭이나 창을 닫을 때 Save / Don't Save / Cancel 확인
- 비정상 종료 뒤 저장하지 않은 편집 내용을 복구하는 로컬 draft snapshot
- drag & drop과 macOS 이미지 `⌘/Ctrl+V` 붙여넣기로 커서·드롭 위치에 이미지 블록 삽입
- 이미지를 번호 하나의 줄로 표시하고 좌·중앙·우 정렬, 100%·50%·33%·20% 크기와 삭제 지원
- Inbox 항목 우클릭 → Delete scrap: 열린 탭을 닫고 문서를 `.trash/scraps`로 이동
- 사용자가 선택한 로컬 Vault에 YAML front matter + Markdown 원본 저장
- 첨부 파일 SHA-256 중복 제거와 상대 경로 링크
- 최초 저장 당시 GPS, 날짜·UTC offset·timezone 메타데이터와 지도 drawer
- 수정일 기준으로 정렬되는 Inbox
- 작성일 기준 Timeline과 작성 순서대로 위치 지점을 연결하는 지도
- 가상 Notes 루트 없이 폴더부터 표시하는 트리와 문서 탭
- 폴더·Note를 다른 폴더로 드래그 이동, 우클릭 삭제 (폴더 삭제는 내부 문서 포함)
- 선택한 폴더 안에 새 Note·하위 폴더 생성
- Notes 우측의 상시 Scrap 목록, 사용 중인 Scrap 강조 표시와 마우스 오버 미리보기
- Scrap을 현재 커서에 한 줄 객체로 삽입하고 저장 후 합쳐진 문서 미리보기 표시

이미지는 Markdown 본문 안에 저장되며, 정렬과 크기는 이미지 링크의
`"left:50"`, `"center:100"` 같은 title로 유지합니다. 이미지와 Scrap 객체의
드래그 순서 변경 기능은 없습니다.

Note에 넣은 Scrap은 삽입 당시 내용의 복사본입니다. 편집 중에는 한 줄 객체로
보이며 저장하면 전체 문서 미리보기가 표시됩니다. `Edit`을 누르면 다시 객체로
편집할 수 있습니다. 저장 파일에는 전체 내용과 출처 구분용 HTML 주석이 함께
남아, 일반 Markdown 뷰어에서도 하나의 문서로 읽을 수 있습니다.

Notes 트리의 빈 공간이나 `NOTES` 헤더를 누르면 최상위를 선택합니다. 폴더나
문서를 빈 공간으로 드롭하면 최상위로 이동합니다. 삭제한 폴더·문서는 Vault의
`.trash/notes`에 보관되고 공유 이미지 파일은 유지됩니다.

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

## Note 제목과 Scrap 사용

Note의 Title 입력란에서 본문과 별도로 제목을 정합니다. 제목은 Markdown의
front matter에 저장되며, 기존 Note는 본문 첫 줄을 제목으로 표시합니다.
Note에 넣은 Scrap은 Inbox와 다른 Note의 삽입 목록에서 제외됩니다.
작성 중인 Note도 포함하며, 삽입을 취소하거나 Note를 삭제하면 다시 사용할 수 있습니다.
Scrap 객체의 연필 버튼은 해당 Note에 들어간 사본을 수정합니다. Apply로 적용하고
Note를 저장하면 변경이 보관됩니다. 원본 Scrap은 바뀌지 않습니다.

새 이미지는 가운데 정렬·50% 크기로 들어갑니다. 이미지별 정렬과
100% / 50% / 33% / 20% 크기를 바꿀 수 있습니다.
Finder에서 복사한 이미지 파일은 파일 아이콘 대신 원본을 읽습니다.
이전에 아이콘으로 저장된 이미지는 원본을 다시 붙여넣어야 합니다.

편집기의 볼드 버튼 또는 ⌘B / Ctrl+B는 선택한 글에 Markdown 볼드 표시를
적용하거나 해제합니다. 선택 없이 실행하면 커서 위치에 볼드 입력 구간을 만듭니다.
Note의 저장된 문서 화면에서는 볼드로 표시됩니다.

macOS 클립보드 원본 선택 회귀 테스트:
```bash
swiftc macos/Runner/ClipboardImageReader.swift test/native/clipboard_image_reader_test.swift -o /tmp/scrapnote-clipboard-test
/tmp/scrapnote-clipboard-test
```
