[CmdletBinding()]
param([ValidateSet('install','upgrade','uninstall')][string]$Action='install',[Parameter(Mandatory=$true)][string]$Root)
$ErrorActionPreference='Stop'
$Root=[IO.Path]::GetFullPath($Root)
$configDir=Join-Path $Root 'config';$configPath=Join-Path $configDir 'application.properties'
$dataDir=Join-Path $Root 'data';$pgData=Join-Path $dataDir 'postgres';$pgHome=Join-Path $Root 'postgresql'
$pendingState=Join-Path $configDir 'setup-pending.json'
$pendingConfig=Join-Path $configDir 'application-pending.properties'
$marker=Join-Path $configDir 'bundled-postgresql.marker'
$serviceExe=Join-Path $Root 'checklist-service.exe'
if(!(Test-Path -LiteralPath $serviceExe)){throw 'CheckList 서비스 실행 파일이 없습니다. 설치 폴더를 확인해 주세요.'}
if($Action -eq 'uninstall'){
 if(Get-Service -Name CheckList -ErrorAction SilentlyContinue){& $serviceExe stop;& $serviceExe uninstall}
 if((Test-Path -LiteralPath $marker) -and (Get-Service -Name CheckListPostgreSQL -ErrorAction SilentlyContinue)){
  Stop-Service CheckListPostgreSQL
  & (Join-Path $pgHome 'bin/pg_ctl.exe') unregister -N CheckListPostgreSQL
 }
 Write-Host '서비스를 해제했습니다. 설정과 DB·첨부 데이터는 보존합니다.'
 exit 0
}
function Protect-Configuration([string]$Path){
 & icacls.exe $Path /inheritance:r /grant:r '*S-1-5-18:(F)' '*S-1-5-32-544:(F)' | Out-Null
 if($LASTEXITCODE -ne 0){throw '설정 파일 접근 권한을 제한하지 못했습니다.'}
}
function Escape-Property([string]$Value){
 $parts=foreach($character in $Value.ToCharArray()){
  switch([int]$character){92{'\\'} 10{'\n'} 13{'\r'} 9{'\t'} 32{'\ '} default{if([int]$character -gt 126){'\u{0:x4}' -f [int]$character}else{[string]$character}}}
 }
 return -join $parts
}
function Read-Port([string]$Prompt,[int]$Default){
 $value=Read-Host "$Prompt [$Default]";if(!$value){return $Default}
 $number=0;if(![int]::TryParse($value,[ref]$number) -or $number -lt 1 -or $number -gt 65535){throw '포트는 1~65535 사이 숫자로 입력해 주세요.'};return $number
}
New-Item -ItemType Directory -Force -Path $configDir,$dataDir,(Join-Path $Root 'logs'),(Join-Path $dataDir 'attachments') | Out-Null
if(!(Test-Path -LiteralPath $configPath)){
 if(Test-Path -LiteralPath $pendingState){
  $saved=Get-Content -LiteralPath $pendingState -Raw -Encoding UTF8 | ConvertFrom-Json
  $values=@{};$saved.values.PSObject.Properties | ForEach-Object {$values[$_.Name]=[string]$_.Value}
  $bundled=[bool]$saved.bundled;$dbPort=[int]$saved.dbPort;$dbUser=$values['spring.datasource.username'];$dbPassword=$values['spring.datasource.password']
  Write-Host '앞선 설치 설정으로 재시도합니다.'
 }else{
 Write-Host 'CheckList 최초 설치 설정' -ForegroundColor Cyan
 $mode=Read-Host 'PostgreSQL: 기존 서버 사용은 1, 이 PC에 함께 설치하려면 2'
 if($mode -notin @('1','2')){throw '설치 방식은 1 또는 2로 선택해 주세요.'}
 $bundled=$mode -eq '2'
 $dbHost=if($bundled){'127.0.0.1'}else{Read-Host 'PostgreSQL 서버 주소 [localhost]'};if(!$dbHost){$dbHost='localhost'}
 $dbPort=Read-Port 'PostgreSQL 포트' 5432
 $dbName=Read-Host '데이터베이스 이름 [checklist]';if(!$dbName){$dbName='checklist'}
 if($dbName -notmatch '^[A-Za-z_][A-Za-z0-9_]{0,62}$'){throw 'DB 이름은 영문·숫자·밑줄로 입력해 주세요.'}
 $dbUser=Read-Host 'PostgreSQL 계정 [checklist]';if(!$dbUser){$dbUser='checklist'}
 $dbPassword=[Net.NetworkCredential]::new('',(Read-Host 'PostgreSQL 비밀번호' -AsSecureString)).Password
 if(!$dbPassword){throw 'PostgreSQL 비밀번호를 입력해 주세요.'}
 $redisHost=Read-Host 'Redis 서버 주소 [localhost]';if(!$redisHost){$redisHost='localhost'}
 Write-Host 'Redis는 실행 중인 로컬 또는 사내 서버를 사용합니다.'
 $redisPort=Read-Port 'Redis 포트' 6379
 $redisPassword=[Net.NetworkCredential]::new('',(Read-Host 'Redis 비밀번호 (없으면 Enter)' -AsSecureString)).Password
 $secretBytes=New-Object byte[] 48;$random=[Security.Cryptography.RandomNumberGenerator]::Create();try{$random.GetBytes($secretBytes)}finally{$random.Dispose()}
 $values=@{
  'spring.datasource.url'="jdbc:postgresql://${dbHost}:${dbPort}/${dbName}"
  'spring.datasource.username'=$dbUser;'spring.datasource.password'=$dbPassword
  'spring.data.redis.host'=$redisHost;'spring.data.redis.port'=[string]$redisPort;'spring.data.redis.password'=$redisPassword
  'server.address'='0.0.0.0';'server.port'='8383';'app.jwt-secret'=[Convert]::ToBase64String($secretBytes)
  'app.file-directory'='./data/attachments'
 }
 $state=@{values=$values;bundled=$bundled;dbPort=$dbPort}|ConvertTo-Json -Depth 4
 [IO.File]::WriteAllText($pendingState,$state,[Text.UTF8Encoding]::new($false));Protect-Configuration $pendingState
 }
 $properties=($values.Keys|Sort-Object|ForEach-Object {$_+'='+(Escape-Property $values[$_])}) -join "`r`n"
 [IO.File]::WriteAllText($pendingConfig,$properties,[Text.UTF8Encoding]::new($false));Protect-Configuration $pendingConfig
 if($bundled){
  $initdb=Join-Path $pgHome 'bin/initdb.exe';$pgCtl=Join-Path $pgHome 'bin/pg_ctl.exe'
  if(!(Test-Path -LiteralPath $initdb)){throw '번들 PostgreSQL 실행 파일을 찾지 못했습니다.'}
  $pgService=Get-Service -Name CheckListPostgreSQL -ErrorAction SilentlyContinue
  if($pgService -and !(Test-Path -LiteralPath $marker)){throw '같은 이름의 PostgreSQL 서비스가 존재합니다. 기존 서버 사용을 선택해 주세요.'}
  if(!$pgService -and (Get-NetTCPConnection -State Listen -LocalPort $dbPort -ErrorAction SilentlyContinue)){throw '선택한 PostgreSQL 포트를 다른 프로그램이 사용 중입니다.'}
  if(!(Test-Path -LiteralPath (Join-Path $pgData 'PG_VERSION'))){
  $pwFile=Join-Path $configDir '.pg-init-password'
  try{
   [IO.File]::WriteAllText($pwFile,$dbPassword,[Text.UTF8Encoding]::new($false));Protect-Configuration $pwFile
   & $initdb -D $pgData -U $dbUser --encoding=UTF8 --locale=C --auth-host=scram-sha-256 --auth-local=trust "--pwfile=$pwFile"
   if($LASTEXITCODE -ne 0){throw 'PostgreSQL 초기화 실패'}
  }finally{if(Test-Path -LiteralPath $pwFile){Remove-Item -LiteralPath $pwFile -Force}}
  [IO.File]::AppendAllText((Join-Path $pgData 'postgresql.conf'),"`nlisten_addresses = '127.0.0.1'`nport = $dbPort`n",[Text.UTF8Encoding]::new($false))
  }
  if(!$pgService){
  & $pgCtl register -N CheckListPostgreSQL -D $pgData -S auto
  if($LASTEXITCODE -ne 0){throw 'PostgreSQL 서비스 등록 실패'}
  [IO.File]::WriteAllText($marker,'CheckList PostgreSQL 18.6',[Text.Encoding]::ASCII)
  }
  Start-Service CheckListPostgreSQL
  & (Join-Path $Root 'jre/bin/java.exe') -jar (Join-Path $Root 'checklist.jar') --checklist-create-database $pendingConfig
  if($LASTEXITCODE -ne 0){throw 'PostgreSQL 데이터베이스 생성 실패'}
 }
 Move-Item -LiteralPath $pendingConfig -Destination $configPath
 Remove-Item -LiteralPath $pendingState -Force
}
Protect-Configuration $configPath
if(!(Get-Service -Name CheckList -ErrorAction SilentlyContinue)){
 & $serviceExe install
 if($LASTEXITCODE -ne 0){throw 'CheckList 서비스 등록 실패'}
}
Start-Service CheckList
$ready=$false
for($attempt=0;$attempt -lt 30;$attempt++){
 try{if((Invoke-RestMethod -Uri 'http://127.0.0.1:8383/api/health' -TimeoutSec 2).status -eq 'UP'){$ready=$true;break}}catch{}
 Start-Sleep -Seconds 1
}
if(!$ready){throw '서비스를 등록했지만 앱 준비 확인에 실패했습니다. logs 폴더를 확인한 뒤 같은 설치 명령으로 재시도해 주세요.'}
Write-Host '설치 완료: http://localhost:8383'