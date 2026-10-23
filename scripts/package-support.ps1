function Write-PackageLog([string]$Message){
 Write-Host ('[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$Message)
}

function Invoke-PackageStep([string]$StepName,[scriptblock]$Action){
 $watch=[Diagnostics.Stopwatch]::StartNew()
 Write-PackageLog "시작: $StepName"
 try{
  & $Action
  Write-PackageLog ('완료: {0} ({1:N1}초)' -f $StepName,$watch.Elapsed.TotalSeconds)
 }catch{
  Write-PackageLog ('실패: {0} ({1:N1}초) 원인: {2}' -f $StepName,$watch.Elapsed.TotalSeconds,$_.Exception.Message)
  throw
 }
}

function Invoke-PackageProcess {
 param([string]$Name,[string]$FilePath,[string]$Arguments,[int]$TimeoutSeconds=300,[int]$HeartbeatSeconds=15,[string]$WorkingDirectory=(Get-Location).Path)
 if($TimeoutSeconds -lt 1 -or $HeartbeatSeconds -lt 1){throw '프로세스 제한 시간은 1초 이상이어야 합니다.'}
 $safeName=$Name -replace '[^\p{L}\p{N}._-]','-'
 $prefix=Join-Path $script:PackageLogDirectory ($safeName+'-'+[guid]::NewGuid().ToString('N'))
 $stdout=$prefix+'.stdout.log';$stderr=$prefix+'.stderr.log'
 $seen=@{Out=0;Err=0}
 function Show-NewOutput {
  foreach($entry in @(@('Out',$stdout),@('Err',$stderr))){
   if(Test-Path -LiteralPath $entry[1]){
    $lines=@(Get-Content -LiteralPath $entry[1] -Encoding UTF8)
    $lines | Select-Object -Skip $seen[$entry[0]] | ForEach-Object {Write-Host $_}
    $seen[$entry[0]]=$lines.Count
   }
  }
 }
 $watch=[Diagnostics.Stopwatch]::StartNew();$nextHeartbeat=$HeartbeatSeconds
 Write-PackageLog "프로세스 시작: $Name, 실행 파일=$FilePath, 제한=${TimeoutSeconds}초"
 $process=Start-Process -FilePath $FilePath -ArgumentList $Arguments -WorkingDirectory $WorkingDirectory -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
 $null=$process.Handle
 try{
  while(!$process.WaitForExit(200)){
   Show-NewOutput
   if($watch.Elapsed.TotalSeconds -ge $TimeoutSeconds){
    Write-PackageLog "시간 제한: $Name, PID=$($process.Id), 제한=${TimeoutSeconds}초"
    throw "$Name 시간 제한 ${TimeoutSeconds}초 초과. 진단 로그: $prefix"
   }
   if($watch.Elapsed.TotalSeconds -ge $nextHeartbeat){
    $process.Refresh()
    Write-PackageLog ('진행 중: {0}, PID={1}, 경과={2:N1}초, CPU={3:N1}초' -f $Name,$process.Id,$watch.Elapsed.TotalSeconds,$process.TotalProcessorTime.TotalSeconds)
    $nextHeartbeat=$watch.Elapsed.TotalSeconds+$HeartbeatSeconds
   }
  }
  Show-NewOutput
  $process.Refresh()
  if($process.ExitCode -ne 0){throw "$Name 실패: 종료 코드 $($process.ExitCode). 진단 로그: $prefix"}
  Write-PackageLog ('프로세스 완료: {0}, 종료 코드 0, {1:N1}초' -f $Name,$watch.Elapsed.TotalSeconds)
  return [pscustomobject]@{OutputLog=$stdout;ErrorLog=$stderr;ExitCode=$process.ExitCode}
 }finally{
  if(!$process.HasExited){
   # 이 함수가 시작한 프로세스와 그 자식만 종료한다.
   if($PSVersionTable.PSEdition -eq 'Core'){$process.Kill($true)}
   else{& "$env:SystemRoot\System32\taskkill.exe" /PID $process.Id /T /F | Out-Host}
   $null=$process.WaitForExit(5000)
  }
  Show-NewOutput
  $process.Dispose()
 }
}

function Get-PackageDownload {
 param([string]$File,[string]$Url,[string]$Hash,[int]$TimeoutSeconds=180)
 $name=Split-Path -Leaf $File
 Invoke-PackageStep "다운로드·검증 $name" {
  if(!(Test-Path -LiteralPath $File)){
   $partial=$File+'.partial'
   Write-PackageLog "다운로드 주소: $Url"
   try{
    $curl=(Get-Command curl.exe -ErrorAction Stop).Source
    # 전송별 제한 외에 외부 프로세스 전체에도 제한을 둔다. 실패한 파일은 캐시로 승격하지 않는다.
    $arguments='--fail --location --silent --show-error --connect-timeout 20 --max-time '+$TimeoutSeconds+' --retry 1 --retry-max-time '+($TimeoutSeconds*2)+' --output "'+$partial+'" "'+$Url+'"'
    Invoke-PackageProcess -Name "다운로드 $name" -FilePath $curl -Arguments $arguments -TimeoutSeconds ($TimeoutSeconds*2+30) | Out-Null
    if($Hash -and (Get-FileHash -LiteralPath $partial -Algorithm SHA256).Hash -ne $Hash){throw "배포 도구 SHA-256 불일치: $name"}
    Move-Item -LiteralPath $partial -Destination $File -Force
   }finally{
    if(Test-Path -LiteralPath $partial){Remove-Item -LiteralPath $partial -Force}
   }
  }else{Write-PackageLog "캐시 사용: $File"}
  $size=(Get-Item -LiteralPath $File).Length
  Write-PackageLog "파일 준비: $name, ${size}바이트"
  if($Hash -and (Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash -ne $Hash){throw "배포 도구 SHA-256 불일치: $name"}
  if($Hash){Write-PackageLog "SHA-256 일치: $name"}
 }
}
function Start-PackageStage([string]$StageName){
 Complete-PackageStage
 $script:PackageStageName=$StageName
 $script:PackageStageWatch=[Diagnostics.Stopwatch]::StartNew()
 Write-PackageLog "단계 시작: $StageName"
}
function Complete-PackageStage {
 if($script:PackageStageName){
  Write-PackageLog ('단계 완료: {0} ({1:N1}초)' -f $script:PackageStageName,$script:PackageStageWatch.Elapsed.TotalSeconds)
  $script:PackageStageName=$null
 }
}