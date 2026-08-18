# Vendored Android Maven Artifact

`flutter_webrtc 1.6.0`, Android audio routing icin
`com.github.davidliu:audioswitch:039a35aefab7747c557242fa216c9ea11743b604`
artefaktini ister. Upstream plugin bu commit artefaktini JitPack'ten cozer.
Release build'inde JitPack'e izin verilmedigi icin daha once Gradle dependency
verification ile dogrulanan AAR ve POM bu local Maven deposunda vendoredir.

- AAR SHA-256:
  `c8240221daa9a96d4ea01a4dc6f6f6b10b4903d2a71f9b57f838bdfeb6c3fcbc`
- POM SHA-256:
  `b01278803fe0a007591a44143e1919a406c0c529794b13aa30e86a87532095fd`
- Upstream: `https://github.com/twilio/audioswitch`
- Lisans: Apache-2.0; metin `assets/licenses/audioswitch_APACHE-2.0.txt`

`test/supply_chain_gate_test.dart` byte hash'lerini ve repository politikasini
kontrol eder. Artefakt guncellenirse commit, iki hash, lisans, Gradle
verification metadata ve WebRTC testleri birlikte review edilmelidir.
