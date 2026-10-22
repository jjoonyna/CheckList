[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Java21,[switch]$SkipBuild,[switch]$CompileInstaller,[string]$Version='0.1.0')
$ErrorActionPreference='Stop'
[Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$root=Split-Path -Parent $PSScriptRoot
$cache=Join-Path $root 'tools-cache/deploy';$dist=Join-Path $root 'dist'
$stage=Join-Path $root ('build/deploy-stage-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Force -Path $cache,$dist,$stage | Out-Null
function Get-Verified([string]$File,[string]$Url,[string]$Hash){
 if(!(Test-Path -LiteralPath $File)){Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $File}
 if((Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash -ne $Hash){throw "배포 도구 SHA-256 불일치: $File"}
}
if(!(Test-Path -LiteralPath $Java21)){throw 'Java 21 java.exe를 지정해 주세요.'}
$versionText=& $Java21 --version
if(($versionText -join ' ') -notmatch '(?<!\d)21\.'){throw 'Java 21 실행 파일이 필요합니다.'}
if(!$SkipBuild){
 Push-Location (Join-Path $root 'backend')
 try{
  $jdk=Split-Path -Parent (Split-Path -Parent $Java21)
  & $Java21 "-Dorg.gradle.java.home=$jdk" '-Dorg.gradle.jvmargs=-Dfile.encoding=COMPAT' -classpath gradle/wrapper/gradle-wrapper.jar org.gradle.wrapper.GradleWrapperMain test bootJar --no-daemon --console=plain
  if($LASTEXITCODE -ne 0){throw '앱 테스트·빌드 실패'}
 }finally{Pop-Location}
}
$jar=Get-ChildItem (Join-Path $root 'backend/build/libs') -Filter '*.jar' | Where-Object {$_.Name -notmatch 'plain'} | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if(!$jar){throw '앱 JAR가 없습니다. 먼저 빌드해 주세요.'}
$winsw=Join-Path $cache 'WinSW-2.12.0.exe'
Get-Verified $winsw 'https://github.com/winsw/winsw/releases/download/v2.12.0/WinSW-x64.exe' '05B82D46AD331CC16BDC00DE5C6332C1EF818DF8CEEFCD49C726553209B3A0DA'
$jreZip=Join-Path $cache 'jre-21.0.12.1.zip'
Get-Verified $jreZip 'https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.12.1%2B1/OpenJDK21U-jre_x64_windows_hotspot_21.0.12.1_1.zip' 'D35F31E712F0FCF6AC5A093EDC90204FBFF22F720BA3950BD09D331D5E621636'
$pgJar=Join-Path $cache 'postgresql-18.6-windows.jar'
if(!(Test-Path -LiteralPath $pgJar)){
 $candidates=@((Join-Path $root 'backend/.gradle-user-home/caches/modules-2/files-2.1/io.zonky.test.postgres/embedded-postgres-binaries-windows-amd64/18.6.0'),(Join-Path $env:USERPROFILE '.gradle/caches/modules-2/files-2.1/io.zonky.test.postgres/embedded-postgres-binaries-windows-amd64/18.6.0'))
 $cached=$candidates|Where-Object {Test-Path -LiteralPath $_}|ForEach-Object {Get-ChildItem -LiteralPath $_ -Recurse -Filter '*.jar'}|Select-Object -First 1
 if($cached){Copy-Item -LiteralPath $cached.FullName -Destination $pgJar}
}
Get-Verified $pgJar 'https://repo.maven.apache.org/maven2/io/zonky/test/postgres/embedded-postgres-binaries-windows-amd64/18.6.0/embedded-postgres-binaries-windows-amd64-18.6.0.jar' 'b7ef2d03588e0439f0d0a2250f43905f7464f1e96ace47703ceaf79094198150'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$txz=Join-Path $stage 'postgres.txz'
$archive=[IO.Compression.ZipFile]::OpenRead($pgJar)
try{$entry=$archive.GetEntry('postgres-windows-x86_64.txz');if(!$entry){throw 'PostgreSQL 바이너리 항목이 없습니다.'};[IO.Compression.ZipFileExtensions]::ExtractToFile($entry,$txz,$false)}finally{$archive.Dispose()}
$pg=Join-Path $stage 'postgresql';New-Item -ItemType Directory -Force -Path $pg | Out-Null
& tar.exe -xf $txz -C $pg
if($LASTEXITCODE -ne 0 -or !(Test-Path -LiteralPath (Join-Path $pg 'bin/initdb.exe'))){throw 'PostgreSQL 압축 구조 또는 추출 오류'}
Remove-Item -LiteralPath $txz -Force
Invoke-WebRequest -UseBasicParsing -Uri 'https://raw.githubusercontent.com/postgres/postgres/REL_18_STABLE/COPYRIGHT' -OutFile (Join-Path $pg 'LICENSE.txt')
$jreExtract=Join-Path $stage 'jre-extract';Expand-Archive -LiteralPath $jreZip -DestinationPath $jreExtract
$jreRoot=Get-ChildItem -LiteralPath $jreExtract -Directory | Where-Object {Test-Path -LiteralPath (Join-Path $_.FullName 'bin/java.exe')} | Select-Object -First 1
if(!$jreRoot){throw 'JRE 압축 구조 오류'}
$jre=Join-Path $stage 'jre';New-Item -ItemType Directory -Force -Path $jre | Out-Null
Get-ChildItem -LiteralPath $jreRoot.FullName -Force | Copy-Item -Destination $jre -Recurse
# 압축을 푼 임시 JRE 폴더는 배포에 포함하지 않는다. 원본 추출 캐시는 별도로 보존한다.
$extractCache=Join-Path $cache ('jre-extract-'+(Get-Date -Format 'yyyyMMddHHmmss'))
$resolvedStage=[IO.Path]::GetFullPath($stage);$resolvedExtract=[IO.Path]::GetFullPath($jreExtract);$resolvedCache=[IO.Path]::GetFullPath($extractCache)
if(!$resolvedExtract.StartsWith($resolvedStage+[IO.Path]::DirectorySeparatorChar) -or !$resolvedCache.StartsWith([IO.Path]::GetFullPath($cache)+[IO.Path]::DirectorySeparatorChar)){throw '추출 폴더 이동 범위 오류'}
Move-Item -LiteralPath $jreExtract -Destination $extractCache
Copy-Item -LiteralPath $jar.FullName -Destination (Join-Path $stage 'checklist.jar')
Copy-Item -LiteralPath $winsw -Destination (Join-Path $stage 'checklist-service.exe')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'install-runtime.ps1'),(Join-Path $PSScriptRoot 'checklist-service.xml') -Destination $stage
$notices=Join-Path $stage 'licenses';New-Item -ItemType Directory -Force -Path $notices | Out-Null
Invoke-WebRequest -UseBasicParsing -Uri 'https://raw.githubusercontent.com/winsw/winsw/v2.12.0/LICENSE.txt' -OutFile (Join-Path $notices 'WinSW-2.12.0.txt')
Invoke-WebRequest -UseBasicParsing -Uri 'https://raw.githubusercontent.com/jrsoftware/issrc/is-6_7_3/license.txt' -OutFile (Join-Path $notices 'Inno-Setup-6.7.3.txt')
$notice=@"
CheckList 설치 구성요소 안내
WinSW 2.12.0: MIT, licenses/WinSW-2.12.0.txt, https://github.com/winsw/winsw
PostgreSQL 18.6: PostgreSQL License, postgresql/LICENSE.txt, https://www.postgresql.org/
Eclipse Temurin JRE 21: jre/legal 및 jre/NOTICE, https://adoptium.net/
Inno Setup 6.7.3: 설치 파일 생성 도구, licenses/Inno-Setup-6.7.3.txt, https://jrsoftware.org/isinfo.php
앱 라이브러리의 원문 고지는 JAR 내부 META-INF 및 프론트 dist/assets/*.LICENSE.txt에 포함된 범위를 보존합니다.
"@
[IO.File]::WriteAllText((Join-Path $stage 'THIRD-PARTY-NOTICES.txt'),$notice,[Text.UTF8Encoding]::new($true))
if($CompileInstaller){
 $innoInstaller=Join-Path $cache 'innosetup-6.7.3.exe'
 Get-Verified $innoInstaller 'https://github.com/jrsoftware/issrc/releases/download/is-6_7_3/innosetup-6.7.3.exe' '9C73C3BAE7ED48D44112A0F48E66742C00090BDB5BEF71D9D3C056C66E97B732'
 $inno=Join-Path $cache 'inno-6.7.3'
 if(!(Test-Path -LiteralPath (Join-Path $inno 'ISCC.exe'))){
  $arguments='/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /CURRENTUSER /PORTABLE=1 /DIR="'+$inno+'"'
  $process=Start-Process -FilePath $innoInstaller -ArgumentList $arguments -WindowStyle Hidden -Wait -PassThru
  if($process.ExitCode -ne 0){throw 'Inno Setup 포터블 준비 실패'}
 }
 & (Join-Path $inno 'ISCC.exe') "/DAppVersion=$Version" "/DStageDir=$stage" "/DOutputDir=$dist" (Join-Path $root 'installer/checklist.iss')
 if($LASTEXITCODE -ne 0){throw 'Windows 설치 파일 컴파일 실패'}
}
Write-Output "앱·JRE·PostgreSQL 스테이징 완료: $stage"
Write-Output "설치 파일 출력 위치: $dist"