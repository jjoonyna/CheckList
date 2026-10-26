function Write-SetupStatus([string]$Message){
 $line='[설치] '+$Message;Write-Host $line
 [IO.File]::AppendAllText((Join-Path $Root 'logs/install.log'),(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')+' '+$line+"`r`n",[Text.UTF8Encoding]::new($false))
}
function Invoke-RuntimeCommand([string]$Name,[string]$Executable,[string]$Arguments,[int]$Timeout=180){
 Write-SetupStatus $Name
 $prefix=Join-Path $Root ('logs/setup-'+[guid]::NewGuid().ToString('N'))
 $process=Start-Process -FilePath $Executable -ArgumentList $Arguments -WorkingDirectory $Root -WindowStyle Hidden -PassThru -RedirectStandardOutput ($prefix+'.out.log') -RedirectStandardError ($prefix+'.error.log')
 $null=$process.Handle
 try{
  $watch=[Diagnostics.Stopwatch]::StartNew();$next=15
  while(!$process.WaitForExit(200)){
   if($watch.Elapsed.TotalSeconds -ge $Timeout){throw "$Name 시간 제한 초과. logs 폴더를 확인해 주세요."}
   if($watch.Elapsed.TotalSeconds -ge $next){Write-SetupStatus ($Name+' 진행 중 ('+[int]$watch.Elapsed.TotalSeconds+'초)');$next+=15}
  }
  $process.Refresh()
  if($process.ExitCode -ne 0){throw "$Name 실패 (종료 코드 $($process.ExitCode)). logs 폴더의 진단 기록을 확인해 주세요."}
 }finally{
  if(!$process.HasExited){if($PSVersionTable.PSEdition -eq 'Core'){$process.Kill($true)}else{& "$env:SystemRoot\System32\taskkill.exe" /PID $process.Id /T /F | Out-Null};$null=$process.WaitForExit(5000)}
  $process.Dispose()
 }
}
function Assert-OwnedService([string]$Name,[string]$Executable){
 $service=Get-Service -Name $Name -ErrorAction SilentlyContinue
 if($service){
  $record=Get-CimInstance Win32_Service -Filter "Name='$Name'" -ErrorAction Stop
  $pattern='^(?:"'+[regex]::Escape($Executable)+'"|'+[regex]::Escape($Executable)+')(?:\s|$)'
  if($record.PathName -notmatch $pattern){throw "동일 이름의 다른 서비스가 있습니다: $Name. 기존 서버 사용을 선택해 주세요."}
 }
 return $service
}
function Read-InstallProperties([string]$Path){
 $values=@{}
 foreach($line in (Get-Content -LiteralPath $Path -Encoding UTF8)){
  if($line -match '^([^#!][^=]*)=(.*)$'){
   $key=$matches[1];$value=$matches[2]
   $values[$key]=[regex]::Replace($value,'\\(u[0-9a-fA-F]{4}|.)',{param($match) $token=$match.Groups[1].Value;if($token.StartsWith('u')){return [string][char][Convert]::ToInt32($token.Substring(1),16)};switch($token){'n'{"`n"} 'r'{"`r"} 't'{"`t"} default{$token}}})
  }
 }
 return $values
}
function Start-OwnedDependencies {
 foreach($name in @('CheckListPostgreSQL','CheckListRedis')){
  $markerName=if($name -eq 'CheckListRedis'){'bundled-redis.marker'}else{'bundled-postgresql.marker'}
  if(Test-Path -LiteralPath (Join-Path $configDir $markerName)){
   $executable=if($name -eq 'CheckListRedis'){Join-Path $Root 'redis-service.exe'}else{Join-Path $Root 'postgresql/bin/pg_ctl.exe'}
   if(Assert-OwnedService $name $executable){Start-Service -Name $name}
  }
 }
}
function Set-BundledRedis($State){
 $redisExe=Join-Path $Root 'redis/redis-server.exe';$wrapper=Join-Path $Root 'redis-service.exe';$marker=Join-Path $configDir 'bundled-redis.marker'
 if(!(Test-Path -LiteralPath $redisExe) -or !(Test-Path -LiteralPath $wrapper)){throw '번들 Redis 실행 파일을 찾지 못했습니다.'}
 $existing=Assert-OwnedService 'CheckListRedis' $wrapper
 if(!$existing -and (Get-NetTCPConnection -State Listen -LocalPort $State.redisPort -ErrorAction SilentlyContinue)){throw '선택한 Redis 포트를 다른 프로그램이 사용 중입니다. 포트를 바꾸거나 기존 서버 사용을 선택해 주세요.'}
 if($existing -and $existing.Status -eq 'Running'){Stop-Service -Name CheckListRedis}
 $redisData=Join-Path $Root 'data/redis';New-Item -ItemType Directory -Force -Path $redisData | Out-Null
 Protect-Configuration $redisData
 $conf=@('bind 127.0.0.1','protected-mode yes',('port '+$State.redisPort),('dir '+(Escape-RedisValue (ConvertTo-CygwinPath $redisData))),'appendonly yes','save 900 1',('requirepass '+(Escape-RedisValue $State.values['spring.data.redis.password']))) -join "`r`n"
 $redisConf=Join-Path $configDir 'redis.conf';Write-ProtectedText $redisConf $conf
 $configArgument=[Security.SecurityElement]::Escape('"'+(ConvertTo-CygwinPath $redisConf)+'"')
 $xml='<service><id>CheckListRedis</id><name>CheckList Redis</name><description>CheckList 전용 Redis</description><executable>%BASE%\redis\redis-server.exe</executable><arguments>'+$configArgument+'</arguments><workingdirectory>%BASE%\redis</workingdirectory><logpath>%BASE%\logs</logpath><log mode="roll"/><stoptimeout>30 sec</stoptimeout><onfailure action="restart" delay="10 sec"/></service>'
 Write-ProtectedText (Join-Path $Root 'redis-service.xml') $xml
 if(!$existing){Invoke-RuntimeCommand 'Redis 서비스 등록' $wrapper 'install'}
 Write-ProtectedText $marker 'CheckList Redis 8.10.2'
 Start-Service -Name CheckListRedis
 Wait-RuntimePort $State.redisPort
}
function Wait-RuntimePort([int]$Port){
 for($attempt=0;$attempt -lt 30;$attempt++){
  $client=New-Object Net.Sockets.TcpClient
  try{
   $request=$client.BeginConnect('127.0.0.1',$Port,$null,$null)
   if($request.AsyncWaitHandle.WaitOne(500)){$client.EndConnect($request);return}
  }catch{}finally{$client.Close()}
  Start-Sleep -Milliseconds 500
 }
 throw '신규 서버가 연결 가능한 상태가 되지 않았습니다. logs 폴더를 확인해 주세요.'
}
function Initialize-PostgresData([string]$Initdb,[string]$DataDirectory,[string]$Username,[string]$Password){
 # initdb는 관리자 그룹 권한을 내려 실행하므로 현재 사용자 SID로만 임시 접근을 허용한다.
 $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
 $pwFile=Join-Path (Split-Path -Parent $DataDirectory) ('.pg-init-'+[guid]::NewGuid().ToString('N'))
 $grants=@('*S-1-5-18:(OI)(CI)(F)','*S-1-5-32-544:(OI)(CI)(F)')
 if($sid -ne 'S-1-5-18'){$grants+=('*'+$sid+':(OI)(CI)(F)')}
 try{
  New-Item -ItemType Directory -Force -Path $DataDirectory | Out-Null
  & icacls.exe $DataDirectory /inheritance:r /grant:r $grants | Out-Null
  if($LASTEXITCODE -ne 0){throw 'PostgreSQL 초기화 폴더의 접근 권한을 설정하지 못했습니다.'}
  # 설정 폴더의 보호는 유지하고 비밀번호 파일 하나에만 초기화 계정의 읽기를 허용한다.
  Write-ProtectedText $pwFile $Password
  if($sid -ne 'S-1-5-18'){
   & icacls.exe $pwFile /grant:r ('*'+$sid+':(R)') | Out-Null
   if($LASTEXITCODE -ne 0){throw 'PostgreSQL 초기화 비밀번호 파일의 읽기 권한을 설정하지 못했습니다.'}
  }
  Invoke-RuntimeCommand 'PostgreSQL 초기화' $Initdb ('-D "'+$DataDirectory+'" -U "'+$Username+'" --encoding=UTF8 --locale=C --auth-host=scram-sha-256 --auth-local=trust "--pwfile='+$pwFile+'"')
 }finally{
  try{if(Test-Path -LiteralPath $pwFile){Remove-Item -LiteralPath $pwFile -Force}}
  finally{
   if($sid -ne 'S-1-5-18' -and (Test-Path -LiteralPath $DataDirectory)){
    & icacls.exe $DataDirectory /remove:g ('*'+$sid) /T /Q | Out-Null
    if($LASTEXITCODE -ne 0){throw 'PostgreSQL 초기화 계정의 임시 접근 권한을 회수하지 못했습니다.'}
   }
  }
 }
}
