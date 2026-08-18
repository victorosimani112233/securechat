# iOS Privacy ve Build Readiness Audit

Bu dosya `dart tool/audit_ios_readiness.dart` ile uretilir.
Linux uzerinde statik sozlesmeyi kanitlar; Xcode derlemesi yerine gecmez.

## Sonuc

- Statik readiness: **PASS**
- Dart native method sayisi: 16
- iOS method eslesmesi: 14/14
- Android method eslesmesi: 16/16
- Kayitli iOS plugin sayisi: 13

## Gizlilik kararlari

- Yeni oturumda notification preview ve last-seen paylasimi kapali baslar.
- App switcher goruntusu native opak overlay ile otomatik kapatilir.
- iOS screenshot engellenemez; uygulama yalniz cihaz-ici uyari verir ve server audit olayi gondermez.
- Rehberden yalniz ad ve telefon okunur; contact thumbnail alinmaz.
- Native open/share yalniz `Application Support/media` ve `crash_logs` altindaki normal dosyalari kabul eder; symlink escape reddedilir.
- CallKit/Telecom privacy modunda kisi adi ve account ID yerine generic etiket kullanir.
- Privacy manifest tracking=false, app-functionality veri kategorileri ve app-container file metadata icin `C617.1` beyanini tasir.

## Platform davranisi

- Background maintenance ve sender-key rotation kimlikleri Dart, Info.plist ve AppDelegate katmanlarinda aynidir.
- iOS scheduled-message calisma zamani BGTaskScheduler tarafindan garanti edilmez. Mesaj/plani servera birakmak gizlilik hedefiyle reddedildigi icin cihaz, izin verilen ilk background/foreground firsatinda gonderir.
- Push payload generic wake-up bilgisidir; mesaj, gonderen, grup veya preview tasimaz.
- `GoogleService-Info.plist` zorunlu kaynak dosyasi yapilmadi; Firebase explicit `FirebaseOptions` ve secret olmayan build-time iOS app ID ile kurulur.

## Mac/Codemagic zorunlu kapisi

1. Apple signing team, App ID, push capability ve provisioning profile ayarlanir.
2. `SECURECHAT_FIREBASE_IOS_APP_ID` build-time define saglanir; APNs key Firebase projesine yuklenir.
3. `tool/verify_ios_on_macos.sh` calistirilir; plist lint, analyze, tum Flutter testleri, unsigned iOS release compile ve Runner XCTest gecmeden release alinmaz.
4. Xcode Organizer privacy report ile app + plugin manifest birlesimi incelenir; App Store Connect beyanlari bu rapor ve production retention politikasiyla esit tutulur.
5. iOS terminated-state incoming call wake-up icin PushKit/VoIP capability ve server APNs VoIP gonderimi halen dis provisioning/deployment girdisidir; normal APNs wake-up CallKit icin garanti sayilmaz.

## Kayitli pluginler

- `AudioSessionPlugin`
- `ConnectivityPlusPlugin`
- `FLTFirebaseCorePlugin`
- `FLTFirebaseMessagingPlugin`
- `FLTImagePickerPlugin`
- `FilePickerPlugin`
- `FlutterLocalNotificationsPlugin`
- `FlutterSecureStorageDarwinPlugin`
- `FlutterWebRTCPlugin`
- `IntegrationTestPlugin`
- `JustAudioPlugin`
- `RecordIosPlugin`
- `WorkmanagerPlugin`

## Resmi Apple dayanaklari

- https://developer.apple.com/documentation/bundleresources/privacy-manifest-files
- https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api
- https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/

## Hatalar

- Yok.
