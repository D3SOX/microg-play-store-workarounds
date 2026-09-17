# microG Play Store Workarounds

This release refocuses the project as a general microG / Play Integrity compatibility guide and updates the modules accordingly.

Highlights:

- documents the Android 13+ `MEETS_DEVICE_INTEGRITY` setup as a combination of root/Zygisk hiding, Play Integrity Fork, an attestation/keystore solution such as Tricky Store OSS, and the official Play Store compatibility layer where needed;
- updates `playstore-base` to v1.1 and restores the tested Android 16 device-idle whitelist fix for normal Play Store downloads;
- keeps the privacy filter's intentional override: it disables Play Store `DownloadService` and removes the Store from the device-idle whitelist;
- keeps Play installer-provenance repair as an optional tool for legitimately owned apps;
- removes application-specific framing from the documentation.
