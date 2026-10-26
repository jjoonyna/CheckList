[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Java21,[switch]$SkipBuild,[switch]$CompileInstaller,[string]$Version='0.0.4')
$ErrorActionPreference='Stop'
[Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$root=Split-Path -Parent $PSScriptRoot
$cache=Join-Path $root 'tools-cache/deploy';$dist=Join-Path $root 'dist'
$stage=Join-Path $root ('build/deploy-stage-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Force -Path $cache,$dist,$stage | Out-Null
. (Join-Path $PSScriptRoot 'package-support.ps1')
$script:PackageLogDirectory=Join-Path $cache ('logs/'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Force -Path $script:PackageLogDirectory | Out-Null
Start-Transcript -Path (Join-Path $script:PackageLogDirectory 'package.log') | Out-Null
try{
Write-PackageLog "패키징 시작: 버전=$Version, 진단 로그=$script:PackageLogDirectory"
Start-PackageStage 'Java 21 확인'
if(!(Test-Path -LiteralPath $Java21)){throw 'Java 21 java.exe를 지정해 주세요.'}
$javaCheck=Invoke-PackageProcess -Name 'Java 버전 확인' -FilePath $Java21 -Arguments '--version' -TimeoutSeconds 30
$versionText=Get-Content -LiteralPath $javaCheck.OutputLog
if(($versionText -join ' ') -notmatch '(?<!\d)21\.'){throw 'Java 21 실행 파일이 필요합니다.'}
if(!$SkipBuild){
 Start-PackageStage '프론트·백엔드 테스트 및 JAR 빌드'
 Push-Location (Join-Path $root 'backend')
 try{
  $jdk=Split-Path -Parent (Split-Path -Parent $Java21)
  $gradleArguments='"-Dorg.gradle.java.home='+$jdk+'" "-Dorg.gradle.jvmargs=-Dfile.encoding=COMPAT" -classpath gradle/wrapper/gradle-wrapper.jar org.gradle.wrapper.GradleWrapperMain test bootJar --no-daemon --console=plain'
  Invoke-PackageProcess -Name '앱 테스트·빌드' -FilePath $Java21 -Arguments $gradleArguments -TimeoutSeconds 1200 | Out-Null
 }finally{Pop-Location}
}
$jar=Get-Item -LiteralPath (Join-Path $root ("backend/build/libs/checklist-$Version.jar")) -ErrorAction SilentlyContinue
if(!$jar){throw '앱 JAR가 없습니다. 먼저 빌드해 주세요.'}
Start-PackageStage 'WinSW·JRE·PostgreSQL 다운로드 및 해시 검증'
$winsw=Join-Path $cache 'WinSW-2.12.0.exe'
Get-PackageDownload $winsw 'https://github.com/winsw/winsw/releases/download/v2.12.0/WinSW-x64.exe' '05B82D46AD331CC16BDC00DE5C6332C1EF818DF8CEEFCD49C726553209B3A0DA'
$jreZip=Join-Path $cache 'jre-21.0.12.1.zip'
Get-PackageDownload $jreZip 'https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.12.1%2B1/OpenJDK21U-jre_x64_windows_hotspot_21.0.12.1_1.zip' 'D35F31E712F0FCF6AC5A093EDC90204FBFF22F720BA3950BD09D331D5E621636'
$pgJar=Join-Path $cache 'postgresql-18.6-windows.jar'
if(!(Test-Path -LiteralPath $pgJar)){
 $candidates=@((Join-Path $root 'backend/.gradle-user-home/caches/modules-2/files-2.1/io.zonky.test.postgres/embedded-postgres-binaries-windows-amd64/18.6.0'),(Join-Path $env:USERPROFILE '.gradle/caches/modules-2/files-2.1/io.zonky.test.postgres/embedded-postgres-binaries-windows-amd64/18.6.0'))
 $cached=$candidates|Where-Object {Test-Path -LiteralPath $_}|ForEach-Object {Get-ChildItem -LiteralPath $_ -Recurse -Filter '*.jar'}|Select-Object -First 1
 if($cached){Copy-Item -LiteralPath $cached.FullName -Destination $pgJar}
}
Get-PackageDownload $pgJar 'https://repo.maven.apache.org/maven2/io/zonky/test/postgres/embedded-postgres-binaries-windows-amd64/18.6.0/embedded-postgres-binaries-windows-amd64-18.6.0.jar' 'b7ef2d03588e0439f0d0a2250f43905f7464f1e96ace47703ceaf79094198150'
Start-PackageStage 'PostgreSQL 압축 해제'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$txz=Join-Path $stage 'postgres.txz'
$archive=[IO.Compression.ZipFile]::OpenRead($pgJar)
try{$entry=$archive.GetEntry('postgres-windows-x86_64.txz');if(!$entry){throw 'PostgreSQL 바이너리 항목이 없습니다.'};[IO.Compression.ZipFileExtensions]::ExtractToFile($entry,$txz,$false)}finally{$archive.Dispose()}
$pg=Join-Path $stage 'postgresql';New-Item -ItemType Directory -Force -Path $pg | Out-Null
Expand-PackagePostgres -Archive $txz -Destination $pg -WorkDirectory (Join-Path $stage 'postgres-tar')
Remove-Item -LiteralPath $txz -Force
# 큰 중간 TAR 파일은 스테이징 밖 캐시에 보관해 설치 파일에 포함되지 않게 한다.
$tarCache=Join-Path $cache ('postgres-tar-'+(Get-Date -Format 'yyyyMMddHHmmss'))
$tarSource=[IO.Path]::GetFullPath((Join-Path $stage 'postgres-tar'))
if(!$tarSource.StartsWith([IO.Path]::GetFullPath($stage)+[IO.Path]::DirectorySeparatorChar) -or ![IO.Path]::GetFullPath($tarCache).StartsWith([IO.Path]::GetFullPath($cache)+[IO.Path]::DirectorySeparatorChar)){throw '중간 TAR 이동 범위 오류'}
Move-Item -LiteralPath $tarSource -Destination $tarCache
Get-PackageDownload -Url 'https://raw.githubusercontent.com/postgres/postgres/REL_18_STABLE/COPYRIGHT' -File (Join-Path $pg 'LICENSE.txt')
Start-PackageStage 'JRE 압축 해제 및 복사'
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
Start-PackageStage 'Redis 다운로드 및 압축 해제'
$redisZip=Join-Path $cache 'Redis-8.10.2-Windows-x64-cygwin.zip'
Get-PackageDownload $redisZip 'https://github.com/redis-windows/redis-windows/releases/download/8.10.2/Redis-8.10.2-Windows-x64-cygwin.zip' '6de5cc7f5adbf97b5928b13766383d4ad424626ef3d8b313ffff12d820ec6fc1'
$redisExtract=Join-Path $cache ('redis-extract-'+(Get-Date -Format 'yyyyMMddHHmmss'))
Expand-Archive -LiteralPath $redisZip -DestinationPath $redisExtract
$redisServer=Get-ChildItem -LiteralPath $redisExtract -Recurse -Filter 'redis-server.exe' | Select-Object -First 1
if(!$redisServer){throw 'Redis 아카이브에 실행 파일이 없습니다.'}
$redisHome=Join-Path $stage 'redis';New-Item -ItemType Directory -Force -Path $redisHome | Out-Null
Get-ChildItem -LiteralPath $redisServer.Directory.FullName -Force | Copy-Item -Destination $redisHome -Recurse
Start-PackageStage '앱·서비스·라이선스 스테이징'
Copy-Item -LiteralPath $jar.FullName -Destination (Join-Path $stage 'checklist.jar')
Copy-Item -LiteralPath $winsw -Destination (Join-Path $stage 'checklist-service.exe')
Copy-Item -LiteralPath $winsw -Destination (Join-Path $stage 'redis-service.exe')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'install-runtime.ps1'),(Join-Path $PSScriptRoot 'install-config.ps1'),(Join-Path $PSScriptRoot 'runtime-support.ps1'),(Join-Path $PSScriptRoot 'detect-services.ps1'),(Join-Path $PSScriptRoot 'stop-services.ps1'),(Join-Path $PSScriptRoot 'stop-checklist.ps1'),(Join-Path $PSScriptRoot 'checklist-service.xml') -Destination $stage
$notices=Join-Path $stage 'licenses';New-Item -ItemType Directory -Force -Path $notices | Out-Null
Get-PackageDownload -Url 'https://raw.githubusercontent.com/winsw/winsw/v2.12.0/LICENSE.txt' -File (Join-Path $notices 'WinSW-2.12.0.txt')
Get-PackageDownload -Url 'https://raw.githubusercontent.com/jrsoftware/issrc/is-6_7_3/license.txt' -File (Join-Path $notices 'Inno-Setup-6.7.3.txt')
Get-PackageDownload -Url 'https://raw.githubusercontent.com/redis/redis/8.10.2/LICENSE.txt' -File (Join-Path $notices 'Redis-8.10.2.txt')
Get-PackageDownload -Url 'https://raw.githubusercontent.com/redis-windows/redis-windows/8.10.2/LICENSE' -File (Join-Path $notices 'Redis-Windows-8.10.2.txt')
Get-PackageDownload -Url 'https://cygwin.com/COPYING.LIB' -File (Join-Path $notices 'Cygwin-LGPLv3.txt')
Get-PackageDownload -Url 'https://cygwin.com/COPYING' -File (Join-Path $notices 'Cygwin-GPLv3.txt')
Get-PackageDownload -Url 'https://raw.githubusercontent.com/openssl/openssl/openssl-3.5.8/LICENSE.txt' -File (Join-Path $notices 'OpenSSL-3.5.8.txt')
Get-PackageDownload -Url 'https://raw.githubusercontent.com/gcc-mirror/gcc/releases/gcc-14.4.0/COPYING.RUNTIME' -File (Join-Path $notices 'GCC-14.4.0-Runtime-Exception.txt')
Get-PackageDownload -Url 'https://raw.githubusercontent.com/gcc-mirror/gcc/releases/gcc-14.4.0/COPYING3' -File (Join-Path $notices 'GCC-14.4.0-GPLv3.txt')
Get-PackageDownload -Url 'https://www.gnu.org/licenses/old-licenses/lgpl-2.1.txt' -File (Join-Path $notices 'libiconv-libintl-LGPLv2.1.txt')
Get-PackageDownload -Url 'https://raw.githubusercontent.com/madler/zlib/v1.3.2/zlib.h' -File (Join-Path $notices 'zlib-1.3.2-license-and-header.txt')
$redisSources=@"
Redis 8.10.2 원문 소스: https://github.com/redis/redis/archive/refs/tags/8.10.2.tar.gz
Windows 빌드 소스·빌드 스크립트: https://github.com/redis-windows/redis-windows/archive/refs/tags/8.10.2.zip
Windows 바이너리: https://github.com/redis-windows/redis-windows/releases/tag/8.10.2
Cygwin 3.6.10 DLL 소스: https://cygwin.com/git/?p=newlib-cygwin.git;a=tag;h=refs/tags/cygwin-3_6_10-release
Cygwin 연결 예외 및 라이선스: https://cygwin.com/licensing.html
OpenSSL3.5.8 소스: https://github.com/openssl/openssl/archive/refs/tags/openssl-3.5.8.tar.gz
GCC14.4.0 소스: https://gcc.gnu.org/pub/gcc/releases/gcc-14.4.0/
libiconv1.19 소스: https://ftp.gnu.org/gnu/libiconv/libiconv-1.19.tar.gz
gettext0.22.5 소스: https://ftp.gnu.org/gnu/gettext/gettext-0.22.5.tar.gz
zlib1.3.2 소스: https://github.com/madler/zlib/archive/refs/tags/v1.3.2.tar.gz
Cygwin 의존 패키지 소스 배포: https://mirrors.kernel.org/sourceware/cygwin/x86_64/release/
포함 라이브러리: Cygwin3.6.10, OpenSSL3.5.8, libiconv1.19, gettext0.22.5, zlib1.3.2, GCC14.4.0 libgcc·libstdc++.
Redis는 변경하지 않은 별도 서버 프로세스로 제공하며 CheckList는 TCP로 연결합니다.
"@
[IO.File]::WriteAllText((Join-Path $notices 'Redis-SOURCES.txt'),$redisSources,[Text.UTF8Encoding]::new($true))
$notice=@"
CheckList 설치 구성요소 안내
Redis 8.10.2 Windows 커뮤니티 빌드: licenses/Redis-8.10.2.txt·Redis-Windows-8.10.2.txt·Redis-SOURCES.txt
Cygwin과 동봉 라이브러리: licenses/Cygwin-LGPLv3.txt·Cygwin-GPLv3.txt, 원본 Redis README 보존
WinSW 2.12.0: MIT, licenses/WinSW-2.12.0.txt, https://github.com/winsw/winsw
PostgreSQL 18.6: PostgreSQL License, postgresql/LICENSE.txt, https://www.postgresql.org/
Eclipse Temurin JRE 21: jre/legal 및 jre/NOTICE, https://adoptium.net/
Inno Setup 6.7.3: 설치 파일 생성 도구, licenses/Inno-Setup-6.7.3.txt, https://jrsoftware.org/isinfo.php
앱 라이브러리의 원문 고지는 JAR 내부 META-INF 및 프론트 dist/assets/*.LICENSE.txt에 포함된 범위를 보존합니다.
"@
[IO.File]::WriteAllText((Join-Path $stage 'THIRD-PARTY-NOTICES.txt'),$notice,[Text.UTF8Encoding]::new($true))
if($CompileInstaller){
 Start-PackageStage 'Inno Setup 준비'
 $innoInstaller=Join-Path $cache 'innosetup-6.7.3.exe'
 Get-PackageDownload $innoInstaller 'https://github.com/jrsoftware/issrc/releases/download/is-6_7_3/innosetup-6.7.3.exe' '9C73C3BAE7ED48D44112A0F48E66742C00090BDB5BEF71D9D3C056C66E97B732'
 $inno=Join-Path $cache 'inno-6.7.3'
 if(!(Test-Path -LiteralPath (Join-Path $inno 'ISCC.exe'))){
  $arguments='/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /CURRENTUSER /PORTABLE=1 /DIR="'+$inno+'"'
  $arguments+=' /LOG="'+(Join-Path $script:PackageLogDirectory 'inno-setup.log')+'"'
  Invoke-PackageProcess -Name 'Inno Setup 포터블 설치' -FilePath $innoInstaller -Arguments $arguments -TimeoutSeconds 120 | Out-Null
 }
 Start-PackageStage 'Windows 설치 EXE 컴파일'
 $compilerArguments='"/DAppVersion='+$Version+'" "/DStageDir='+$stage+'" "/DOutputDir='+$dist+'" "'+(Join-Path $root 'installer/checklist.iss')+'"'
 Invoke-PackageProcess -Name 'ISCC 설치 파일 컴파일' -FilePath (Join-Path $inno 'ISCC.exe') -Arguments $compilerArguments -TimeoutSeconds 600 | Out-Null
}
Write-Output "앱·JRE·PostgreSQL 스테이징 완료: $stage"
Write-Output "설치 파일 출력 위치: $dist"
Complete-PackageStage
Write-PackageLog '전체 패키징 완료'
}catch{
 Write-PackageLog "패키징 실패: 단계=$script:PackageStageName, 원인=$($_.Exception.Message), 진단 로그=$script:PackageLogDirectory"
 throw
}finally{
 Stop-Transcript | Out-Null
}
