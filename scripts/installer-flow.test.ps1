$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'install-config.ps1')
. (Join-Path $PSScriptRoot 'runtime-support.ps1')
$source=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'install-runtime.ps1'))
$source=[regex]::Replace($source,'(?m)^\. \(Join-Path \$PSScriptRoot ''(?:install-config|runtime-support)\.ps1''\)\r?\n','')
$installer=[scriptblock]::Create($source)
$testBase=Join-Path $PSScriptRoot ('../build/installer flow '+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $testBase | Out-Null
function Assert($Value,$Message){if(!$Value){throw $Message}}
function Protect-Configuration([string]$Path){}
function Set-InstallLogAccess([string]$Directory){}
function Get-Service {param($Name,$ErrorAction) return $script:Services[$Name]}
function Get-CimInstance {param($ClassName,$Filter,$ErrorAction) $serviceName=$Filter -replace "^Name='|'$",'';return $script:Services[$serviceName]}
function Initialize-PostgresData {param($Initdb,$DataDirectory,$Username,$Password) Invoke-RuntimeCommand 'PostgreSQL 초기화' $Initdb ''}
function Stop-OwnedService {param($Name,$Executable)
 $service=Assert-OwnedService $Name $Executable
 if(!$service){return $false}
 if($script:FailStopApp){throw '모의 앱 중단 실패'}
 Stop-Service $Name;return $true
}
function Unregister-OwnedService {param($Name,$Executable,$Label) if(Assert-OwnedService $Name $Executable){Stop-Service $Name;Invoke-RuntimeCommand $Label $Executable 'uninstall'}}
function Wait-RuntimePort {param($Port)}
function Start-Service {param($Name) $script:Events.Add('start:'+ $Name);if($script:Services[$Name]){$script:Services[$Name].Status='Running'}}
function Stop-Service {param($Name) $script:Events.Add('stop:'+ $Name);if($script:Services[$Name]){$script:Services[$Name].Status='Stopped'}}
function Get-NetTCPConnection {param($State,$LocalPort,$ErrorAction) if($script:ConflictPort -eq $LocalPort){return @{LocalPort=$LocalPort}}}
function Start-Sleep {param($Seconds,$Milliseconds)}
function Invoke-RestMethod {param($Uri,$TimeoutSec) if($script:FailHealth){return @{status='DOWN'}};return @{status='UP'}}
function Test-RedisConnection {param($Server,$Port,$Password) if($script:FailRedis){throw '모의 Redis 연결 실패'}}
function Invoke-RuntimeCommand {param($Name,$Executable,$Arguments,$Timeout)
 $script:Events.Add($Name)
 if($Name -eq 'PostgreSQL 초기화'){
  $dir=Join-Path $script:FixtureRoot 'data/postgres';New-Item -ItemType Directory -Force -Path $dir | Out-Null
  [IO.File]::WriteAllText((Join-Path $dir 'PG_VERSION'),'18')
 }
 $serviceName=switch($Name){'PostgreSQL 서비스 등록'{'CheckListPostgreSQL'} 'Redis 서비스 등록'{'CheckListRedis'} 'CheckList 서비스 등록'{'CheckList'}}
 if($serviceName){$service=[pscustomobject]@{Name=$serviceName;Status='Stopped';PathName='"'+$Executable+'"'};$service|Add-Member -MemberType ScriptMethod -Name Dispose -Value {};$script:Services[$serviceName]=$service}
 if($Name -eq 'Redis 서비스 등록 해제'){$script:Services.Remove('CheckListRedis')}
 if($Name -eq 'PostgreSQL 서비스 등록 해제'){$script:Services.Remove('CheckListPostgreSQL')}
 if($Name -eq '앱 서비스 등록 해제'){$script:Services.Remove('CheckList')}
}
function New-Fixture([string]$Name){
 $script:FixtureRoot=Join-Path $testBase $Name;$script:Services=@{};$script:Events=[Collections.Generic.List[string]]::new();$script:FailRedis=$false;$script:FailHealth=$false;$script:FailStopApp=$false;$script:ConflictPort=-1
 foreach($dir in @('postgresql/bin','redis','config')){New-Item -ItemType Directory -Force -Path (Join-Path $script:FixtureRoot $dir)|Out-Null}
 foreach($file in @('checklist-service.exe','redis-service.exe','postgresql/bin/initdb.exe','redis/redis-server.exe')){[IO.File]::WriteAllText((Join-Path $script:FixtureRoot $file),'대역')}
 return $script:FixtureRoot
}
function Write-Input([string]$Pg,[string]$Redis){
 $settings=@{postgresMode=$Pg;dbHost='127.0.0.1';dbPort=5544;dbName='checklist';dbUser='checklist';dbPassword='fixture-db';redisMode=$Redis;redisHost='127.0.0.1';redisPort=6388;redisPassword='fixture-redis'}
 $file=Join-Path $script:FixtureRoot 'config/setup-input.json'
 [IO.File]::WriteAllText($file,($settings|ConvertTo-Json),[Text.UTF8Encoding]::new($false));return $file
}
foreach($pg in @('existing','new')){foreach($redis in @('existing','new')){
 $root=New-Fixture ($pg+'-'+$redis);$file=Write-Input $pg $redis
 & $installer -Root $root -SettingsFile $file
 Assert (Test-Path (Join-Path $root 'config/application.properties')) '설정 승격 실패'
 Assert (!(Test-Path (Join-Path $root 'config/setup-pending.json'))) '성공 뒤 pending 남음'
 Assert (!(Test-Path $file)) '입력 비밀 파일 남음'
 Assert (($script:Events.Contains('PostgreSQL 서비스 등록')) -eq ($pg -eq 'new')) '기존 DB 서비스 변경 또는 신규 DB 미설치'
 Assert (($script:Events.Contains('Redis 서비스 등록')) -eq ($redis -eq 'new')) '기존 Redis 서비스 변경 또는 신규 Redis 미설치'
 if($redis -eq 'new'){
  $redisText=Get-Content (Join-Path $root 'config/redis.conf') -Raw
  Assert ($redisText -match '(?m)^port 6388\r?$') 'Redis 포트 문법 오류'
  Assert ($redisText -match '(?m)^requirepass "fixture-redis"\r?$') 'Redis 비밀번호 문법 오류'
  [xml]$redisXml=Get-Content (Join-Path $root 'redis-service.xml') -Raw
  Assert ($redisXml.service.id -eq 'CheckListRedis') 'Redis 서비스 XML 오류'
 }
 Write-Host "설치 조합 통과: $pg / $redis"
 $before=[IO.File]::ReadAllBytes((Join-Path $root 'config/application.properties'))
 [IO.File]::WriteAllText((Join-Path $root 'logs/install-error.txt'),'과거 오류')
 $script:Events.Clear()
 & $installer -Root $root -Action upgrade
 Assert (!(Test-Path (Join-Path $root 'logs/install-error.txt'))) '성공 후 과거 오류가 남음'
 $after=[IO.File]::ReadAllBytes((Join-Path $root 'config/application.properties'))
 Assert ([Convert]::ToBase64String($before) -eq [Convert]::ToBase64String($after)) '업데이트가 기존 설정을 변경함'
 foreach($event in @('PostgreSQL 초기화','PostgreSQL 서비스 등록','Redis 서비스 등록','CheckList 서비스 등록')){Assert (!$script:Events.Contains($event)) ('업데이트 중 재생성: '+$event)}
 Assert ($script:Events.Contains('start:CheckList')) '업데이트 후 앱 서비스가 시작되지 않음'
 Write-Host "업데이트 설정 보존 통과: $pg / $redis"

}}
$root=New-Fixture 'retry';$file=Write-Input 'new' 'new';$script:FailRedis=$true
$failed=$false;try{& $installer -Root $root -SettingsFile $file}catch{$failed=$_.Exception.Message -match 'Redis'}
Assert $failed '실패 재현 안 됨'
Assert (!(Test-Path (Join-Path $root 'config/application.properties'))) '실패한 설정이 완료로 승격됨'
Assert (Test-Path (Join-Path $root 'config/setup-pending.json')) '재시도 입력 유실'
$script:FailRedis=$false;& $installer -Root $root
Assert (Test-Path (Join-Path $root 'config/application.properties')) '재시도 실패'
Assert (@($script:Events|Where-Object {$_ -eq 'PostgreSQL 초기화'}).Count -eq 1) '기존 DB를 다시 초기화함'
& $installer -Root $root -Action uninstall
Assert (Test-Path (Join-Path $root 'data/postgres/PG_VERSION')) '제거 시 DB 데이터 삭제'
Assert (Test-Path (Join-Path $root 'config/redis.conf')) '제거 시 Redis 설정 삭제'
Assert ($script:Services.Count -eq 2) '기본 제거에서 PostgreSQL/Redis 서비스가 사라짐'
Assert ($script:Services.ContainsKey('CheckListPostgreSQL')) 'PostgreSQL 서비스가 제거됨'
Assert ($script:Services.ContainsKey('CheckListRedis')) '보존 선택한 Redis 서비스가 제거됨'
$root=New-Fixture 'remove-redis';$file=Write-Input 'new' 'new'
& $installer -Root $root -SettingsFile $file
[IO.File]::WriteAllText((Join-Path $root 'data/redis/session-test.txt'),'Redis 삭제 확인')
[IO.File]::WriteAllText((Join-Path $root 'data/attachments/keep.txt'),'첨부 보존 확인')
& $installer -Root $root -Action uninstall -RemoveRedis
Assert ($script:Services.ContainsKey('CheckListPostgreSQL')) 'Redis 제거 중 PostgreSQL 서비스가 제거됨'
Assert (!$script:Services.ContainsKey('CheckListRedis')) '선택한 Redis 서비스가 남음'
foreach($relative in @('redis','redis-service.exe','redis-service.xml','data/redis','config/redis.conf','config/bundled-redis.marker')){Assert (!(Test-Path (Join-Path $root $relative))) ('Redis 제거 잔존: '+$relative)}
Assert (Test-Path (Join-Path $root 'data/postgres/PG_VERSION')) 'Redis 제거 중 PostgreSQL 데이터가 삭제됨'
Assert ([IO.File]::ReadAllText((Join-Path $root 'data/attachments/keep.txt')) -eq '첨부 보존 확인') 'Redis 제거 중 첨부가 변경됨'
Assert (Test-Path (Join-Path $root 'config/application.properties')) '앱 설정 보존 실패'
$root=New-Fixture 'foreign-redis';$file=Write-Input 'new' 'new'
& $installer -Root $root -SettingsFile $file
$script:Services.CheckListRedis.PathName='"C:\Other\redis-service.exe"'
$failed=$false;try{& $installer -Root $root -Action uninstall -RemoveRedis}catch{$failed=$_.Exception.Message -match '다른 서비스'}
Assert $failed '다른 경로의 Redis 서비스 제거를 차단하지 못함'
Assert ($script:Services.ContainsKey('CheckList')) '사전 검증 실패 전에 앱 서비스가 제거됨'
Assert (!$script:Events.Contains('stop:CheckList')) '제거 사전 검증 실패에 앱 중단이 적용됨'
Assert (Test-Path (Join-Path $root 'data/redis')) '다른 설치 서비스 충돌 후 Redis 데이터가 삭제됨'
$root=New-Fixture 'linked-redis';$file=Write-Input 'new' 'new'
& $installer -Root $root -SettingsFile $file
$outside=Join-Path $testBase 'outside-data';New-Item -ItemType Directory -Force -Path $outside | Out-Null
[IO.File]::WriteAllText((Join-Path $outside 'keep.txt'),'외부 경로 보존')
$link=Join-Path $root 'data/redis/linked';New-Item -ItemType Junction -Path $link -Target $outside | Out-Null
try{
 $failed=$false;try{& $installer -Root $root -Action uninstall -RemoveRedis}catch{$failed=$_.Exception.Message -match '연결된'}
 Assert $failed 'Redis 데이터의 연결된 외부 폴더를 차단하지 못함'
 Assert ([IO.File]::ReadAllText((Join-Path $outside 'keep.txt')) -eq '외부 경로 보존') '외부 경로 데이터가 변경됨'
 Assert ($script:Services.ContainsKey('CheckList')) '경로 검증 실패 전에 앱 서비스가 제거됨'
}finally{
 if([IO.Path]::GetFullPath($link).StartsWith([IO.Path]::GetFullPath($root)+[IO.Path]::DirectorySeparatorChar) -and ((Get-Item -LiteralPath $link -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){[IO.Directory]::Delete($link,$false)}
}
$root=New-Fixture 'collision';$file=Write-Input 'existing' 'new';$script:ConflictPort=6388
$failed=$false;try{& $installer -Root $root -SettingsFile $file}catch{$failed=$_.Exception.Message -match '포트'}
Assert $failed 'Redis 포트 충돌 허용'
Assert (!$script:Events.Contains('Redis 서비스 등록')) '충돌한 Redis 설치 진행'
$script:Services.CheckList=[pscustomobject]@{Name='CheckList';Status='Stopped';PathName='"C:\Other\checklist-service.exe"'}
$failed=$false;try{Assert-OwnedService 'CheckList' (Join-Path $root 'checklist-service.exe')}catch{$failed=$true}
Assert $failed '타 설치 서비스 소유권 충돌 허용'
foreach($failureCase in @('health','stop','foreign-app')){
 $root=New-Fixture ('failed-'+$failureCase);$file=Write-Input 'new' 'new'
 & $installer -Root $root -SettingsFile $file
 $before=[IO.File]::ReadAllBytes((Join-Path $root 'config/application.properties'))
 [IO.File]::WriteAllText((Join-Path $root 'data/redis/keep.txt'),'Redis 보존')
 [IO.File]::WriteAllText((Join-Path $root 'data/attachments/keep.txt'),'첨부 보존')
 $script:Events.Clear()
 if($failureCase -eq 'health'){$script:FailHealth=$true}
 else{$script:FailRedis=$true}
 if($failureCase -eq 'stop'){$script:FailStopApp=$true}
 if($failureCase -eq 'foreign-app'){$script:Services.CheckList.PathName='"C:\Other\checklist-service.exe"'}
 $failureMessage='';try{& $installer -Root $root -Action upgrade}catch{$failureMessage=$_.Exception.Message}
 Assert ($failureMessage -ne '') '설치 실패가 보고되지 않음'
 Assert ($script:Events.Contains('stop:CheckList') -eq ($failureCase -eq 'health')) ('실패 후 앱 중단 또는 타 설치 보호 오류: '+$failureCase)
 Assert (!$script:Events.Contains('stop:CheckListRedis')) '실패 처리에서 Redis를 중단함'
 Assert (!$script:Events.Contains('stop:CheckListPostgreSQL')) '실패 처리에서 PostgreSQL을 중단함'
 Assert ($script:Services.Count -eq 3) '실패 처리에서 서비스를 제거함'
 foreach($relative in @('checklist-service.exe','redis-service.exe','postgresql/bin/initdb.exe','data/postgres/PG_VERSION','data/redis/keep.txt','data/attachments/keep.txt')){Assert (Test-Path (Join-Path $root $relative)) ('실패 후 파일 유실: '+$relative)}
 $after=[IO.File]::ReadAllBytes((Join-Path $root 'config/application.properties'))
 Assert ([Convert]::ToBase64String($before) -eq [Convert]::ToBase64String($after)) '실패 후 기존 설정 변경'
 $errorText=[IO.File]::ReadAllText((Join-Path $root 'logs/install-error.txt'))
 if($failureCase -eq 'health'){Assert ($script:Services.CheckList.Status -eq 'Stopped') '실패 후 앱이 실행 중';Assert ($errorText.Contains('앱 준비 확인에 실패했습니다')) '최초 앱 준비 실패 원인 유실'}
 else{Assert ($failureMessage -eq '모의 Redis 연결 실패') '중단 오류가 최초 설치 예외를 덮음';Assert ($errorText.StartsWith('모의 Redis 연결 실패')) '최초 오류 파일 원인 유실';Assert ($errorText.Contains('앱 중단을 확인하지 못했습니다')) '앱 중단 실패 안내 누락'}
 Assert ($script:Services.CheckListRedis.Status -eq 'Running') '실패 후 Redis가 실행 중이 아님'
 Assert ($script:Services.CheckListPostgreSQL.Status -eq 'Running') '실패 후 PostgreSQL이 실행 중이 아님'
 Write-Host ('실패 시 앱 중단·의존 서버/설정/파일 보존 검사 통과: '+$failureCase)
}
Write-Host "설치 4조합·실패 재시도·데이터 보존·포트/서비스 충돌 검사 통과: $testBase"