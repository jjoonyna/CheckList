param([Parameter(Mandatory=$true)][string]$ServerPath)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'install-config.ps1')
$directory=Join-Path $PSScriptRoot ('../build/redis bundle test '+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $directory | Out-Null
$listener=New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback,0);$listener.Start();$port=$listener.LocalEndpoint.Port;$listener.Stop()
$password='테스트 !"\'+(New-InstallSecret)
$config=Join-Path $directory 'redis.conf'
$lines=@('bind 127.0.0.1',('port '+$port),'protected-mode yes',('dir '+(Escape-RedisValue (ConvertTo-CygwinPath $directory))),'save ""','appendonly no',('requirepass '+(Escape-RedisValue $password)))
[IO.File]::WriteAllText($config,($lines -join "`r`n"),[Text.UTF8Encoding]::new($false))
$process=Start-Process -FilePath $ServerPath -ArgumentList ('"'+(ConvertTo-CygwinPath $config)+'"') -WorkingDirectory $directory -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $directory 'redis.out.log') -RedirectStandardError (Join-Path $directory 'redis.error.log')
try{
 $ready=$false
 for($attempt=0;$attempt -lt 30;$attempt++){
  if($process.HasExited){throw '번들 Redis가 시작 직후 종료됐습니다.'}
  try{Test-RedisConnection '127.0.0.1' $port $password;$ready=$true;break}catch{Start-Sleep -Milliseconds 200}
 }
 if(!$ready){throw '번들 Redis AUTH/PING 실패'}
 $failed=$false;try{Test-RedisConnection '127.0.0.1' $port 'wrong-test-password'}catch{$failed=$true}
 if(!$failed){throw '잘못된 Redis 비밀번호를 허용함'}
 $found=Get-LocalEndpoints
 if(!(@($found.Redis)|Where-Object {$_.Port -eq $port})){throw '실제 Redis 수신 포트 자동 탐지 실패'}
 Write-Host '번들 Redis 실행·한글/특수문자 비밀번호 AUTH/PING·오인증 거절·실제 포트 탐지 통과'
}finally{
 if(!$process.HasExited){$process.Kill();$null=$process.WaitForExit(5000)}
 $process.Dispose()
}