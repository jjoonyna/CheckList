function New-InstallSecret([int]$Length=24){
 $bytes=New-Object byte[] $Length;$generator=[Security.Cryptography.RandomNumberGenerator]::Create()
 try{$generator.GetBytes($bytes)}finally{$generator.Dispose()}
 return [Convert]::ToBase64String($bytes)
}
function Escape-InstallProperty([string]$Value){
 $parts=foreach($character in $Value.ToCharArray()){
  switch([int]$character){92{'\\'} 10{'\n'} 13{'\r'} 9{'\t'} 32{'\ '} default{if([int]$character -gt 126){'\u{0:x4}' -f [int]$character}else{[string]$character}}}
 }
 return -join $parts
}
function ConvertTo-CygwinPath([string]$Path){
 $full=[IO.Path]::GetFullPath($Path)
 if($full -notmatch '^([A-Za-z]):[\\/](.*)$'){throw 'Redis 신규 설치 경로는 로컬 드라이브여야 합니다.'}
 return '/cygdrive/'+$matches[1].ToLowerInvariant()+'/'+$matches[2].Replace('\','/')
}
function Escape-RedisValue([string]$Value){return '"'+$Value.Replace('\','\\').Replace('"','\"')+'"'}
function ConvertTo-InstallState($Settings){
 foreach($name in @('postgresMode','redisMode')){if($Settings.$name -notin @('existing','new')){throw '기존 서버 사용 또는 새로 설치를 선택해 주세요.'}}
 foreach($name in @('dbPort','redisPort')){
  $port=0;if(![int]::TryParse([string]$Settings.$name,[ref]$port) -or $port -lt 1 -or $port -gt 65535){throw '포트는 1~65535 사이 숫자로 입력해 주세요.'}
 }
 foreach($name in @('dbHost','redisHost')){if([string]$Settings.$name -notmatch '^[A-Za-z0-9_.:-]+$'){throw '서버 주소를 올바르게 입력해 주세요.'}}
 if($Settings.dbName -notmatch '^[A-Za-z_][A-Za-z0-9_]{0,62}$'){throw 'DB 이름은 영문·숫자·밑줄로 입력해 주세요.'}
 if($Settings.dbUser -match '[\x00\r\n"\\]' -or [string]::IsNullOrWhiteSpace($Settings.dbUser) -or [string]::IsNullOrEmpty($Settings.dbPassword)){throw 'PostgreSQL 계정과 비밀번호를 입력해 주세요.'}
 foreach($name in @('dbUser','dbPassword','redisPassword')){if([string]$Settings.$name -match '[\x00\r\n]'){throw '계정과 비밀번호에 줄바꿈을 사용할 수 없습니다.'}}
 foreach($pair in @(@('postgresMode','dbHost'),@('redisMode','redisHost'))){
  if($Settings.($pair[0]) -eq 'new' -and $Settings.($pair[1]) -notin @('localhost','127.0.0.1')){throw '새로 설치할 서버 주소는 localhost 또는 127.0.0.1이어야 합니다.'}
 }
 if($Settings.redisMode -eq 'new' -and [string]::IsNullOrEmpty($Settings.redisPassword)){throw 'Redis 신규 설치 비밀번호를 입력해 주세요.'}
 if($Settings.postgresMode -eq 'new' -and $Settings.redisMode -eq 'new' -and [int]$Settings.dbPort -eq [int]$Settings.redisPort){throw 'PostgreSQL과 Redis는 서로 다른 포트를 사용해야 합니다.'}
 $dbHost=[string]$Settings.dbHost;if($dbHost.Contains(':')){$dbHost='['+$dbHost+']'}
 $values=@{
  'spring.datasource.url'="jdbc:postgresql://${dbHost}:$($Settings.dbPort)/$($Settings.dbName)"
  'spring.datasource.username'=[string]$Settings.dbUser;'spring.datasource.password'=[string]$Settings.dbPassword
  'spring.data.redis.host'=[string]$Settings.redisHost;'spring.data.redis.port'=[string]$Settings.redisPort;'spring.data.redis.password'=[string]$Settings.redisPassword
  'server.address'='0.0.0.0';'server.port'='8383';'app.jwt-secret'=(New-InstallSecret 48);'app.file-directory'='./data/attachments'
 }
 return @{values=$values;bundled=($Settings.postgresMode -eq 'new');bundledRedis=($Settings.redisMode -eq 'new');dbPort=[int]$Settings.dbPort;redisPort=[int]$Settings.redisPort}
}
function ConvertTo-LocalEndpoints($Listeners){
 $pg=@();$redis=@()
 foreach($listener in $Listeners){
  $address=[string]$listener.LocalAddress;if($address -in @('0.0.0.0','::','localhost')){$address='127.0.0.1'}
  $entry=[pscustomobject]@{Host=$address;Port=[int]$listener.LocalPort}
  if($listener.ProcessName -match 'postgres'){$pg+=$entry}elseif($listener.ProcessName -match 'redis'){$redis+=$entry}
 }
 return [pscustomobject]@{PostgreSQL=@($pg|Sort-Object Host,Port -Unique);Redis=@($redis|Sort-Object Host,Port -Unique)}
}
function Get-LocalEndpoints {
 $listeners=@()
 foreach($process in @(Get-Process -Name postgres,redis-server,RedisService -ErrorAction SilentlyContinue)){
  foreach($connection in @(Get-NetTCPConnection -State Listen -OwningProcess $process.Id -ErrorAction SilentlyContinue)){
   $listeners+=[pscustomobject]@{ProcessName=$process.ProcessName;LocalAddress=$connection.LocalAddress;LocalPort=$connection.LocalPort}
  }
 }
 foreach($service in @(Get-CimInstance Win32_Service -ErrorAction SilentlyContinue|Where-Object {$_.Name -match 'postgres|redis' -or $_.PathName -match 'postgres|redis'})){
  $configuration=$null;$kind=if($service.Name -match 'postgres' -or $service.PathName -match 'pg_ctl|postgres.exe'){'postgres'}else{'redis'}
  if($kind -eq 'postgres' -and $service.PathName -match '(?:^|\s)-D\s*(?:"([^"]+)"|(\S+))'){
   $directory=if($matches[1]){$matches[1]}else{$matches[2]};$configuration=Join-Path $directory 'postgresql.conf'
  }elseif($service.PathName -match '"([^\"]+\.conf)"|\s([^\s]+\.conf)'){$configuration=if($matches[1]){$matches[1]}else{$matches[2]}}
  if(!$configuration -and $kind -eq 'redis'){
   $executable=$null
   if($service.PathName -match '^"([^"]+\.exe)"'){$executable=$matches[1]}
   elseif($service.PathName -match '^([^\s]+\.exe)'){$executable=$matches[1]}
   if($executable){
    $serviceDirectory=Split-Path -Parent $executable
    foreach($candidate in @((Join-Path $serviceDirectory 'config/redis.conf'),(Join-Path $serviceDirectory 'redis.conf'))){
     if(Test-Path -LiteralPath $candidate){$configuration=$candidate;break}
    }
   }
  }
  if($configuration -and (Test-Path -LiteralPath $configuration)){
   $content=Get-Content -LiteralPath $configuration -ErrorAction SilentlyContinue
   $port=if($kind -eq 'postgres'){5432}else{6379}
   foreach($line in $content){if($line -match '^\s*port\s*(?:=\s*)?["'']?(\d+)'){$port=[int]$matches[1]}}
   if($port -ge 1 -and $port -le 65535){$listeners+=[pscustomobject]@{ProcessName=$kind;LocalAddress='127.0.0.1';LocalPort=$port}}
  }
 }
 return ConvertTo-LocalEndpoints $listeners
}
function Protect-Configuration([string]$Path){
 & icacls.exe $Path /inheritance:r /grant:r '*S-1-5-18:(F)' '*S-1-5-32-544:(F)' | Out-Null
 if($LASTEXITCODE -ne 0){throw '설정 파일 접근 권한을 제한하지 못했습니다.'}
}
function Write-ProtectedText([string]$Path,[string]$Text){
 if(!(Test-Path -LiteralPath $Path)){[IO.File]::WriteAllText($Path,'')}
 Protect-Configuration $Path
 [IO.File]::WriteAllText($Path,$Text,[Text.UTF8Encoding]::new($false))
}
function Test-RedisConnection([string]$Server,[int]$Port,[string]$Password){
 $client=New-Object Net.Sockets.TcpClient
 try{
  $connection=$client.BeginConnect($Server,$Port,$null,$null)
  if(!$connection.AsyncWaitHandle.WaitOne(3000)){throw 'Redis 연결 시간 초과'}
  $client.EndConnect($connection);$client.ReceiveTimeout=3000;$client.SendTimeout=3000
  $stream=$client.GetStream();$reader=New-Object IO.StreamReader($stream,[Text.Encoding]::UTF8)
  foreach($command in @(@('AUTH',$Password),@('PING'))){
   if($command[0] -eq 'AUTH' -and !$Password){continue}
   $request='*'+$command.Count+"`r`n"
   foreach($part in $command){$bytes=[Text.Encoding]::UTF8.GetByteCount([string]$part);$request+='$'+$bytes+"`r`n"+[string]$part+"`r`n"}
   $payload=[Text.Encoding]::UTF8.GetBytes($request);$stream.Write($payload,0,$payload.Length)
   $response=$reader.ReadLine()
   if(($command[0] -eq 'AUTH' -and $response -ne '+OK') -or ($command[0] -eq 'PING' -and $response -ne '+PONG')){throw 'Redis 인증 또는 응답 확인 실패. 주소·포트·비밀번호를 확인해 주세요.'}
  }
 }catch{throw 'Redis 연결 확인 실패. 주소·포트·비밀번호 및 서버 실행 상태를 확인해 주세요.'}finally{$client.Close()}
}
function ConvertFrom-PendingState($State){
 $values=$State.values
 $get={param($Key) if($values -is [Collections.IDictionary]){return [string]$values[$Key]}else{return [string]$values.$Key}}
 $uri=[uri]((& $get 'spring.datasource.url') -replace '^jdbc:','')
 return [ordered]@{postgresMode=$(if($State.bundled){'new'}else{'existing'});dbHost=$uri.DnsSafeHost;dbPort=[string]$uri.Port;dbName=$uri.AbsolutePath.TrimStart('/');dbUser=(& $get 'spring.datasource.username');dbPassword=(& $get 'spring.datasource.password');redisMode=$(if($State.bundledRedis){'new'}else{'existing'});redisHost=(& $get 'spring.data.redis.host');redisPort=(& $get 'spring.data.redis.port');redisPassword=(& $get 'spring.data.redis.password')}
}
function ConvertTo-IniHex([string]$Value){return -join ($Value.ToCharArray()|ForEach-Object {'{0:x4}' -f [int]$_})}