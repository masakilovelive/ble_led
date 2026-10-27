# ScepTRONIC Build 15 ストア再提出作業

最終更新: 2026-10-27

対象候補:

- iOS: `0.1.5 (15)`
- Android: versionName `0.1.5` / versionCode `15`
- Bundle ID / Application ID: `com.FAE.ScepTRONIC`

関連変更は[Build 8–15変更履歴](BUILD_8_TO_15_RELEASE_HISTORY.md)を参照する。

## 0. 現在の進捗（2026-10-27確認）

iOS実機試験およびFlutterテストの結果は2026-10-25の記録を継承する。2026-10-27はApple審査用資料の整理、共有設定、未ログインでの閲覧・再生確認を実施した。ストアへのアップロード・提出完了を示す記録ではない。

- [x] Build 15をiPhone 16／iOS 26.2.1へインストールした。
- [x] iOSで、MCU起動→アプリ起動→Bluetooth Settingを開かず自動接続することを確認した。
- [x] iOSで、アプリ起動中→MCU再起動→Bluetooth Settingを開かず自動再接続することを確認した。
- [x] `flutter analyze`を実行し、問題がないことを確認した。
- [x] Flutterテスト5件が合格した。
- [x] Google Driveへ実機動画①〜⑮（MP4）をアップロードした。
- [x] Google Driveへ動画撮影手順シートをアップロードした。
- [x] Google Driveへ知的財産・所有権確認書のWord原稿をアップロードした。
- [x] 動画①〜⑮と手順シートの計16件を「リンクを知っている全員・閲覧者」へ変更した。各ファイルの権限情報でも `type=anyone / role=reader / allowFileDiscovery=false` を確認した。
- [x] 手順シートのファイル名・タブ名・本文に残っていたBuild 12／14の対象表記をBuild 15へ統一した。
- [x] 手順シートに「提出URL対応表」タブを追加し、動画15本の番号・機能・URL・共有状態・閲覧確認結果・保留事項を記録した。
- [x] 所有権確認書の審査対象を `0.1.5 (Build 15)` へ更新し、Bundle IDと動画対応表のURLを記載した。未記入・未署名・本人の事実確認待ちを明示した。
- [x] Googleからログアウトした実ブラウザーで、動画①〜⑮をそれぞれ冒頭から再生し、プレーヤーの終端到達を確認した。
- [x] 同じ未ログイン状態で、手順シートの本文と「閲覧のみ」表示を確認した。
- [ ] 各動画が審査対象Build 15で撮影されたこと、および必要な操作内容が揃っていることを最終確認する。
- [ ] 所有権確認書の未記入欄、単独所有・配布権限の事実確認、裏付け資料、本人署名を完成させる。
- [ ] 本人確認・署名後の所有権確認書を提出用PDFにし、App Store Connectへ添付する。
- [ ] Android実機でBuild 15のAuto reconnect ON/OFFとMCU再起動後再接続を確認する。
- [ ] Build 15をApp Store ConnectおよびGoogle Play Consoleへアップロードする。

Google Driveの資料:

- [動画撮影手順・提出URL対応表](https://docs.google.com/spreadsheets/d/1GbZrWEGsyEIiQu3ybHnvgobcpMCuCQHNohdQDNDxc7Y/edit?gid=319156219#gid=319156219) — ログイン不要・閲覧者。審査へ案内する動画の個別URLはこのタブに集約。
- [所有権確認書のWord原稿（未署名）](https://docs.google.com/document/d/1kZdY6-CDGHpY5MwEReWUkHRD6IRD1HNy/edit) — `ScepTRONIC_Build15_Ownership_JA_未署名.docx`。非共有のまま。署名済みPDFの代わりとして提出しない。
- [提出準備フォルダー](https://drive.google.com/drive/folders/1hgO4m9Mn7VvCPbGtBNC1vhVEJvSBO1cw) — 内部管理用。今回の公開対象は動画15本と手順シートのみ。審査にはフォルダーではなく個別動画URLまたは対応表URLを案内する。

### 2026-10-27の確認範囲と残課題

- 動画の機能・番号は、各動画から抽出した6か所のフレームと手順シートで部分照合した。別途、Google未ログインの実ブラウザーで全15本の再生開始と終端到達を確認した。全操作の目視判定や音声内容の確認が完了したという意味ではない。
- 撮影時のBuild番号は映像から判読できていない。特に①はDrive上の作成日が2026-10-13のため、Build 15の映像として使用できるか本人確認が必要。作成日だけで撮影Buildを断定しない。
- 所有権確認書では旧 `1.0 (Build 8)` を `0.1.5 (Build 15)` へ更新した。旧Submission ID `bfd67569-31fd-4825-9270-acb92975df71` は過去の参照情報として区別し、今回の提出IDとしては未確認とした。
- Bundle ID `com.FAE.ScepTRONIC` はこの作業記録に基づいて記載した。App Store Connectの実値との照合、Apple Developerアカウント名、Team ID、今回のSubmission ID、連絡先、発行日、署名は本人確認・記入待ち。
- 単独所有、制作・管理、使用・配布権限の記載、およびその裏付け資料は本人の事実確認待ち。署名、添付、審査への返信を完了したものとして扱わない。
- 所有権確認書にも、動画・シートの共有と未ログイン閲覧を確認した結果を追記した。未署名原稿のため、提出用の署名済みPDFは未完成。
- 初回の未ログインHTTP確認では動画がHTTP 429、シートがHTTP 401だったが、共有変更後の実ブラウザー確認で上記16件の閲覧・再生成功を確認した。最終判定はこの実ブラウザー確認結果を採用する。
- App Store Connect／Google Play ConsoleへのBuild 15アップロード、Review Notesの登録、署名済みPDFの添付、Appleへの返信・再提出は今回実施していない。

### 動画番号とURLの対応表

2026-10-27、全15本で「リンクを知っている全員・閲覧者」の設定と、Google未ログインでの再生開始・終端到達を確認済み。各動画の撮影Buildと操作内容の最終確認は保留。

| 動画 | 手順シート上の機能 | URL |
| --- | --- | --- |
| ① | 初回登録・接続 | [①.mp4](https://drive.google.com/file/d/1clrCN5QSA6DObE6JFuagLasMc1EUIZda/view) |
| ② | Stock A Head単色 | [②.mp4](https://drive.google.com/file/d/1UznXBFiI4HJja4itNrzzN2sPXh5QNdoT/view) |
| ③ | Stock A Tip単色 | [③.mp4](https://drive.google.com/file/d/1D2f6OR4EG1tbPTuQyxt1iA9Nd08x7rVz/view) |
| ④ | Stock B Head単色 | [④.mp4](https://drive.google.com/file/d/1nSG9cE6b9qZmOmxiXqA6Sw0SGpcbjBPV/view) |
| ⑤ | Stock B Tip単色 | [⑤.mp4](https://drive.google.com/file/d/10GlI8-ihwqShPGSgpyOEvf8n3NfXEwJq/view) |
| ⑥ | Stock A Heart Beat | [⑥.mp4](https://drive.google.com/file/d/1kz3R2vezFe7cPQPHUx_UhGCRvUsNHjJZ/view) |
| ⑦ | Stock A Rainbow | [⑦.mp4](https://drive.google.com/file/d/15MtKMUDLlmB7FHr1bkN0kig7zGG_BKLE/view) |
| ⑧ | Stock B Heart Beat | [⑧.mp4](https://drive.google.com/file/d/19tHGvilXguAA2ugws3yuS2VjAo8yil2X/view) |
| ⑨ | Stock B Rainbow | [⑨.mp4](https://drive.google.com/file/d/1DaicfwGY1eOqDvX5q63aSFAZTPT3j-ZL/view) |
| ⑩ | A+B同期 Heart Beat・Rainbow | [⑩.mp4](https://drive.google.com/file/d/16yx1f88wiMGyoeT1ZYzQ-hL_Xi292gVs/view) |
| ⑪ | A+B同期 単色設定 | [⑪.mp4](https://drive.google.com/file/d/1Nrtz4SIx40L6NgpbfuGnfbmnlnuzVdh8/view) |
| ⑫ | 切断・手動接続 | [⑫.mp4](https://drive.google.com/file/d/1vZhsM08bTVpVakxFumb04uajpXSByEuS/view) |
| ⑬ | Auto reconnect ON MCU起動→アプリ起動 | [⑬.mp4](https://drive.google.com/file/d/1rtPXPcY7Jj59opfHkSzUZfr7u8soa_Y0/view) |
| ⑭ | Auto reconnect ON アプリ起動中→MCU再起動 | [⑭.mp4](https://drive.google.com/file/d/1teVypqytiumKDGEVK5JvBikohITiYaQe/view) |
| ⑮ | Auto reconnect OFF・手動接続 | [⑮.mp4](https://drive.google.com/file/d/1rRbxjrn-oR93--7frWtu5rteec3vpxoP/view) |

## 1. 両ストア共通

- [ ] iOSとAndroidのソースが同一のBuild 15仕様であることを確認する。
- [ ] iOS実機およびAndroid実機でAuto reconnect ON/OFFを確認する。
- [ ] MCU起動→アプリ起動→自動接続を確認する。
- [ ] アプリ起動中→MCU再起動→自動再接続を確認する。
- [ ] Noxel-1／Noxel-2、色、明るさ、Head、Tip、Heart Beat、Rainbow、A+B同期を確認する。
- [ ] 充電検知・電圧表示に回帰がないことを確認する。
- [ ] Demo Mode、`START DEMO`、UUID／MAC相当識別子、不要な右上リンク状態アイコンが表示されないことを確認する。
- [x] `flutter analyze`とテストを実行し、結果を保存する（解析問題なし、テスト5件合格）。
- [ ] iOS IPAとAndroid署名済みAABをBuild 15で作成する。
- [ ] スクリーンショット、動画、説明文がBuild 15の実画面と一致していることを確認する。

## 2. Apple App Store Connect

### バイナリとバージョン

- [ ] Build 15をArchiveし、App Store Connectへアップロードする。
- [ ] Apple側の処理完了後、iOSアプリバージョン`0.1.5`のBuild欄でBuild 15を選択する。
- [ ] Export Complianceの質問または不足情報が表示された場合は回答する。
- [ ] Build 8など旧ビルドが選択されている場合は外し、Build 15へ差し替える。

### Guideline 2.1: App Completeness

- [x] 実機動画①〜⑮をMP4でGoogle Driveへアップロードする。
- [x] 動画番号と機能を対応付ける撮影手順シートをGoogle Driveへアップロードする。
- [x] 実機とiPhone画面を同時に撮影した動画①〜⑮を用意した。抽出フレームで実機・画面を部分確認した。
- [ ] 登録、接続、主要LED操作、アプリ起動時自動接続、MCU再起動後自動再接続が、Build 15の動画として必要な操作を満たすことを最終確認する（番号・機能の部分照合は実施済み）。
- [x] Google Driveの動画①〜⑮と手順シートを「リンクを知っている全員・閲覧者」に設定した（2026-10-27）。
- [x] Googleからログアウトした実ブラウザーで、動画①〜⑮すべての再生開始と終端到達を確認した（2026-10-27）。シークレットウィンドウを使用したとの記録ではない。
- [ ] Review Notesへ動画URL、必要ハードウェア、確認手順、試験端末・OSを記載する。
- [ ] 審査完了まで動画を移動・削除せず、共有権限を維持する。

Appleは、専用ハードウェアが必要なアプリについて、物理Apple端末上のアプリがハードウェアとペアリング・操作する様子を示す動画をApp Review Informationへ提供するよう案内している。

### Guideline 5.2.1: Intellectual Property

- [x] 知的財産・所有権確認書のWord原稿をGoogle Driveへアップロードした。
- [x] 単独所有者宣言書の原稿を `0.1.5 (Build 15)` へ更新し、動画対応表URLと2026-10-27の閲覧確認結果を記載した。未署名・非共有の原稿として管理している。
- [ ] ScepTRONIC名称、ロゴ、製品およびBLEハードウェアについて、単独所有・使用・配布権限の記載が事実と一致するか本人が確認し、裏付け資料を揃える。
- [ ] 氏名、住所、連絡先、発行日、Apple Developerアカウント名、Team ID、今回のSubmission IDを本人が確認・記入し、署名する。法人の存在・役職・社印など未確認の事実を補完しない。
- [ ] `com.FAE.ScepTRONIC` のApple App Storeでの配布権限に関する記載を本人が確認する。
- [ ] 確認・署名済みの書類を提出用PDFにし、所有を裏付ける原本・開発記録・契約書など実在する補足資料を必要に応じて添付する。
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
