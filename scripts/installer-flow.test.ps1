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
function Get-Service {param($Name,$ErrorAction) return $script:Services[$Name]}
function Get-CimInstance {param($ClassName,$Filter,$ErrorAction) $serviceName=$Filter -replace "^Name='|'$",'';return $script:Services[$serviceName]}
function Wait-RuntimePort {param($Port)}
function Start-Service {param($Name) $script:Events.Add('start:'+ $Name)}
function Stop-Service {param($Name) $script:Events.Add('stop:'+ $Name)}
function Get-NetTCPConnection {param($State,$LocalPort,$ErrorAction) if($script:ConflictPort -eq $LocalPort){return @{LocalPort=$LocalPort}}}
function Invoke-RestMethod {param($Uri,$TimeoutSec) return @{status='UP'}}
function Test-RedisConnection {param($Server,$Port,$Password) if($script:FailRedis){throw '모의 Redis 연결 실패'}}
function Invoke-RuntimeCommand {param($Name,$Executable,$Arguments,$Timeout)
 $script:Events.Add($Name)
 if($Name -eq 'PostgreSQL 초기화'){
  $dir=Join-Path $script:FixtureRoot 'data/postgres';New-Item -ItemType Directory -Force -Path $dir | Out-Null
  [IO.File]::WriteAllText((Join-Path $dir 'PG_VERSION'),'18')
 }
 $serviceName=switch($Name){'PostgreSQL 서비스 등록'{'CheckListPostgreSQL'} 'Redis 서비스 등록'{'CheckListRedis'} 'CheckList 서비스 등록'{'CheckList'}}
 if($serviceName){$script:Services[$serviceName]=[pscustomobject]@{Name=$serviceName;Status='Stopped';PathName='"'+$Executable+'"'}}
 if($Name -eq 'Redis 서비스 등록 해제'){$script:Services.Remove('CheckListRedis')}
 if($Name -eq 'PostgreSQL 서비스 등록 해제'){$script:Services.Remove('CheckListPostgreSQL')}
 if($Name -eq '앱 서비스 등록 해제'){$script:Services.Remove('CheckList')}
}
function New-Fixture([string]$Name){
 $script:FixtureRoot=Join-Path $testBase $Name;$script:Services=@{};$script:Events=[Collections.Generic.List[string]]::new();$script:FailRedis=$false;$script:ConflictPort=-1
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
Assert ($script:Services.Count -eq 0) '서비스 해제 누락'
$root=New-Fixture 'collision';$file=Write-Input 'existing' 'new';$script:ConflictPort=6388
$failed=$false;try{& $installer -Root $root -SettingsFile $file}catch{$failed=$_.Exception.Message -match '포트'}
Assert $failed 'Redis 포트 충돌 허용'
Assert (!$script:Events.Contains('Redis 서비스 등록')) '충돌한 Redis 설치 진행'
$script:Services.CheckList=[pscustomobject]@{Name='CheckList';Status='Stopped';PathName='"C:\Other\checklist-service.exe"'}
$failed=$false;try{Assert-OwnedService 'CheckList' (Join-Path $root 'checklist-service.exe')}catch{$failed=$true}
Assert $failed '타 설치 서비스 소유권 충돌 허용'
Write-Host "설치 4조합·실패 재시도·데이터 보존·포트/서비스 충돌 검사 통과: $testBase"