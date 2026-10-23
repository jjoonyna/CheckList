[CmdletBinding()]
param([ValidateSet('install','upgrade','uninstall')][string]$Action='install',[Parameter(Mandatory=$true)][string]$Root,[string]$SettingsFile)
$ErrorActionPreference='Stop'
$Root=[IO.Path]::GetFullPath($Root)
. (Join-Path $PSScriptRoot 'install-config.ps1')
. (Join-Path $PSScriptRoot 'runtime-support.ps1')
$configDir=Join-Path $Root 'config';$configPath=Join-Path $configDir 'application.properties'
$pendingState=Join-Path $configDir 'setup-pending.json';$pendingConfig=Join-Path $configDir 'application-pending.properties'
$dataDir=Join-Path $Root 'data';$pgData=Join-Path $dataDir 'postgres';$pgHome=Join-Path $Root 'postgresql'
$marker=Join-Path $configDir 'bundled-postgresql.marker';$serviceExe=Join-Path $Root 'checklist-service.exe'
New-Item -ItemType Directory -Force -Path $configDir,$dataDir,(Join-Path $Root 'logs'),(Join-Path $dataDir 'attachments') | Out-Null
Protect-Configuration $configDir;Protect-Configuration (Join-Path $Root 'logs')
try{
 if(!(Test-Path -LiteralPath $serviceExe)){throw 'CheckList 서비스 실행 파일이 없습니다.'}
 if($Action -eq 'uninstall'){
  Write-SetupStatus '앱 서비스 해제'
  if(Assert-OwnedService 'CheckList' $serviceExe){Stop-Service CheckList;Invoke-RuntimeCommand '앱 서비스 등록 해제' $serviceExe 'uninstall'}
  if((Test-Path -LiteralPath (Join-Path $configDir 'bundled-redis.marker')) -and (Assert-OwnedService 'CheckListRedis' (Join-Path $Root 'redis-service.exe'))){Stop-Service CheckListRedis;Invoke-RuntimeCommand 'Redis 서비스 등록 해제' (Join-Path $Root 'redis-service.exe') 'uninstall'}
  if((Test-Path -LiteralPath $marker) -and (Assert-OwnedService 'CheckListPostgreSQL' (Join-Path $pgHome 'bin/pg_ctl.exe'))){Stop-Service CheckListPostgreSQL;Invoke-RuntimeCommand 'PostgreSQL 서비스 등록 해제' (Join-Path $pgHome 'bin/pg_ctl.exe') 'unregister -N CheckListPostgreSQL'}
  Write-SetupStatus '서비스 해제 완료. 설정·DB·Redis·첨부 데이터는 보존했습니다.'
  return
 }
 if(!(Test-Path -LiteralPath $configPath)){
  if($SettingsFile){
   $settings=Get-Content -LiteralPath $SettingsFile -Raw -Encoding UTF8 | ConvertFrom-Json
   $state=ConvertTo-InstallState $settings
   Write-ProtectedText $pendingState ($state|ConvertTo-Json -Depth 5)
  }elseif(Test-Path -LiteralPath $pendingState){
   $saved=Get-Content -LiteralPath $pendingState -Raw -Encoding UTF8 | ConvertFrom-Json
   $values=@{};$saved.values.PSObject.Properties|ForEach-Object {$values[$_.Name]=[string]$_.Value}
   $state=@{values=$values;bundled=[bool]$saved.bundled;bundledRedis=[bool]$saved.bundledRedis;dbPort=[int]$saved.dbPort;redisPort=[int]$values['spring.data.redis.port']}
   Write-SetupStatus '보호된 이전 설정으로 재시도'
  }else{throw '설치 마법사에서 서버 설정을 입력해 주세요.'}
  $values=$state.values
  $properties=($values.Keys|Sort-Object|ForEach-Object {$_+'='+(Escape-InstallProperty $values[$_])}) -join "`r`n"
  Write-ProtectedText $pendingConfig $properties
  if($state.bundled){
   Write-SetupStatus 'PostgreSQL 준비'
   $initdb=Join-Path $pgHome 'bin/initdb.exe';$pgCtl=Join-Path $pgHome 'bin/pg_ctl.exe'
   if(!(Test-Path -LiteralPath $initdb)){throw '번들 PostgreSQL 실행 파일을 찾지 못했습니다.'}
   $pgService=Assert-OwnedService 'CheckListPostgreSQL' $pgCtl
   if(!$pgService -and (Get-NetTCPConnection -State Listen -LocalPort $state.dbPort -ErrorAction SilentlyContinue)){throw '선택한 PostgreSQL 포트를 다른 프로그램이 사용 중입니다. 포트를 바꾸거나 기존 서버 사용을 선택해 주세요.'}
   if(!(Test-Path -LiteralPath (Join-Path $pgData 'PG_VERSION'))){
    $pwFile=Join-Path $configDir '.pg-init-password'
    try{Write-ProtectedText $pwFile $values['spring.datasource.password'];Invoke-RuntimeCommand 'PostgreSQL 초기화' $initdb ('-D "'+$pgData+'" -U "'+$values['spring.datasource.username']+'" --encoding=UTF8 --locale=C --auth-host=scram-sha-256 --auth-local=trust "--pwfile='+$pwFile+'"')}
    finally{if(Test-Path -LiteralPath $pwFile){Remove-Item -LiteralPath $pwFile -Force}}
    [IO.File]::AppendAllText((Join-Path $pgData 'postgresql.conf'),"`nlisten_addresses = '127.0.0.1'`nport = $($state.dbPort)`n",[Text.UTF8Encoding]::new($false))
   }
   if(!$pgService){Invoke-RuntimeCommand 'PostgreSQL 서비스 등록' $pgCtl ('register -N CheckListPostgreSQL -D "'+$pgData+'" -S auto')}
   Write-ProtectedText $marker 'CheckList PostgreSQL 18.6'
   Start-Service CheckListPostgreSQL
   Wait-RuntimePort $state.dbPort
  }
  if($state.bundledRedis){Write-SetupStatus 'Redis 준비';Set-BundledRedis $state}
  # 기존 서버도 DB 존재·접속을 확인한다. 없다면 입력 계정의 권한으로만 생성한다.
  Invoke-RuntimeCommand 'PostgreSQL 연결 및 데이터베이스 확인' (Join-Path $Root 'jre/bin/java.exe') ('-jar "'+(Join-Path $Root 'checklist.jar')+'" --checklist-create-database "'+$pendingConfig+'"')
  Write-SetupStatus 'Redis 연결 및 인증 확인'
  Test-RedisConnection $values['spring.data.redis.host'] ([int]$values['spring.data.redis.port']) $values['spring.data.redis.password']
  Move-Item -LiteralPath $pendingConfig -Destination $configPath
  Remove-Item -LiteralPath $pendingState -Force
 }else{
  $values=Read-InstallProperties $configPath
  Start-OwnedDependencies
  Write-SetupStatus '기존 Redis 연결 확인'
  Test-RedisConnection $values['spring.data.redis.host'] ([int]$values['spring.data.redis.port']) $values['spring.data.redis.password']
 }
 Protect-Configuration $configPath
 if(!(Assert-OwnedService 'CheckList' $serviceExe)){Invoke-RuntimeCommand 'CheckList 서비스 등록' $serviceExe 'install'}
 Write-SetupStatus 'CheckList 서비스 시작'
 Start-Service CheckList
 $ready=$false
 for($attempt=0;$attempt -lt 30;$attempt++){
  try{if((Invoke-RestMethod -Uri 'http://127.0.0.1:8383/api/health' -TimeoutSec 2).status -eq 'UP'){$ready=$true;break}}catch{}
  Start-Sleep -Seconds 1
 }
 if(!$ready){throw '앱 준비 확인에 실패했습니다. logs 폴더를 확인한 뒤 설치 프로그램을 다시 실행해 주세요.'}
 Write-SetupStatus '설치 완료: http://localhost:8383'
}catch{
 Write-SetupStatus ('설치 실패: '+$_.Exception.Message)
 Write-ProtectedText (Join-Path $Root 'logs/install-error.txt') $_.Exception.Message
 throw
}finally{
 if($SettingsFile -and (Test-Path -LiteralPath $SettingsFile)){Remove-Item -LiteralPath $SettingsFile -Force}
}