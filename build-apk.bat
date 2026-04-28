@echo off
title SecureChat v4 - Offline Build
cd /d "%~dp0"

echo.
echo ========================================
echo   SecureChat v4 - Offline APK Build
echo ========================================
echo.

REM ========================================
REM 1. JAVA KONTROLU
REM ========================================
echo [1/4] Java kontrol ediliyor...
java -version >nul 2>&1
if %errorlevel% neq 0 (
    echo HATA: Java JDK bulunamadi! JDK 17+ gerekli.
    echo Indir: https://adoptium.net/temurin/releases/?version=17
    goto :END
)
echo OK: Java kurulu
echo.

REM ========================================
REM 2. ANDROID SDK KONTROLU
REM ========================================
echo [2/4] Android SDK kontrol ediliyor...

set "SDK_DIR="
if exist "C:\android-sdk\platforms\android-34\android.jar" set "SDK_DIR=C:\android-sdk"
if "%SDK_DIR%"=="" if exist "%LOCALAPPDATA%\Android\Sdk\platforms\android-34\android.jar" set "SDK_DIR=%LOCALAPPDATA%\Android\Sdk"
if "%SDK_DIR%"=="" if exist "%USERPROFILE%\AppData\Local\Android\Sdk\platforms\android-34\android.jar" set "SDK_DIR=%USERPROFILE%\AppData\Local\Android\Sdk"
if "%SDK_DIR%"=="" if exist "D:\android-sdk\platforms\android-34\android.jar" set "SDK_DIR=D:\android-sdk"

if "%SDK_DIR%"=="" (
    echo HATA: Android SDK bulunamadi!
    echo Aranan konumlar:
    echo   - C:\android-sdk
    echo   - %LOCALAPPDATA%\Android\Sdk
    echo   - D:\android-sdk
    goto :END
)
echo OK: SDK bulundu: %SDK_DIR%
set "ANDROID_HOME=%SDK_DIR%"
set "ANDROID_SDK_ROOT=%SDK_DIR%"
set "PATH=%SDK_DIR%\platform-tools;%SDK_DIR%\cmdline-tools\latest\bin;%SDK_DIR%\build-tools\34.0.0;%PATH%"
echo.

REM ========================================
REM 3. GRADLE CACHE AYARLAMA
REM ========================================
echo [3/4] Gradle cache ayarlaniyor...

set "SCRIPT_DIR=%~dp0"
set "CACHE_SRC=%SCRIPT_DIR%gradle-cache"
set "GRADLE_HOME=%USERPROFILE%\.gradle"
set "CACHE_DEST=%GRADLE_HOME%\caches\modules-2"

if not exist "%GRADLE_HOME%\caches" mkdir "%GRADLE_HOME%\caches" 2>nul

REM Eski modules-2 varsa kaldir
if exist "%CACHE_DEST%" rmdir "%CACHE_DEST%" 2>nul
if exist "%CACHE_DEST%" rmdir /S /Q "%CACHE_DEST%" 2>nul

REM Junction olustur
mklink /J "%CACHE_DEST%" "%CACHE_SRC%" >nul 2>&1
if %errorlevel% equ 0 (
    echo OK: Cache junction baglandi
) else (
    echo Junction olusturulamadi, kopyalaniyor...
    xcopy "%CACHE_SRC%\*" "%CACHE_DEST%\" /E /Y /Q /H >nul 2>&1
    echo OK: Cache kopyalandi
)
echo.

REM ========================================
REM 4. BUILD
REM ========================================
echo [4/4] APK Build basliyor...
echo.

cd /d "%SCRIPT_DIR%securechat"

REM local.properties olustur (SDK + Release signing)
REM Properties dosyasinda backslash escape karakteri, forward slash kulllanilmali
set "SDK_ESCAPED=%SDK_DIR:\=/%"
set "KEYSTORE_PATH=%SCRIPT_DIR:\=/%securechat.keystore"
echo sdk.dir=%SDK_ESCAPED%> local.properties
echo RELEASE_STORE_FILE=%KEYSTORE_PATH%>> local.properties
echo RELEASE_STORE_PASSWORD=securechat123>> local.properties
echo RELEASE_KEY_ALIAS=securechat>> local.properties
echo RELEASE_KEY_PASSWORD=securechat123>> local.properties

REM Eski build temizle
if exist "app\build\outputs" rmdir /S /Q "app\build\outputs" 2>nul
if exist ".gradle" rmdir /S /Q ".gradle" 2>nul

REM ----------------------------------------
REM  Debug Build
REM ----------------------------------------
echo ----------------------------------------
echo  Dev Debug APK
echo ----------------------------------------
echo.

call gradlew.bat assembleDevDebug --offline --no-daemon --no-configuration-cache
if %errorlevel% neq 0 (
    echo.
    echo Offline basarisiz, online deneniyor...
    call gradlew.bat assembleDevDebug --no-daemon --no-configuration-cache
)

REM ----------------------------------------
REM  Release Build
REM ----------------------------------------
echo.
echo ----------------------------------------
echo  Dev Release APK
echo ----------------------------------------
echo.

call gradlew.bat assembleDevRelease --offline --no-daemon --no-configuration-cache
if %errorlevel% neq 0 (
    echo.
    echo Offline basarisiz, online deneniyor...
    call gradlew.bat assembleDevRelease --no-daemon --no-configuration-cache
)

REM ========================================
REM  SONUC
REM ========================================
echo.
echo ========================================

set "BUILD_OK=0"

if exist "app\build\outputs\apk\dev\debug\app-dev-debug.apk" (
    set "BUILD_OK=1"
    copy "app\build\outputs\apk\dev\debug\app-dev-debug.apk" "%SCRIPT_DIR%\SecureChat_v4_Debug.apk" >nul 2>&1
    echo  [OK] Debug APK:   SecureChat_v4_Debug.apk
)

if exist "app\build\outputs\apk\dev\release\app-dev-release.apk" (
    set "BUILD_OK=1"
    copy "app\build\outputs\apk\dev\release\app-dev-release.apk" "%SCRIPT_DIR%\SecureChat_v4_Release.apk" >nul 2>&1
    echo  [OK] Release APK:  SecureChat_v4_Release.apk
)

if "%BUILD_OK%"=="0" (
    echo  [HATA] Build basarisiz!
    echo ========================================
    echo.
    echo  Kontrol edin:
    echo    1. JDK 17+ kurulu mu?
    echo    2. Android SDK 34 kurulu mu?
    echo    3. Yonetici olarak calistirdiniz mi?
    echo    4. securechat.keystore dosyasi script klasorunde mi?
) else (
    echo ========================================
    echo.
    echo  Kurulum: adb install SecureChat_v4_Release.apk
)

cd /d "%SCRIPT_DIR%"

:END
echo.
echo Kapatmak icin bir tusa basin...
pause >nul
