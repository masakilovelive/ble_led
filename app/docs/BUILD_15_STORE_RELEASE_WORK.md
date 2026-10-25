# ScepTRONIC Build 15 ストア再提出作業

最終更新: 2026-10-25

対象候補:

- iOS: `0.1.5 (15)`
- Android: versionName `0.1.5` / versionCode `15`
- Bundle ID / Application ID: `com.FAE.ScepTRONIC`

関連変更は[Build 8–15変更履歴](BUILD_8_TO_15_RELEASE_HISTORY.md)を参照する。

## 1. 両ストア共通

- [ ] iOSとAndroidのソースが同一のBuild 15仕様であることを確認する。
- [ ] iOS実機およびAndroid実機でAuto reconnect ON/OFFを確認する。
- [ ] MCU起動→アプリ起動→自動接続を確認する。
- [ ] アプリ起動中→MCU再起動→自動再接続を確認する。
- [ ] Noxel-1／Noxel-2、色、明るさ、Head、Tip、Heart Beat、Rainbow、A+B同期を確認する。
- [ ] 充電検知・電圧表示に回帰がないことを確認する。
- [ ] Demo Mode、`START DEMO`、UUID／MAC相当識別子、不要な右上リンク状態アイコンが表示されないことを確認する。
- [ ] `flutter analyze`とテストを実行し、結果を保存する。
- [ ] iOS IPAとAndroid署名済みAABをBuild 15で作成する。
- [ ] スクリーンショット、動画、説明文がBuild 15の実画面と一致していることを確認する。

## 2. Apple App Store Connect

### バイナリとバージョン

- [ ] Build 15をArchiveし、App Store Connectへアップロードする。
- [ ] Apple側の処理完了後、iOSアプリバージョン`0.1.5`のBuild欄でBuild 15を選択する。
- [ ] Export Complianceの質問または不足情報が表示された場合は回答する。
- [ ] Build 8など旧ビルドが選択されている場合は外し、Build 15へ差し替える。

### Guideline 2.1: App Completeness

- [ ] 実物のNoxel-1／Noxel-2とiPhone画面を同時に映した動画を用意する。画面収録だけにしない。
- [ ] 動画に、登録、接続、主要LED操作、アプリ起動時自動接続、MCU再起動後自動再接続を含める。
- [ ] Google DriveへMP4を置き、「リンクを知っている全員・閲覧者」に設定する。
- [ ] Google未ログインのシークレットウィンドウで動画を最初から再生できることを確認する。
- [ ] Review Notesへ動画URL、必要ハードウェア、確認手順、試験端末・OSを記載する。
- [ ] 審査完了まで動画を移動・削除せず、共有権限を維持する。

Appleは、専用ハードウェアが必要なアプリについて、物理Apple端末上のアプリがハードウェアとペアリング・操作する様子を示す動画をApp Review Informationへ提供するよう案内している。

### Guideline 5.2.1: Intellectual Property

- [ ] ScepTRONIC名称、ロゴ、製品およびBLEハードウェアをアプリで使用・配布する権限を示す許諾書を準備する。
- [ ] 権利者の正式法人名、住所、担当者名、役職、連絡先、発行日、署名または社印を記載する。
- [ ] `com.FAE.ScepTRONIC`をApple App Storeで配布する許可を明記する。
- [ ] 会社レターヘッド付きPDFとし、商標登録証、契約書、発注書など補足資料があれば添付する。
- [ ] App Review InformationのAttachmentへPDFを追加し、Review NotesとAppleへの返信で説明する。

### メタデータと再提出

- [ ] スクリーンショットをBuild 15のUIへ更新する。
- [ ] 「このバージョンの最新情報」とReview NotesへBuild 8以降の累積変更を記載する。
- [ ] Privacy Policy URL、Support URL、連絡先、App Privacy、価格・配信地域を再確認する。
- [ ] Appleの未解決メッセージへ、Build 15、動画、知的財産書類を追加したことを返信する。
- [ ] `Add for Review`後、Draft Submissionで内容を確認し、`Submit for Review`を実行する。
- [ ] ステータスが`Waiting for Review`または`In Review`へ進むことを確認する。

### Apple用リリース説明案

```text
Build 15 improves Bluetooth connection reliability for registered Noxel-1 and
Noxel-2 devices. When Auto reconnect is enabled, the app discovers and connects
to both registered devices at launch and reconnects after an MCU restart without
requiring the Bluetooth Setting screen. Device registration is retained when a
device is temporarily unavailable.

The production build does not include Demo Mode. Device identifiers are hidden
from the product UI, and the launch and stock setting screens have been updated.
No firmware update is required for these app-side changes.
```

## 3. Google Play Console

### バイナリとリリース

- [ ] AndroidのversionCodeが`15`、versionNameが`0.1.5`であることを確認する。
- [ ] 署名済みAABを作成し、既存のクローズドテストトラックへアップロードする。
- [ ] リリース名を例`0.1.5 (15)`として、リリースノートを日本語・英語で入力する。
- [ ] Application ID、Play App Signing、対象APIレベル、権限警告を確認する。
- [ ] エラーと警告を解決してテストリリースを開始する。
- [ ] 既存テスターがBuild 15へ更新できることを確認する。

### ストア情報・ポリシー

- [ ] スクリーンショットと説明文をBuild 15のUI・機能へ合わせる。
- [ ] Data safety、Bluetooth権限、Privacy Policyの内容が実装と一致していることを確認する。
- [ ] 対象ユーザー、コンテンツレーティング、広告、データ収集回答を再確認する。
- [ ] 公開の概要に保留中の変更が残っていないことを確認する。

### 12人・14日間のクローズドテスト

- Google公式要件は、**2023年11月13日以降に作成した個人デベロッパーアカウント**がProduction accessを初めて申請する場合に適用される。
- 対象アカウントでは、12人以上のテスターがクローズドテストへ14日間連続でオプトインしている必要がある。
- Build 15へ更新しただけで既存の連続オプトイン実績が自動的にリセットされる、という要件ではない。テスターをトラックから外したりオプトアウトさせたりせず、Play ConsoleのProduction access表示を確認する。
- すでにProduction accessが承認済みの場合、通常の更新ごとに12人・14日間を最初からやり直す手順ではない。
- Consoleが追加テストを要求した場合は、その画面の指示を優先する。

### Google Play用リリースノート案

日本語:

```text
Bluetooth接続の安定性を改善しました。
Auto reconnectがONの場合、登録済みのNoxel-1／Noxel-2へアプリ起動時に自動接続し、MCU再起動後も自動的に再接続します。
デバイス表示、起動画面および操作画面を改善しました。
```

English:

```text
Improved Bluetooth connection reliability.
When Auto reconnect is enabled, the app connects to registered Noxel-1 and
Noxel-2 devices at launch and reconnects automatically after an MCU restart.
Improved the device display, launch screen, and controls.
```

## 4. 公式参照先

- Apple: [Provide information for a complete review](https://developer.apple.com/help/app-review/before-submitting-for-review/complete-review)
- Apple: [Choose a build to submit](https://developer.apple.com/help/app-store-connect/manage-builds/choose-a-build-to-submit/)
- Apple: [Submit an app](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app/)
- Google: [App testing requirements for new personal developer accounts](https://support.google.com/googleplay/android-developer/answer/14151465)
- Google: [Set up your app on the app dashboard](https://support.google.com/googleplay/android-developer/answer/9859454)
