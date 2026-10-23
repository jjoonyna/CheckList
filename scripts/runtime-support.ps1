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