$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'install-config.ps1')
function Assert($Value,$Message){if(!$Value){throw $Message}}
function Expect-Failure([scriptblock]$Action){$failed=$false;try{& $Action}catch{$failed=$true};Assert $failed '실패해야 하는 입력이 허용됨'}
foreach($pgMode in @('existing','new')){foreach($redisMode in @('existing','new')){
 $settings=[pscustomobject]@{postgresMode=$pgMode;dbHost='127.0.0.1';dbPort=5432;dbName='checklist';dbUser='checklist';dbPassword='테스트! a"b\c';redisMode=$redisMode;redisHost='127.0.0.1';redisPort=6379;redisPassword='테스트! a"b\c'}
 $result=ConvertTo-InstallState $settings
 Assert ($result.bundled -eq ($pgMode -eq 'new')) 'DB 설치 선택 불일치'
 Assert ($result.bundledRedis -eq ($redisMode -eq 'new')) 'Redis 설치 선택 불일치'
 Assert ($result.values['spring.data.redis.password'] -eq $settings.redisPassword) '비밀번호 변형'
 Assert ($result.values['spring.datasource.url'] -eq 'jdbc:postgresql://127.0.0.1:5432/checklist') 'DB 주소 불일치'
}}
$settings.dbPort=0;Expect-Failure {ConvertTo-InstallState $settings};$settings.dbPort=5432
$settings.dbHost="localhost`n잘못된값";Expect-Failure {ConvertTo-InstallState $settings};$settings.dbHost='127.0.0.1'
$settings.redisMode='invalid';Expect-Failure {ConvertTo-InstallState $settings};$settings.redisMode='new'
$settings.redisPassword='';Expect-Failure {ConvertTo-InstallState $settings};$settings.redisMode='existing';ConvertTo-InstallState $settings | Out-Null
Assert ((ConvertTo-CygwinPath 'C:\Program Files\CheckList\data') -eq '/cygdrive/c/Program Files/CheckList/data') 'Cygwin 경로 변환 실패'
Expect-Failure {ConvertTo-CygwinPath '\\server\share'}
$escaped=Escape-RedisValue 'a"b\c';Assert ($escaped -eq '"a\"b\\c"') 'Redis 비밀번호 이스케이프 실패'
$endpoints=ConvertTo-LocalEndpoints @([pscustomobject]@{ProcessName='postgres';LocalAddress='0.0.0.0';LocalPort=5544},[pscustomobject]@{ProcessName='postgres';LocalAddress='::';LocalPort=5544},[pscustomobject]@{ProcessName='redis-server';LocalAddress='127.0.0.1';LocalPort=6388})
Assert (@($endpoints.PostgreSQL).Count -eq 1) 'DB 후보 중복 제거 실패'
Assert ($endpoints.PostgreSQL[0].Port -eq 5544) 'DB 비표준 포트 탐지 실패'
Assert ($endpoints.Redis[0].Port -eq 6388) 'Redis 비표준 포트 탐지 실패'
Assert ((Escape-InstallProperty ' a\b') -eq '\ a\\b') 'Java 설정 이스케이프 실패'
$pending=ConvertTo-InstallState $settings
$roundTrip=ConvertFrom-PendingState ($pending|ConvertTo-Json -Depth 5|ConvertFrom-Json)
Assert ($roundTrip.dbPassword -eq $settings.dbPassword) '재시도 비밀번호 유실'
Assert ($roundTrip.redisMode -eq $settings.redisMode) '재시도 Redis 모드 유실'
Assert ((ConvertTo-IniHex ' 가" ') -eq '0020ac0000220020') '재시도 INI 문자 인코딩 오류'
Write-Host '설치 입력 4조합·검증·경로·탐지 검사 통과'
$fixture=Join-Path $PSScriptRoot ('../build/detection test '+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path (Join-Path $fixture 'config')|Out-Null
[IO.File]::WriteAllText((Join-Path $fixture 'config/redis.conf'),'port 6397')
$script:StoppedRedisService=[pscustomobject]@{Name='CheckListRedis';PathName='"'+(Join-Path $fixture 'redis-service.exe')+'"'}
function Get-Process {param($Name,$ErrorAction) return @()}
function Get-CimInstance {param($ClassName,$ErrorAction) return @($script:StoppedRedisService)}
$stopped=Get-LocalEndpoints
Assert ($stopped.Redis[0].Port -eq 6397) '중단된 Redis 서비스 설정 탐지 실패'
Write-Host '중단된 Redis 서비스 주소·포트 탐지 통과'