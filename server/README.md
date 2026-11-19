# Scrapnote API

Node 22 / Fastify 5와 PostgreSQL 16을 사용하는 개인 Vault 동기화 서버다.
문서·정산 JSON은 PostgreSQL에 원본 바이트로 저장하고, 사진은 기존 Zipline v4.8.3에
보관한다. API는 HTTPS 프록시 뒤의 8080 포트에서 실행한다.

## 설정과 실행

`.env.example`을 참고해 Coolify 환경 변수를 설정한다. DB 비밀번호는 URL에 안전한
난수 문자열을 사용한다. `ZIPLINE_TOKEN`은 전용 일반 사용자 토큰이다.
`ZIPLINE_PASSWORD_KEY`는 32자 이상의 영구 난수 키이며 사진 복구에 반드시 필요하다.

```sh
npm ci
npm test
# DATABASE_URL, INITIAL_EMAIL/PASSWORD, ZIPLINE_* 설정 후
npm start
```

서버가 시작되면 schema.sql을 적용하고 최초 계정을 만든다. 이미 있는 이메일의
비밀번호는 재시작하거나 INITIAL_PASSWORD를 바꿔도 덮어쓰지 않는다. 공개 회원가입은
없다. 비밀번호는 scrypt로, 세션 토큰은 SHA-256으로 저장한다. 세션은 30일 뒤 만료된다.

## Coolify 배포

현재 서버 소스는 `/home/ubuntu/scrapnote-api`, 서비스는
`e7aoqro0dfik9uxwx9lxnwfq`이다. `compose.yaml`을 Coolify Compose 서비스로 등록했다.
API는 서버에서 빌드한 이미지를 사용하므로 코드를 갱신한 뒤 반드시 이미지를 다시
빌드하고 Coolify에서 서비스를 재시작한다. 기존 이미지 태그를 재시작만 하면 소스는
갱신되지 않는다.

```sh
cd /home/ubuntu/scrapnote-api
docker build -t scrapnote-api:1.0.0 .
# Coolify → Scrapnote → scrapnote → Restart
```

PostgreSQL 볼륨을 제거하는 `down -v`는 실행하지 않는다. API 외부 포트와 DB 포트는
열지 않으며 Coolify 프록시만 API로 연결한다. `/healthz`는 DB 연결도 확인한다.
사진 업로드는 Zipline 요청 제한의 Retry-After를 따라 기다릴 수 있다.

## 백업과 복구

함께 보관할 항목은 PostgreSQL dump, Zipline의 DB와 업로드 저장소,
`ZIPLINE_PASSWORD_KEY`·전용 토큰 등 운영 환경 변수, 로컬 Vault 전체 사본이다.
PostgreSQL dump만으로는 사진을 복원할 수 없다. Zipline 설정에서 업로드 파일의
자동 삭제·만료·재압축을 활성화하지 않는다.

현재 PostgreSQL 컨테이너를 백업하는 예:

```sh
umask 077
docker exec database-e7aoqro0dfik9uxwx9lxnwfq \
  pg_dump -U scrapnote -d scrapnote -Fc > scrapnote.dump
```

복구 시 먼저 별도 PostgreSQL과 Zipline 저장소에 백업을 복원하고 같은 사진 비밀번호
생성 키를 설정한다. `pg_restore --no-owner`로 새 Scrapnote DB에 복원한 뒤 API를
시작한다. 계정과 manifest, 모든 blob의 SHA-256이 일치하는지 확인하고 기기를 연결한다.
원래 API 주소/사용자 ID를 유지하지 않으면 기존 Vault identity도 별도 이전해야 한다.

## API와 검증

- `POST /v1/auth/login`, `POST /v1/auth/logout`, `GET /v1/auth/me`
- `GET /v1/manifest`, `PUT /v1/manifest` (`expected_revision`, `entries`)
- `PUT /v1/blobs/:sha256?path=...`, `GET /v1/blobs/:sha256`

로그인과 상태 확인 외에는 Bearer 세션이 필요하다. 파일 한도는 25 MiB, manifest는
4 MiB다. 소유자 범위와 해시를 검사하며 파일 업로드가 끝난 후에만 manifest를 원자적으로
커밋한다. 같은 버전의 동시 커밋은 한 요청만 성공한다. 삭제된 파일의 이전 blob은
즉시 물리 삭제하지 않으며 현재는 별도 자동 정리 작업을 실행하지 않는다.

```sh
npm test
# 테스트 전용 PostgreSQL 또는 임의 스키마 생성이 가능한 DB에서:
TEST_DATABASE_URL=... node --test test/postgres.test.js
```

PostgreSQL 테스트는 무작위 스키마를 만들고 종료 시 제거한다. 운영 사용자 행은
변경하지 않는다. 실제 데이터 이전은 `../tool/migration/local_import.py`를 사용한다.

## GitHub Actions 자동 배포 설정

`.github/workflows/deploy-server.yml`은 `main`에 서버 코드가 push되거나 수동 실행되면
서버 테스트를 통과한 뒤 SSH로 API 이미지를 빌드하고 API 컨테이너만 교체한다.
DB 볼륨은 건드리지 않는다. API가 정상 상태가 되지 않으면 이전 이미지로 복구를 시도한다.
배포가 끝나도 Flutter 앱은 별도로 빌드·설치해야 한다.

활성화하려면 저장소에 워크플로와 `server/`를 커밋하고 다음 GitHub Actions secrets를
설정해야 한다. 서버에는 해당 공개 키를 등록해야 한다.

- `SCRAPNOTE_DEPLOY_SSH_KEY`: 서버 `ubuntu` 계정에 접근하는 전용 SSH 개인 키.
- `SCRAPNOTE_DEPLOY_KNOWN_HOSTS`: 서버 호스트 키를 신뢰할 수 있는 경로로 확인한
  `known_hosts` 항목. 검증되지 않은 `ssh-keyscan` 출력만을 신뢰하지 않는다.

이 계정은 Docker와 sudo를 제어할 수 있으므로 개인 키 접근 권한과 `main` 브랜치에 push할 수
있는 사람을 제한한다. 워크플로는 Coolify가 생성한 서비스 디렉터리에 의존하므로 서비스
ID가 바뀌면 경로를 수정해야 한다. 이 설정은 파일 추가만으로 활성화되지 않으며, 키와
secrets 설정 및 GitHub push가 필요하다.
