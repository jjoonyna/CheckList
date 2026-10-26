[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$JavaHome,[Parameter(Mandatory=$true)][string]$JreHome,[Parameter(Mandatory=$true)][string]$WinSW)
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'runtime-support.ps1')
function Assert($value,[string]$message){if(!$value){throw $message}}
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
Assert ([Security.Principal.WindowsPrincipal]::new($identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) '실제 재설치 프로세스 검사는 관리자 권한으로 실행해 주세요.'
$id=[guid]::NewGuid().ToString('N');$serviceName='CheckListReinstallTest'+$id
$base=[IO.Path]::GetFullPath((Join-Path $env:ProgramData ('CheckList reinstall test '+$id)))
$root=Join-Path $base '설치 폴더';$processes=[Collections.Generic.List[Diagnostics.Process]]::new()
New-Item -ItemType Directory -Force -Path $root,(Join-Path $base 'classes') | Out-Null
function Run-Test([string]$File,[string]$Arguments,[string]$Name,[int]$Expected=0){
 $process=Start-Process -FilePath $File -ArgumentList $Arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $base ($Name+'.out')) -RedirectStandardError (Join-Path $base ($Name+'.error'))
 $null=$process.Handle
 try{
  Assert ($process.WaitForExit(60000)) ('시험 명령 시간 초과: '+$Name)
  $process.Refresh();Assert ($process.ExitCode -eq $Expected) ('시험 명령 종료 코드 오류: '+$Name+'='+$process.ExitCode)
 }finally{if(!$process.HasExited){$process.Kill();$process.WaitForExit()};$process.Dispose()}
}
function Start-Java([string]$Executable,[string]$Jar,[string]$Name){
 $process=Start-Process -FilePath $Executable -ArgumentList ('-jar "'+$Jar+'"') -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $base ($Name+'.out')) -RedirectStandardError (Join-Path $base ($Name+'.error'))
 $null=$process.Handle;$processes.Add($process)
 Assert (!$process.WaitForExit(500)) ('시험 Java 실행 실패: '+$Name)
 return $process
}
try{
 Copy-Item -LiteralPath $JreHome -Destination (Join-Path $root 'jre') -Recurse
 foreach($file in @('install-config.ps1','runtime-support.ps1','stop-services.ps1')){
  $text=[IO.File]::ReadAllText((Join-Path $PSScriptRoot $file)).Replace('CheckList',$serviceName)
  [IO.File]::WriteAllText((Join-Path $root $file),$text,[Text.UTF8Encoding]::new($true))
 }
 $javaSource=Join-Path $base 'CheckListProcessProbe.java'
 [IO.File]::WriteAllText($javaSource,'public final class CheckListProcessProbe { public static void main(String[] args) throws Exception { Thread.sleep(600000L); } }')
 Run-Test (Join-Path $JavaHome 'bin/javac.exe') ('-d "'+(Join-Path $base 'classes')+'" "'+$javaSource+'"') 'compile'
 $jar=Join-Path $root 'checklist.jar';$otherJar=Join-Path $root 'other.jar'
 Run-Test (Join-Path $JavaHome 'bin/jar.exe') ('--create --file "'+$jar+'" --main-class CheckListProcessProbe -C "'+(Join-Path $base 'classes')+'" .') 'jar'
 Copy-Item -LiteralPath $jar -Destination $otherJar
 $java=Join-Path $root 'jre/bin/java.exe';$externalJava=Join-Path $JavaHome 'bin/java.exe'
 $powershell=Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
 $arguments='-NoProfile -ExecutionPolicy Bypass -File "'+(Join-Path $root 'stop-services.ps1')+'" -Root "'+$root+'"'
 $wrapper=Join-Path $root 'checklist-service.exe'
 Copy-Item -LiteralPath $WinSW -Destination $wrapper
 $xml='<service><id>'+$serviceName+'</id><name>'+$serviceName+'</name><description>재설치 종료 검사</description><executable>'+[Security.SecurityElement]::Escape($java)+'</executable><arguments>'+[Security.SecurityElement]::Escape('-jar "'+$jar+'"')+'</arguments><logpath>%BASE%\logs</logpath><log mode="roll"/><stoptimeout>2 sec</stoptimeout></service>'
 [IO.File]::WriteAllText((Join-Path $root 'checklist-service.xml'),$xml,[Text.UTF8Encoding]::new($false))
 [IO.File]::WriteAllText((Join-Path $root 'preserved.txt'),'보존 표식')
 Run-Test $wrapper 'install' 'service-install'
 Start-Service -Name $serviceName
 Run-Test $powershell $arguments 'service-stop'
 $service=Get-Service $serviceName;try{Assert ($service.Status -eq 'Stopped') '기존 서비스가 중단되지 않음'}finally{$service.Dispose()}
 Write-Host '실제 서비스·Java 종료 대기 검사 통과'
 $owned=Start-Java $java $jar 'owned'
 $unrelated=Start-Java $externalJava $otherJar 'unrelated'
 Run-Test $powershell $arguments 'orphan-stop'
 Assert ($owned.WaitForExit(3000)) '남은 전용 Java가 종료되지 않음'
 Assert (!$unrelated.HasExited) '다른 Java가 종료됨'
 Copy-Item -LiteralPath (Join-Path $JreHome 'bin/java.exe') -Destination $java -Force
 Write-Host '전용 Java 정리·실행 파일 잠금 해제·다른 Java 보존 검사 통과'
 $ownedAgain=Start-Java $java $jar 'owned-again'
 $differentJar=Start-Java $java $otherJar 'different-jar'
 Run-Test $powershell $arguments 'blocked-jar' 1
 Assert (!$ownedAgain.HasExited -and !$differentJar.HasExited) '미확인 JAR가 있는데 프로세스를 종료함'
 $differentJar.Kill();$differentJar.WaitForExit()
 $ownedAgain.Kill();$ownedAgain.WaitForExit()
 $differentExecutable=Start-Java $externalJava $jar 'different-executable'
 Run-Test $powershell $arguments 'blocked-executable' 1
 Assert (!$differentExecutable.HasExited) '다른 실행 경로의 Java를 종료함'
 $differentExecutable.Kill();$differentExecutable.WaitForExit()
 Assert ([IO.File]::ReadAllText((Join-Path $root 'preserved.txt')) -eq '보존 표식') '기존 파일이 변경됨'
 Assert (Test-InstallJarArgument ('java -jar "'+$jar+'"') $root) '공백·한글 JAR 경로 판정 실패'
 Assert (!(Test-InstallJarArgument 'java -jar checklist.jar' $root)) '상대 경로 JAR를 소유 확인함'
 Assert (!(Test-InstallJarArgument ('java Main -jar "'+$jar+'"') $root)) '업무 인자를 JAR 실행으로 오인함'
 Assert (!(Test-InstallJarArgument ('java -Dnote="-jar '+$jar+'" -jar "'+$otherJar+'"') $root)) '옵션 문자열을 JAR 실행으로 오인함'
 $script:probeRecords=@([pscustomobject]@{ProcessId=999;ExecutablePath=$null;CommandLine=$null})
 function Get-CimInstance {param($ClassName,$Filter,$ErrorAction) $script:probeRecords}
 try{$blocked=$false;try{$null=@(Get-InstallJavaProcesses $root)}catch{$blocked=$true};Assert $blocked '조회 불가 Java를 허용함'}finally{Remove-Item Function:\Get-CimInstance}
 Write-Host '미확인 JAR·실행 경로·조회 불가 차단 및 파일 보존 검사 통과'
}finally{
 foreach($process in $processes){try{if(!$process.HasExited){$process.Kill();$process.WaitForExit()}}finally{$process.Dispose()}}
 $service=Get-Service $serviceName -ErrorAction SilentlyContinue
 if($service){try{if($service.Status -ne 'Stopped'){Stop-Service $serviceName};$service.WaitForStatus([ServiceProcess.ServiceControllerStatus]::Stopped,[TimeSpan]::FromSeconds(20))}finally{$service.Dispose()}; & (Join-Path $env:SystemRoot 'System32/sc.exe') delete $serviceName | Out-Null}
 $archive=Join-Path $repo ('build/installer-test-logs/reinstall-'+$id)
 foreach($file in @(Get-ChildItem -LiteralPath $base -Recurse -File | Where-Object Extension -in @('.log','.out','.error'))){
  $destination=Join-Path $archive $file.FullName.Substring($base.Length+1)
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
  Copy-Item -LiteralPath $file.FullName -Destination $destination
 }
 if((Split-Path -Parent $base) -ne [IO.Path]::GetFullPath($env:ProgramData) -or (Split-Path -Leaf $base) -notmatch '^CheckList reinstall test [a-f0-9]{32}$'){throw '시험 폴더 정리 경로 검증 실패'}
 Remove-Item -LiteralPath $base -Recurse -Force
}
Write-Host '실제 재설치 프로세스 정리 검사 완료'
