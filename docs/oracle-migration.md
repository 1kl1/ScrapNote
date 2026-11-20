# Oracle Cloud · Coolify · Zipline 이전

## 구성과 기준 데이터

Supabase SDK·Auth·Storage 연결을 제거하고 다음 구성으로 전환했다.

```text
Flutter → HTTPS Scrapnote API → PostgreSQL (문서·정산·계정·동기화 버전)
                             → Zipline (사진 원본)
```

원본은 운영 PC의 `/Users/1kl1/Desktop/scraps`이다. Supabase의 과거 데이터는
읽거나 병합하지 않는다. `supabase/migrations/`와 `supabase_export.py`는 과거
구성/내보내기 참고 자료이며 현재 서버 운영이나 이번 이전에는 사용하지 않는다.
Supabase 클라우드 프로젝트 자체의 삭제는 이번 앱 연결 전환과 별개다.

| 항목 | 저장 방식 |
| --- | --- |
| Scrap, Note, GPS, 삽입 출처 | 기존 경로와 Markdown 바이트 그대로 PostgreSQL |
| 정산 기록·표시 설정 | 기존 JSON 바이트 그대로 PostgreSQL |
| 이미지 | SHA-256과 Zipline 파일 ID를 PostgreSQL에 매핑 |
| 파일 목록·빈 폴더 | 버전이 있는 JSON manifest |
| 로그인 | 서버 등록 계정, scrypt 비밀번호 해시, 30일 세션 |

원본 문서의 이미지 링크를 바꾸지 않는다. 앱은 인증된 API에서 사진을 받아
기존 로컬 파일 방식으로 사용한다. 현재 Zipline 사진은 개별 비밀번호 없이 공개 URL로
열람할 수 있다. 압축·만료·조회 횟수 제한 없이 원본 해시를 검증한다.

## 배포

- API: <https://scrapnote.134.185.114.149.sslip.io>
- 상태 확인: `/healthz`
- Coolify: <https://coolify.gdgoc-ku.com>, `Scrapnote / production / scrapnote`
- Oracle: `134.185.114.149`, 서버 소스 `/home/ubuntu/scrapnote-api`
- 기존 Zipline: <https://kl-playground-files.duckdns.org>, 전용 계정 `scrapnote-sync`
- PostgreSQL은 Scrapnote 전용 영구 볼륨이며 외부 포트를 열지 않는다.
- 배포에 사용한 임시 Coolify 토큰은 폐기했고, API 활성화 설정은 기존 비활성 상태로 복원했다.

DNS 설정이 필요 없는 SSLIP 주소를 사용한다. 고정 도메인으로 변경하면 Coolify의
HTTPS 주소와 앱의 `SCRAPNOTE_API_URL`, Vault identity도 검증해서 함께 이전해야 한다.
[서버 실행·백업 안내](../server/README.md)에 재배포와 복구 절차를 기록했다.

## 로컬 백업과 이전 도구

Git에서 제외되는 `.migration/`에 다음 운영 파일을 보관한다. 비밀번호를 공개 문서나
명령행 인자로 복사하지 않는다.

- `app-account.json`: 앱 서버 주소와 로그인 계정
- `runtime-env.json`: DB 비밀번호, Zipline 토큰·사진 비밀번호 생성 키
- `zipline-service-account.json`: 전용 Zipline 계정 복구 정보
- `local-backup-path.txt`: 이전 전 Vault 전체 사본의 위치
- `local-migration-report.json`: 원본 목록, 파일별 해시, 개수, 바이트 수, 검증 시각
- `local-migration-report.previous-state.json`: 이전 전 동기화 연결 상태

이번 백업은 `.migration/local-vault-backup-20261119T021054Z`에 있다.
휴지통과 로컬 상태도 백업에 포함한다. 새 앱이 기존 사진 메타데이터를 읽어
7개 문서에 `photo_metadata_read`를 추가했으며 본문은 동일하다. 이전에는 이 최신
로컬 메타데이터까지 포함한다. 서버 동기화 대상은 scraps, notes, assets,
expenses 및 정산 설정이며 휴지통과 복구 초안은 업로드하지 않는다.

빈 API 계정으로 가져오는 명령:

```sh
python3 tool/migration/local_import.py \
  --config .migration/app-account.json \
  --vault /Users/1kl1/Desktop/scraps \
  --report .migration/local-migration-report.json --bind
```

이 도구는 모든 파일을 업로드하고 서버에서 다시 내려받아 SHA-256을 비교한다.
로컬 원본과 서버 목록이 검증 도중 바뀌지 않았는지 재확인한 다음에만 `.sync/state.json`을
새 서버/계정에 연결한다. 이전 상태는 따로 보관한다. 원본 콘텐츠를 삭제하지 않는다.

실패한 업로드는 같은 데이터로 재시도할 수 있다. 이미 저장한 해시는 재사용한다.
대상 서버가 다른 데이터로 채워져 있으면 덮어쓰기를 거절한다. 검증 보고서가 이미
있으면 보존하므로 재검증에는 새 보고서 경로를 사용한다. 사진 저장소의 요청 제한은
응답의 대기 시간을 따른다.

## 완료 기록 (2026-11-19 UTC)

로컬 기준 Scrap 45개, Note 2개, 정산 202개와 표시 설정 1개, 사진 50개,
Note 폴더 1개를 이전했다. 고유 파일 300개(569,350,466 bytes)의 원본 해시를
모두 검증하고 기존 PC Vault를 새 API 계정에 연결했다.

외부 다운로드 속도가 느려 전체 검증은 서버에서 API를 통해 원본을 내려받고,
SSH로 받은 검증 결과를 현재 로컬 파일 해시·크기와 대조했다. 외부 HTTPS에서는
별도로 작은 파일의 로그인·문서·이미지 다운로드와 Flutter 동기화 검사를 통과했고,
macOS 릴리스 앱에서도 로그인과 실제 동기화 완료를 확인했다. 외부에서 21.5 MB
사진을 받는 검사는 5분 제한을 초과했다. 서버 내부 원본 검증은 모두 통과했으나
새 기기에서 사진 전체를 받는 첫 동기화는 현재 외부 전송 속도 때문에 오래 걸릴 수 있다.
기존 Zipline에 직접 접속한 다운로드도 느려 API 중계에만 한정된 현상은 아니었다.
이전 당시 사진 50개 모두 비밀번호 보호, 만료 없음, 조회 횟수 제한 없음 상태였으며
익명 사진 원본 요청이 차단되는 것을 확인했다. 이후 블로그에서 기존 사진 URL을
사용하기 위해 파일별 비밀번호를 해제하고 새 업로드도 비밀번호 없이 저장하도록 변경했다.
사진 파일을 복사하지 않으며 기존 파일 ID와 URL을 유지한다. 노트 본문은 여전히
로컬 이미지 경로를 사용하므로 블로그 발행 시 공개 URL로 변환하는 처리는 별도로 필요하다.
변경 후 사진 50개 모두 인증 없는 공개 URL에서 내려받아 원본 SHA-256과 크기를 검증했다.
기존 파일 ID·URL·개수도 동일하며, 갱신한 운영 API의 인증된 사진 다운로드와 기존 사진
재사용을 확인했다. 변경 전후 검증 보고서는 `.migration/zipline-public-photos-*.json`에 보관한다.

PostgreSQL의 초기 백업은 서버의
`/home/ubuntu/scrapnote-backups/migration-20261119.dump`와 로컬의
`.migration/postgres-migration-20261119.dump`에 있다. 자동 정기 백업은 별도 설정 대상이다.

## 기기 전환

PC는 전체 검증이 끝난 기존 Vault를 사용한다. 새 앱에서 위 계정으로 로그인한다.
기존 Supabase 세션은 새 API 세션으로 재사용하지 않는다.

Android/iOS는 기존 `vault`가 Supabase에 묶여 있으면 이를 보존하고 `vault-oracle`을
사용한다. 새 계정으로 동기화해 PC 기준 데이터를 받는다. 기존 모바일의 오래된
파일을 새 서버에 덮어쓰지 않는다. 앱 삭제 전에는 필요한 로컬 전용 파일을 백업한다.

## 검증

```sh
python3 -m unittest discover -s tool/migration -p 'test_*.py'
npm test --prefix server
flutter analyze
flutter test
flutter build macos --debug
flutter build apk --debug
```

서버 테스트에는 인증·계정 격리·로그아웃·해시 검증·Zipline 보호·요청 제한 재시도와
실제 PostgreSQL에서의 동시 커밋/롤백 검사가 있다. 실제 데이터 이전의 최종 결과는
`local-migration-report.json`을 기준으로 확인한다. 물리 Android/폴더블 기기의
화면과 양방향 동기화는 기기에서 추가 확인한다.
