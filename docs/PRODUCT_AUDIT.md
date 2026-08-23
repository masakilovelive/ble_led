# ScepTRONIC製品ソース評価

評価日: 2026-08-23

## 採用した製品ソース

旧作業ディレクトリの `septronics/` を製品アプリの基準実装として採用した。

採用根拠:

- `septronics/dist/` に2026-04-27作成のdebug/release APKと配布zipがある。
- Android製品IDは `com.masacookie.sceptronic`、iOS Bundle IDはApp Store Connect登録済みの `com.FAE.ScepTRONIC` である。
- 表示名、ブランド画像、App Store資料が `ScepTRONIC` と一致する。
- C3/C6製品ファームウェアを含む配布zip作成ツールがある。
- 2026-05-05までアプリ、アイコン、出荷検査、配布ツールが更新されている。

## 開発元として保持するもの

- `ble_led_endurance_app`: 現製品アプリの開発元。旧ブランチの履歴として保持する。
- `ble_led_app`: 初期BLEアプリ。旧ブランチの履歴として保持する。
- UNO耐久・出荷検査治具とMCUブリッジ: 現製品の製造検査に必要なため、このブランチの `manufacturing/` に収録する。

## 製品ブランチから除外したもの

- Flutterの `build/`、`.dart_tool/`、`dist/`、Gradleキャッシュ
- ローカル仮想環境、ログ、APK、配布zip
- `ski_*`、`tissue_counter`、`study_research`、`glb_viewer_test_app`
- Loreley navigation light、VESC/DAQ/電源解析関連
- 日付付きバックアップと入れ子のGitクローン

除外した資産は元の作業ディレクトリおよび既存Git履歴に残し、この製品ブランチでは削除しない。

## 製品IDの履歴と採用決定

| 対象 | 確認できたID | 根拠 |
| --- | --- | --- |
| 2026-04-27配布Android APK | `com.masacookie.septronics` | APK Manifestをaaptで確認 |
| 2026-05-05時点のAndroidソース | `com.masacookie.sceptronic` | `app/android/app/build.gradle.kts` |
| 2026-05-05時点のiOSソース | `com.masacookie.sceptronic` | Xcode project設定 |
| App Store Connect登録済みiOSアプリ | `com.FAE.ScepTRONIC` | App Store Connectアプリ情報（Apple ID `6764564058`） |

2026-08-23のApp Store Connect確認により、iOSの正式Bundle IDは既存アプリに登録済みの `com.FAE.ScepTRONIC` と確定した。iOSソースをこのIDへ合わせ、Android application IDは `com.masacookie.sceptronic`、macOS bundle IDも `com.masacookie.sceptronic` のままとする。過去IDは配布・提出履歴との照合用に保持する。
