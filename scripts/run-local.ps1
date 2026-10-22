[CmdletBinding()]
param([string]$Java21='C:\Program Files\Java\jdk-21\bin\java.exe',[switch]$Build)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
if(!(Test-Path -LiteralPath $Java21)){throw 'Java 21 실행 파일 경로를 -Java21로 지정해 주세요.'}
& (Join-Path $PSScriptRoot 'local-runtime.ps1') -Action start
Push-Location (Join-Path $root 'backend')
try{
 $jar=Get-ChildItem build/libs -Filter '*.jar' -ErrorAction SilentlyContinue | Where-Object {$_.Name -notmatch 'plain'} | Sort-Object LastWriteTime -Descending | Select-Object -First 1
 if($Build -or !$jar){
  $jdk=Split-Path -Parent (Split-Path -Parent $Java21)
  & $Java21 "-Dorg.gradle.java.home=$jdk" '-Dorg.gradle.jvmargs=-Dfile.encoding=COMPAT' -classpath gradle/wrapper/gradle-wrapper.jar org.gradle.wrapper.GradleWrapperMain bootJar --no-daemon --console=plain
  if($LASTEXITCODE -ne 0){throw '앱 빌드 실패'}
  $jar=Get-ChildItem build/libs -Filter '*.jar' | Where-Object {$_.Name -notmatch 'plain'} | Sort-Object LastWriteTime -Descending | Select-Object -First 1
 }
 Write-Host '체크리스트: http://localhost:8383 (종료: Ctrl+C)'
 & $Java21 -jar $jar.FullName --spring.profiles.active=local
}finally{Pop-Location}