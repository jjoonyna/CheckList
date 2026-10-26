# CheckList

사내 공용 3단계 체크리스트 MVP입니다. React 화면과 Spring Boot API를 하나의 JAR로 실행하며 웹 접속 포트는 **8383**입니다.

## 구현 기능

- 이메일·이름·비밀번호 직접 가입, JWT 인증과 Redis 세션·로그아웃.
- 최상위 → 세부 항목 → 하위 세부 항목. 모든 단계에 제목·상세내용·마감일·담당자·완료 상태.
- 로그인한 사용자는 전체 열람. 최상위 지정 편집자만 해당 트리의 추가·수정·완료·댓글 작성 가능.
- 긴급·높음·보통·낮음·고려 5단계 우선순위 등록·수정·표시. 기존 항목과 새 항목의 기본값은 보통입니다.
- 계층을 유지하고 최상위끼리·같은 부모의 형제끼리 우선순위→마감일 순 정렬. 기한이 없으면 마지막입니다.
- 전체/본인 담당, 완료/미완료, 기간, 검색 필터. 기본 이번 달, 최대 1력년. 마감일이 없으면 생성일 기준.
- 중요 원댓글을 상단에 고정·해제하고 답글도 묶여 함께 이동합니다. 중요/일반 그룹과 답글은 각각 최신순입니다.
- 각 단계의 댓글·한 단계 답글과 댓글 또는 답글 하나당 첨부 합계 최대 500000000바이트, 인증 후 다운로드.
- GitHub 이슈를 조회하고 선택해서 가져오기. 공개 저장소는 토큰 없이 이용 가능하며 PAT는 요청에만 사용합니다.

## 구성

| 영역 | 구성 |
|---|---|
| 프론트 | React 19 · TypeScript 5.9 · Vite 7 |
| 백엔드 | Java 21 · Spring Boot 3.5 · JPA · QueryDSL 5.1 |
| 저장소 | PostgreSQL 18.6 · Flyway, Redis 세션, 로컬 첨부 파일 |
| 배포 | 프론트 포함 JAR, JRE·PostgreSQL 선택 설치를 포함한 Windows EXE |

`frontend/`는 `pages`, `layouts`, `components`, `store`, `types`, `styles`로 나눕니다. `backend/src/main/java/com/checklist/domain/` 아래 `auth`, `checklist`, `comment`, `github`에 실제 controller/dto/entity/repository/service 파일을 배치합니다. 해당 역할이 없는 빈 패키지는 만들지 않습니다. 공통 코드는 `global/`에 둡니다.

## 현재 PC에서 실행

저장소 루트에서 PowerShell로 실행합니다. 기존에 설치한 사용자 전용 PostgreSQL·Redis와 `backend/config/application-local.properties`를 사용합니다.

```powershell
.\scripts\run-local.ps1 -Java21 'C:\Java\jdk\bin\java.exe'
```

[http://localhost:8383](http://localhost:8383)에 접속해 직접 가입합니다. 앱 종료는 실행 터미널의 Ctrl+C입니다. DB·Redis 상태 확인/중지는 별도 명령입니다.

```powershell
.\scripts\local-runtime.ps1 -Action status
.\scripts\local-runtime.ps1 -Action stop
```

`run-local.ps1 -Build`는 실행 전 JAR을 다시 생성합니다. Java 관련 JAVA_HOME/PATH 및 시스템·사용자 환경설정을 변경하지 않습니다. 비밀번호와 JWT 비밀키가 있는 로컬 설정은 저장소와 설치 파일에 포함하지 않습니다.

## 개발과 테스트

Java 21과 Node.js 20.19 이상 또는 22.12 이상, PostgreSQL·Redis가 필요합니다. 백엔드 디렉터리에서 다음 명령으로 테스트와 통합 빌드를 수행합니다. Windows 한글 경로를 위해 실행별 인코딩 옵션을 지정합니다.

```powershell
cd backend
& 'C:\Java\jdk\bin\java.exe' '-Dorg.gradle.java.home=C:\Java\jdk' '-Dorg.gradle.jvmargs=-Dfile.encoding=COMPAT' -classpath gradle/wrapper/gradle-wrapper.jar org.gradle.wrapper.GradleWrapperMain test bootJar --no-daemon --console=plain --max-workers=1
```

실제 PostgreSQL 18.6 임시 인스턴스와 테스트 전용 Redis를 사용합니다. Windows의 Redis 테스트 바이너리는 현재 PC의 사용자 전용 설치를 기본으로 찾으며, 다른 PC에서는 `-Dtest.redis.executable=<redis-server 실행파일>`을 지정합니다. 테스트 완료 시 해당 임시 서버를 종료합니다.

프론트 디렉터리에서:

```powershell
npm ci
npm run test -- --run
npm run dev
```

개발 화면은 5173이며 `/api`를 8383으로 전달합니다. 실행 중인 로컬 백엔드와 함께 사용합니다. `npm run build`는 TypeScript 검사와 정적 빌드를 수행합니다.

## 다른 PC와 Windows 설치

```powershell
.\scripts\package-deploy.ps1 -Java21 'C:\Java\jdk\bin\java.exe' -CompileInstaller
```

출력은 `dist/checklist-setup-0.0.4.exe`입니다. 빌드에는 Node.js와 도구 다운로드 네트워크가 필요합니다. 설치한 앱 실행에는 번들 JRE를 사용합니다.

설치 프로그램은 관리자 권한을 요구합니다. PostgreSQL 18.6과 Redis 8.10.2 Windows 커뮤니티 빌드가 EXE에 포함되어 있으며, 설치 마법사에서 각각 **기존 서버 사용 / 이 PC에 새로 설치**를 선택합니다. PostgreSQL만 설치된 PC에서는 PostgreSQL은 기존 사용, Redis는 신규 설치를 선택하면 됩니다. WSL·Docker·별도 Java 설치는 필요하지 않습니다.

설치 폴더를 선택하면 **신규 설치 / 업데이트**를 자동으로 안내합니다. 기존 완료 설정이 있으면 업데이트로 진행하며 연결 설정 입력을 건너뛰고 기존 설정·DB·첨부를 유지합니다. 완료 설정이 없으면 신규 설치로 진행하고, 실패한 설치의 임시 설정이 있으면 복원합니다. 제거 후 설정을 보존한 폴더에 다시 설치하는 경우에도 기존 환경을 재사용합니다.

신규 설치 순서는 **설치 폴더 → 신규 설치 안내 → PostgreSQL 설치 방식·연결 설정 → Redis 설치 방식·연결 설정 → 파일 복사 → DB/Redis 준비 및 연결 확인 → CheckList 서비스 시작**입니다. 업데이트는 **설치 폴더 → 업데이트 안내 → 기존 서비스 중단 → 프로그램 갱신 → 기존 설정으로 서비스 재시작** 순서입니다. PowerShell 콘솔은 표시하지 않으며 진행 상황과 오류를 설치 마법사에 표시합니다.

기존 서버는 설치 PC의 실행 프로세스 수신 포트와 등록 서비스 설정을 자동 탐지하고 후보를 제공합니다. 선택한 주소·포트는 수정할 수 있으며 탐지되지 않거나 다른 PC의 서버를 사용하면 직접 입력합니다. 계정·비밀번호는 자동으로 읽지 않습니다. 기존 PostgreSQL 계정과 비밀번호, Redis 비밀번호(사용하는 경우)를 입력합니다.

신규 설치의 기본값은 로컬주소 `127.0.0.1`, PostgreSQL 포트 `5432`·DB/계정 `checklist`, Redis 포트 `6379`입니다. 비밀번호는 설치마다 임의 생성하며 수정하거나 ‘비밀번호 표시’로 확인할 수 있습니다. 기존 프로그램이 해당 포트를 쓰면 다른 포트로 변경해야 합니다. DB가 없으면 입력 계정의 권한으로만 생성하며, 기존 서버 사용 시 해당 계정에 필요한 DB 접근·생성 권한이 있어야 합니다.

신규 PostgreSQL은 `CheckListPostgreSQL`, Redis는 `CheckListRedis`, 앱은 `CheckList` Windows 서비스로 등록합니다. 이 설치가 소유한 서비스만 관리하며 다른 경로의 같은 이름 서비스를 덮어쓰지 않습니다. Redis는 로컬 주소에만 바인딩하고 비밀번호와 데이터 저장을 설정합니다. 다른 PC의 사용자는 앱 웹 주소에 접속하며 번들 Redis에 직접 연결할 필요가 없습니다.

설정은 설치 폴더의 `config/`, 첨부와 번들 DB는 `data/`, 로그는 `logs/`에 둡니다. 설정 파일은 관리자/SYSTEM으로 접근을 제한합니다. 실패한 초기 설정은 보호된 `config/setup-pending.json`에 보존하고 재실행 시 마법사에 복원합니다. 입력 파일은 성공·실패 후 제거하고, DB·Redis 연결 확인이 성공해야 완료 설정으로 승격합니다. Windows 설치된 앱에서 CheckList 제거 또는 설치 폴더의 `unins000.exe`를 실행하면 앱을 제거합니다. PostgreSQL 프로그램·서비스·데이터와 앱 설정·업무·첨부 데이터는 남깁니다. CheckList 전용 Redis가 있으면 삭제 여부를 묻고, 삭제를 선택하면 Redis 프로그램·서비스·저장 데이터·설정을 함께 제거합니다. 아니요를 선택하면 Redis를 그대로 남기며 취소하면 제거를 시작하지 않습니다. 외부 Redis 서버는 제거하지 않습니다. 기존 완료 설정이 있으면 재설치 시 입력 화면을 건너뛰고 기존 설정을 유지합니다. 구성요소 고지는 설치 폴더의 `THIRD-PARTY-NOTICES.txt`, `licenses/`, JRE의 `legal/`을 확인합니다.

## 확인 범위와 남은 항목

2026-10-22 기준 백엔드 35개, 프론트 8개 테스트와 실제 브라우저 기본 9개·추가 10개 흐름이 통과했습니다. 실제 GitHub 공개 이슈 조회·가져오기, DB/Redis 연결, 첨부 다운로드를 확인했고 통합 JAR과 EXE를 생성했습니다.

2026-10-26에는 기본 `Program Files/CheckList` 경로에서 PostgreSQL 초기화 권한 오류를 수정하고, 실패한 설치 재시도·PostgreSQL/Redis/앱 서비스 등록과 시작·Redis 인증·앱 응답을 실제 검증했습니다. 이후 분리된 시험 설치·실제 Windows 서비스에서 구버전 갱신, Redis 보존·삭제·취소, 다른 설치 서비스 보호, 실행 파일 누락 복구, 앱·전용 Redis 종료까지 6개 시나리오를 검증했습니다. Docker Compose 실행, 비공개 GitHub PAT, 500MB 실파일 전송은 이번 검증 범위에 포함하지 않았습니다. 첨부 크기 경계는 서버 규칙 테스트로 확인했습니다.

편집자에서 제외할 계정이 하위 항목 담당자로 남아 있으면 서버가 변경을 거절하고 편집 창에 안내합니다. 기간·완료 상태에 관계없이 해당 트리를 검사하며 담당자를 먼저 변경하거나 미지정해야 합니다. 담당자를 자동 해제하지 않습니다.

최신 JAR과 EXE에는 담당자 변경 후 편집자 제외 정책, 5단계 우선순위, 계층 정렬, 중요 원댓글과 답글 묶음 이동까지 반영했습니다. 로컬 설정·DB·첨부는 배포 파일에 포함하지 않습니다.

MVP에는 메일 인증, 계층 이동·삭제, 댓글 수정·삭제, GitHub 지속 동기화를 제공하지 않습니다. Donetick은 구조·동작 분석 참고 대상으로 사용했으며 이 프로젝트는 Java/React로 별도 구현했습니다. 프로젝트 계획과 AI 분석·인수인계 자료는 저장소 밖에서 관리합니다.
## 자동 검증·빌드·릴리즈

main 대상 PR을 열거나 갱신하면 프론트·백엔드·릴리즈 규칙 테스트와 통합 JAR 빌드를 실행합니다. **PR이 main에 실제 통합된 뒤**에는 통합 결과 SHA로 다시 검증하고 Windows 설치 EXE를 생성한 다음 GitHub Releases에 게시합니다. PR을 통합하지 않고 닫으면 실행하지 않습니다.

현재 버전은 `0.0.4`, 태그는 `v.0.0.4`입니다. `CHANGELOG.md`의 `## [0.0.4]` 절 본문을 릴리즈 설명으로 사용하고 `checklist-0.0.4.jar`와 `checklist-setup-0.0.4.exe`를 첨부합니다. 릴리즈 게시에는 해당 작업에만 `contents: write` 권한을 부여하며 나머지는 읽기 권한을 사용합니다.

다음 릴리즈는 프론트 `package.json`·`package-lock.json`의 앱 버전, 백엔드 `build.gradle`, 설치 `checklist.iss`, `package-deploy.ps1`의 기본 버전을 함께 올리고 CHANGELOG에 같은 버전의 내용을 추가합니다. `node scripts/release.mjs`로 버전과 노트를 확인하고 `node --test scripts/release.test.mjs`로 규칙을 검증합니다. 버전 불일치나 누락·중복·빈 노트는 빌드를 실패시킵니다. 같은 버전이 이미 게시됐다면 릴리즈는 유지하고 새 결과물은 Actions에서 확인합니다. 기존 태그나 미완료 초안은 덮어쓰지 않고 실패시켜 수동 확인하도록 합니다.

Actions 결과물 `checklist-jar`, `checklist-windows-installer`, `checklist-test-reports`의 보관 기간은 14일이며 Releases에 게시한 JAR·EXE도 다운로드할 수 있습니다. 실제 원격 설치 파일 생성·릴리즈 게시 성공은 main 통합 후 Actions에서 확인해야 합니다. 서비스 설치나 운영 서버 배포는 자동 수행하지 않습니다. CI의 Java/Node 환경 준비는 GitHub 러너에서만 수행하며 사용자 PC의 Java 환경설정은 변경하지 않습니다.

이슈를 연결하는 PR에는 `Closes #1`과 같은 문구를 사용합니다. 저장소 기본 설정에 따라 main 통합 시 연결 이슈가 자동 종료됩니다. [GitHub 이슈 연결 안내](https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/linking-a-pull-request-to-an-issue), [릴리즈 생성 안내](https://cli.github.com/manual/gh_release_create)를 참고합니다.

## 설치 파일 생성 진단

패키징은 단계 시작·완료·실패와 경과 시간을 출력합니다. 다운로드 주소·캐시 사용·파일 크기·SHA-256 검증 결과도 확인할 수 있습니다. 외부 프로세스는 15초마다 PID·CPU 시간·경과 시간을 출력하며 표준 출력과 오류를 별도 파일에 보관합니다.

로그 위치는 `tools-cache/deploy/logs/<실행별 폴더>/`입니다. `package.log`는 전체 기록, `*.stdout.log`·`*.stderr.log`는 프로세스별 출력이며 Inno 도구를 새로 준비할 때 `inno-setup.log`도 생성됩니다. Actions는 실패·취소 시에도 `checklist-packaging-logs` 업로드를 시도합니다. 전체 작업 강제 종료 등으로 후속 단계가 실행되지 않으면 GitHub 실행 화면의 로그를 확인합니다.

다운로드는 연결 20초·전송 시도당 180초·재시도 1회·전체 프로세스 390초 제한을 적용합니다. Java 확인 30초, PostgreSQL XZ·TAR 추출 각각 180초, Inno 도구 설치 120초, EXE 컴파일 600초, 로컬 앱 빌드 1200초 제한입니다. 시간 초과 시 이번 작업이 시작한 프로세스와 자식만 종료합니다. 실패한 다운로드는 임시 파일을 제거하고 기존 정상 캐시는 보존합니다.

진단 규칙은 `powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/package-support.test.ps1`로 검사합니다. Windows CI에서는 Windows PowerShell과 PowerShell 7을 모두 검사합니다. 0.0.1 원격 로그에서 Windows 기본 tar.exe의 PostgreSQL 추출이 180초 제한으로 실패한 것을 확인해 7-Zip 방식으로 교체했습니다. tar 내부 대기 원인은 확정하지 못했으며 수정본의 원격 실행 성공은 별도 확인이 필요합니다.

PostgreSQL 아카이브는 7-Zip으로 XZ를 풀고 그 안의 TAR를 추출합니다. 두 단계에 각각 180초 제한을 적용하며 `bin/initdb.exe` 존재를 확인합니다. 중간 TAR는 설치 파일에 포함하지 않습니다. GitHub Windows 러너의 사전 설치 도구를 사용하고, 로컬에 없으면 공식 26.04 포터블 도구를 SHA-256 검증 후 `tools-cache/deploy/7zip-26.04/`에 준비합니다. 시스템 PATH나 Java 환경변수는 바꾸지 않습니다. 압축 회귀 검사는 `scripts/package-postgres.test.ps1`이며 Windows CI에서 두 PowerShell로 실행합니다.

PostgreSQL 초기화 중에는 현재 설치 계정에 데이터 폴더 쓰기와 임시 비밀번호 파일 읽기만 허용하며, 성공·실패 후 임시 권한과 파일을 정리합니다. 설정 폴더 전체의 관리자/SYSTEM 접근 제한은 유지합니다. 관리자 PowerShell에서 `scripts/postgres-permissions.test.ps1 -Initdb <설치 폴더의 postgresql/bin/initdb.exe>`로 실제 Program Files 초기화·실패 정리·설정 폴더 권한 보존을 검사할 수 있습니다.

설치 입력 규칙은 `scripts/install-config.test.ps1`, 4가지 설치 조합·실패 재시도·소유권·보존 검사는 `scripts/installer-flow.test.ps1`로 검증합니다. 번들 Redis 실행 검사는 `scripts/redis-bundle.test.ps1 -ServerPath <redis-server.exe>`를 사용합니다. Redis·Cygwin·OpenSSL·GCC·libiconv/libintl·zlib 원문 고지와 소스 입수 안내는 설치 폴더 `licenses/`에 보존합니다. Redis Windows 빌드는 커뮤니티 배포판이며 Redis 공식 Windows 배포판은 아닙니다.

제거 검사는 관리자 PowerShell에서 `scripts/uninstaller.test.ps1 -Compiler <ISCC.exe> -WinSW <WinSW.exe>`로 실행합니다. 실제 설치와 분리된 시험 경로·고유 이름의 서비스로 구버전 갱신 후 PostgreSQL 보존, Redis 보존/삭제/취소 및 제거 실패 시 파일 보존을 확인합니다.

시작 메뉴의 **CheckList → CheckList 종료**를 실행하면 관리자 권한 확인 후 앱과 CheckList 전용 Redis만 종료합니다. 서비스 등록·프로그램·데이터는 지우지 않고 PostgreSQL과 외부 Redis는 계속 실행합니다.


신규 설치·업데이트 안내 검사는 `scripts/installer-mode.test.ps1 -Compiler <ISCC.exe>`로 실행합니다. 실제 Inno에서 신규 설치, 기존 설정, 제거 후 보존된 설정, 실패 재시도, 설치 폴더 변경에 따른 안내·설정 입력 화면·설치 직전 요약을 검사하며 파일 복사 전에 중단합니다.


설치·서비스 로그는 설치를 실행한 계정에서 일반 권한으로 읽을 수 있습니다. 로그 쓰기는 관리자/SYSTEM에 유지하며, 비밀번호가 포함된 `config/`는 계속 관리자/SYSTEM만 접근합니다. 설치가 성공하면 이전 `logs/install-error.txt` 표시를 해제하고 과거 내역은 `logs/install.log`에 남깁니다. 권한 검사는 관리자 PowerShell에서 `scripts/install-log-access.test.ps1`로 준비한 뒤, 출력된 경로를 같은 계정의 일반 PowerShell에서 `scripts/install-log-access.test.ps1 -VerifyRoot <시험 경로>`로 확인합니다.


설치·업데이트에 실패하면 CheckList 앱 서비스만 중단합니다. 기존 보존 동작대로 서비스 등록·설치 파일·설정·업무·첨부 데이터를 남기며 PostgreSQL과 Redis는 중단하거나 제거하지 않습니다. 앱 중단에도 문제가 생기면 최초 설치 실패 원인과 중단 실패 내용을 함께 기록합니다. 자동 재시도는 수행하지 않습니다.


재설치·업데이트는 파일 복사 전에 CheckList 소유 서비스의 중단과 프로세스 종료를 확인합니다. 이전 설치에서 남은 Java는 선택한 설치 폴더의 `jre/bin/java.exe`와 해당 폴더의 `checklist.jar` 실행이 모두 확인되는 경우에만 종료합니다. 관련 경로나 명령을 확인할 수 없으면 PID를 안내하고 설치를 중단합니다. 다른 Java 프로그램은 종료하지 않습니다.

실제 정리 검사는 관리자 PowerShell에서 `scripts/reinstall.test.ps1 -JavaHome <JDK 경로> -JreHome <번들 JRE 경로> -WinSW <WinSW.exe>`로 실행합니다. 분리된 서비스와 시험 JAR로 서비스 종료, 남은 Java 정리, 파일 잠금 해제, 다른 프로그램 보존을 확인합니다. 실제 Java 실행 시험은 공백 있는 영문 경로를 사용하고 한글 경로 소유권 판정은 별도로 검사합니다. 시험 명령이 예상과 다른 코드로 종료되면 저장된 표준 출력·오류의 마지막 40줄도 표시합니다. CI 제거 검사는 실제 Windows 기본 오류 창의 감지·닫기·프로세스 종료와 다른 PID·복수 선택 창 보호까지 확인합니다. 오류 창은 고정 확인 버튼 ID 대신 검증한 창에 닫기를 요청합니다. 오류 문구의 영문 대소문자 차이를 처리하고, 실패 시 창·프로세스 상태와 제거 로그를 `build/installer-test-logs/`에 보관합니다. 해당 로그는 패키징 진단 아티팩트에도 포함합니다.

설치 진행 출력은 UTF-8로 고정해 Windows 서버의 코드 페이지와 무관하게 한글을 표시합니다. 진행 화면·오류 문구·UTF-8 로그는 실제 Inno Setup과 Windows PowerShell로 한국어(949)·영문(437)·UTF-8(65001) 출력 환경에서 검사합니다.
