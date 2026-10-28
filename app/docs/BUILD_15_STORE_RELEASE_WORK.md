# ScepTRONIC Build 16 ストア再提出作業（Build 15履歴を含む）

最終更新: 2026-10-29（提出文面整備。ストアの進捗は2026-10-28記録に基づく）

現在の対象:

- iOS: `0.1.6 (16)`
- Android: versionName `0.1.6` / versionCode `16`
- Bundle ID / Application ID: `com.FAE.ScepTRONIC`

関連変更は[Build 8–15変更履歴](BUILD_8_TO_15_RELEASE_HISTORY.md)を参照する。同文書はBuild 15時点の履歴であり、現在の提出対象を示すものではない。

本書の§1〜3が現在のBuild 16向け手順・文面、§0と§5がBuild 15の履歴。今回はGitHub文書のみを更新し、ストアへの入力・資料差し替え・正式な審査送信は実施していない。

## 0A. Build 16への更新と現在の進捗（2026-10-28確認）

Build 15のストアアップロード後、Android実機のStock Setting画面で、狭い2列レイアウト内の`Head`／`Tip`と`RAINBOW`バッジがオーバーフローすることを確認した。端末のフォント倍率は標準`1.0`であり、原因は端末設定ではなく固定幅UIだった。iOSとAndroidで共有するFlutterコードを可変レイアウトに修正したため、両OSをBuild 16に統一した。Bluetooth通信、Auto reconnect、ファームウェアの仕様変更ではない。

- [x] `SceptronicStatusPill`をコンパクト表示に対応させた。
- [x] Stock Settingの`Head`／`Tip`見出しを可変幅と縮小表示にし、狭いAndroid端末でのオーバーフローを解消した。
- [x] 修正後のAndroid画面を実機（SH 02M、1080×2160、font scale 1.0）で確認した。
- [x] `flutter analyze`で問題なし、Flutterテスト5件の合格を確認した。
- [x] Android実機へ通常版`0.1.6 (16)`をインストールし、versionCode `16`／versionName `0.1.6`を確認した。
- [x] iOS実機（a4os5のiPhone）へ`0.1.6 (16)`をインストールし、Bundle ID `com.FAE.ScepTRONIC`、バージョン`0.1.6`、Build `16`を端末情報で確認した。
- [x] iOS用IPAを`0.1.6 (16)`で生成し、App Store Connectへアップロードした。Xcode Organizerの状態は`Uploaded with warnings`。
- [x] Android用署名済みAABをversionCode `16`／versionName `0.1.6`で生成し、Google Play Consoleのクローズドテスト下書きへアップロードした。
- [x] 動画①をBuild 16で再撮影し、無音版`①_Build16_無音.mp4`をGoogle Driveへ追加した。
- [x] 動画提出URL対応表の①を、Build 16無音版のURL・再生時間・確認状況へ更新した。
- [x] 動画内の表示`0.1.6`とApp Store Connectの提出Build `0.1.6 (16)`の対応は、アプリ名を変更せずReview Notesで説明する方針とした。
- [ ] Google Play Consoleの下書きにBuild 15とBuild 16が両方表示されているため、Build 15をリリース対象から外し、Build 16のみで保存する。
- [ ] App Store ConnectとGoogle Play ConsoleのスクリーンショットをBuild 16表示に差し替える。
- [ ] 動画①の共有権限と、Google未ログイン状態での再生を最終確認する。
- [ ] リリースノート、Review Notes、動画、知的財産書類を最終確認し、各ストアの審査へ送信する。

### Build 16動画①とReview Notes（2026-10-28更新）

- 動画①（Build 16・無音版）: [①_Build16_無音.mp4](https://drive.google.com/file/d/1mEaeRlyByK1Aajfws1DIL7gG-tEc6emR/view?usp=drivesdk)
- 再生時間: 約42.82秒
- 動画内で表示されるアプリバージョンは`0.1.6`。App Store Connectへアップロード済みの対象は`0.1.6 (Build 16)`。
- アプリ名またはホーム画面表示名を`Build 16`付きへ変更しない。名称変更はBuildの証明にならず、追加バイナリが必要になるため、アップロード済みBuild 16を維持する。
- Build番号との対応はApp Store ConnectのReview Notesへ明記する。

Review Notesは§2の日英全文を使用する。「Build 16で撮影」と説明できる対象は動画①に限定する。旧案の「The attached demonstration video」「本動画」のように対象が曖昧な表現は使用しない。②〜⑮の撮影Buildは未確認であり、①の再撮影をもって全動画のBuild一致が確認されたとは扱わない。

### アップロード時の警告と注意点（2026-10-28の記録、今回の再検証なし）

- iOS deployment targetは現在`13.0`。2027年4月以降のアップロードでは`15.0`以上が必要というApple警告がある。今回のBuild 16アップロード自体は完了している。
- `objective_c.framework`の対応dSYMがArchiveに含まれないというシンボル警告がある。バイナリのアップロードは成功しているが、クラッシュ解析性のため今後解消を検討する。
- Build 16はまだ審査送信・公開完了ではない。App Store ConnectでのBuild選択と`Submit for Review`、Google Play Consoleでのプレビュー確認とテストリリース開始は未実施。

## 0B. 2026-10-29の実装照合と文面整備

### 根拠と確認範囲

- 進捗の基準: [2026-10-28記録更新 f574dc5](https://github.com/masakilovelive/ble_led/commit/f574dc58a57af5e72f28d38052d364ea0de3154b)、[Build 16への更新記録 1f859bf](https://github.com/masakilovelive/ble_led/commit/1f859bf55061a067c45c7c0508746338e731f206)。両コミットは作業記録の更新であり、Build 16実装差分そのものではない。
- 2026-10-29に確認したmain先頭は `f574dc58a57af5e72f28d38052d364ea0de3154b`。以下のソース参照はこのコミットに固定した。
- [led_setting_screen.dart](https://github.com/masakilovelive/ble_led/blob/f574dc58a57af5e72f28d38052d364ea0de3154b/app/lib/screens/led_setting_screen.dart#L282)では、Stock A/B共通画面がHeadとTipを2列で表示し、モードに応じた状態バッジを各見出しの横に置く。`_modeLabel`の`RAINBOW`は状態表示であり、下段のRainbow操作スイッチや効果そのものとは区別する。
- ただし、同ファイルの見出し行は `Text(title) + Spacer + SceptronicStatusPill` のまま。[sceptronic_ui.dart](https://github.com/masakilovelive/ble_led/blob/f574dc58a57af5e72f28d38052d364ea0de3154b/app/lib/screens/sceptronic_ui.dart#L304)のバッジにもcompact引数がなく、固定paddingが残る。作業記録にあるBuild 16の可変幅・縮小表示／コンパクト表示を、現在のmain実装からは再確認できなかった。
- [pubspec.yaml](https://github.com/masakilovelive/ble_led/blob/f574dc58a57af5e72f28d38052d364ea0de3154b/app/pubspec.yaml)も `0.1.4+5` のまま。[Android設定](https://github.com/masakilovelive/ble_led/blob/f574dc58a57af5e72f28d38052d364ea0de3154b/app/android/app/build.gradle.kts)と[iOS設定](https://github.com/masakilovelive/ble_led/blob/f574dc58a57af5e72f28d38052d364ea0de3154b/app/ios/Runner/Info.plist)はFlutterのビルド値を参照しているため、pubspecの値だけでアップロード済み成果物のバージョンを否定・確定しない。Build時の上書き値・成果物情報との照合が必要。
- `product/sceptronic`先頭 `ed20868ad78007e6e2c1d13b15dbc5e1de3fbc91` でも上記2画面とpubspecはmainと同じblobだった。`codex/build15-app-store-screenshots`先頭 `c583fb3f762052c08e0627d989afa6ea19aad189` には現在の`app/`構成がない。これらのブランチ確認ではBuild 16の修正ソースを特定できなかった。
- 解析問題なし・テスト5件合格・実機確認・IPA/AABアップロードは§0Aの過去作業記録に基づく。今回はFlutter解析・テスト・実機試験を再実行していない。mainの `app/test/widget_test.dart` は起動テスト1件であり、記録上の5件の試験内容をこのファイルだけから再現したとは扱わない。

### Build 16の説明に使う範囲

| 項目 | 今回の記載 | 根拠・限界 |
| --- | --- | --- |
| Head／Tip | 狭い2列レイアウトで見出しがはみ出す問題を修正。見出しを可変幅・縮小表示に対応 | 10/28作業記録。mainの修正済みソースとの一致は未確認 |
| RAINBOW | 状態バッジをコンパクト表示に対応し、見出しとともに収まるよう調整 | 効果・速度・色制御の新機能として説明しない |
| OS | 共有Flutter UIの修正を含む0.1.6（Build 16）にiOS／Androidを統一 | Androidで発見した問題。iOSで同じ不具合が再現したとは記録されていない |
| 実機 | Android SH 02M、1080×2160、font scale 1.0で修正後画面を確認。iOS実機へのBuild 16インストールとバージョン情報を確認 | 全端末・全フォント倍率・全機能での回帰試験完了とはしない。Build 16のiPhone機種／OS詳細は未記録 |
| 既存機能 | Bluetooth接続・Auto reconnectの改善はBuild 8〜15からの累積履歴として区別 | Build 16で新規修正・全動作再検証したとは記載しない |
| 動画① | Build 16で再撮影した無音版。表示0.1.6と対象Build 16の対応を明記 | 10/28記録に基づく。共有権限・未ログイン再生は最終確認待ち |
| 動画②〜⑮ | 既存の機能説明資料。撮影Build未確認 | Build 16撮影・Build 16画面修正の証拠とはしない |
| スクリーンショット | 両ストアのBuild 16用差し替えは未完了として管理 | 作成・アップロード・表示一致の確認を今回実施していない |

- [x] Apple Review Notes、App Store用リリース説明、Google Play用リリースノートを日本語・英語で本書へ作成した。
- [x] 現在のBuild 16文面とBuild 15の検証・提出計画・旧文面を分離した。
- [ ] Build 16を作成した作業環境の実装差分、ビルド時のversion指定、対象コミットを記録し、アップロード済みIPA/AABとの対応を照合する。今回、推測によるソース修正・バージョン変更・バイナリ再生成は行わない。
- [ ] 既存動画・手順シート・権利書類で旧Build表記の残る箇所を洗い出し、対象範囲の注記を更新する。過去の撮影Buildを一律にBuild 16へ書き換えない。

## 0. Build 15時点の進捗（2026-10-27確認、履歴）

以下はBuild 15時点の履歴であり、現在の正式対象は上記Build 16とする。iOS実機試験およびFlutterテストの結果は2026-10-25の記録を継承する。2026-10-27はApple審査用資料の整理、共有設定、未ログインでの閲覧・再生確認を実施した。ストアへのアップロード・提出完了を示す記録ではない。

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

### 動画番号とURLの対応表（2026-10-27時点の履歴）

以下の①は旧URL。今回の提出に使う①は§0AのBuild 16無音版URLとし、この旧表の①や旧URLの閲覧確認結果を新ファイルへ流用しない。②〜⑮も、過去の共有・再生確認と撮影Buildの確認を区別する。

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

## 1. Build 16提出前チェック（両ストア共通）

- [x] 両OSの対象を `0.1.6 (Build 16)` として提出文面を整備した。
- [x] IPAのApp Store Connectへのアップロード、AABのGoogle Playクローズドテスト下書きへのアップロードは10/28記録で確認できる。
- [ ] §0Bのソースと成果物の対応、およびBuild 16での必要な回帰試験結果を記録する。Build 15の接続試験結果をBuild 16の再試験済み結果として転記しない。
- [ ] 動画①の現行URL・共有設定・Google未ログイン再生を確認する。
- [ ] ②〜⑮の撮影Buildと操作内容を確認し、現行UIとの相違を注記する。必要な操作が不足する場合はBuild 16で再撮影する。
- [ ] 手順シートの現在の対象をBuild 16とし、①と②〜⑮の撮影Build確認状況を分けて表示する。
- [ ] 両ストアのスクリーンショットをBuild 16の実画面へ差し替え、Stock A/B SettingのHead／TipとRAINBOW状態バッジを含め、掲載画像との一致を確認する。
- [ ] 所有権書類を現在の対象へ更新し、権利関係の事実確認、本人記入・署名、PDF作成を終える。Build 15未署名原稿をBuild 16の署名済み提出資料と扱わない。
- [ ] 下記の文面を各Consoleへ入力・保存し、表示内容を確認する。本書に文面があることはConsole反映済みを意味しない。
- [ ] 正式送信後に日時（JST）、対象Build、Submission／リリース識別情報、表示ステータスを追記する。

## 2. Apple App Store Connect（現在: 0.1.6 / Build 16）

### 入力・差し替えが必要な項目

| 場所 | 入力・差し替え内容 | 状態 |
| --- | --- | --- |
| iOSバージョン／Build | 0.1.6にアップロード済みBuild 16を選択。旧Build 8／15が選択されていれば選択を差し替え、保存 | アップロード済み（10/28記録）。処理完了・選択・保存は未確認 |
| App Review Information > Notes | 下記の日英Review Notes。動画①のBuild 16 URLと②〜⑮の撮影Build未確認を明記 | 文面作成済み／Console入力未実施 |
| このバージョンの最新情報 / What's New in this Version | 下記の日英リリース説明を各ローカライズへ入力 | 文面作成済み／Console入力未実施 |
| スクリーンショット | Build 16実画面へ差し替え。対応端末サイズごとに表示を確認 | 差し替え・照合未完了 |
| App Review Information > Attachment | 本人が事実確認・署名した現行対象の知的財産書類PDFと、実在する裏付け資料 | 未完了。未署名原稿しか確認していない |
| App Review Information／関連情報 | Build 16のiPhone機種・iOS、連絡先、必要ハード、動画アクセス、Export Compliance等の不足情報 | 最終確認待ち。Build 15のiPhone 16／iOS 26.2.1をBuild 16の試験環境と断定しない |
| 未解決の審査メッセージ／審査送信 | 資料完成後、実際に追加したBuild・動画・権利書類だけを説明し、提出内容を確認して審査送信 | 未実施。署名・添付・返信・送信済みとは記載しない |

Appleの公式仕様ではReview Notesは4000 bytesまで。以下は各言語単独でも、日英を連結しても上限内。英語を先にして同じNotes欄へ日英を併記できる。動画①の公開再生、②〜⑮の扱い、権利書類・画面資料の残課題を解消し、事実が変わった箇所を更新してから保存・送信する。

初回公開扱いなどで「このバージョンの最新情報」欄が表示されない場合は、下記を入力できたものとして記録しない。通常のアプリ説明欄をリリース履歴だけで置き換えず、Review Notesへ今回の修正内容を記載する。

### Apple Review Notes（日本語）

```text
審査対象: ScepTRONIC 0.1.6 (Build 16)
Bundle ID: com.FAE.ScepTRONIC

専用BLE LEDハードウェア（Noxel-1／Noxel-2）が必要です。実機を電源ONにし、iPhoneのBluetoothを有効にして、アプリのBluetooth権限を許可してください。
BLUETOOTH SETTINGでSCANし、各デバイスのSETからStock A／Bへ割り当て、CONNECT BOTHで接続します。STOCK SELECTから各StockのOPENを押し、Color Tone／Color Strength／Brightnessを調整してHead／TipのSETを押します。Heart Beat、Rainbow、BOTH SYNCROも確認できます。

Build 16では、Stock A/B Settingの狭い2列レイアウトでHead／Tip見出しとRAINBOW状態バッジがはみ出す問題を修正しました。見出しの可変幅・縮小表示と状態バッジのコンパクト表示に対応した、iOS／Android共通の画面修正です。RAINBOWは動作状態の表示であり、Rainbow効果やBLE通信、Auto reconnect、ファームウェアの仕様変更ではありません。

動画①（Build 16で再撮影した無音版）:
https://drive.google.com/file/d/1mEaeRlyByK1Aajfws1DIL7gG-tEc6emR/view
動画①に表示される0.1.6は、今回の審査対象0.1.6 (Build 16)に対応します。0.1.6の画面表示だけでBuild番号を判定するものではありません。

動画番号・操作・URL対応表:
https://docs.google.com/spreadsheets/d/1GbZrWEGsyEIiQu3ybHnvgobcpMCuCQHNohdQDNDxc7Y/edit?gid=319156219#gid=319156219
②〜⑮は既存の機能説明資料です。撮影Buildは未確認であり、Build 16で撮影した動画、またはBuild 16の画面修正を検証する動画とは扱っていません。
```

### Apple Review Notes（English）

```text
Review target: ScepTRONIC 0.1.6 (Build 16)
Bundle ID: com.FAE.ScepTRONIC

Dedicated BLE LED hardware (Noxel-1/Noxel-2) is required. Power on the hardware, enable Bluetooth on the iPhone, and allow the app's Bluetooth permission.
In BLUETOOTH SETTING, use SCAN, then SET to assign the devices to Stock A/B. Tap CONNECT BOTH. In STOCK SELECT, tap OPEN for either stock. Adjust Color Tone, Color Strength, and Brightness, then tap SET for Head or Tip. Heart Beat, Rainbow, and BOTH SYNCRO are also available.

Build 16 fixes overflow of the Head/Tip headings and the RAINBOW status badge in the narrow two-column Stock A/B Setting layout. The shared iOS/Android UI now supports flexible, scaled-down headings and compact status badges. RAINBOW here is a status label. This is a layout fix, not a change to the Rainbow effect, BLE communication, Auto reconnect, or firmware behavior.

Video 1 (silent, re-recorded using Build 16):
https://drive.google.com/file/d/1mEaeRlyByK1Aajfws1DIL7gG-tEc6emR/view
The version 0.1.6 displayed in Video 1 corresponds to this review target, version 0.1.6 (Build 16). The version text alone does not identify the build number.

Video index, operations, and links:
https://docs.google.com/spreadsheets/d/1GbZrWEGsyEIiQu3ybHnvgobcpMCuCQHNohdQDNDxc7Y/edit?gid=319156219#gid=319156219
Videos 2-15 are existing functional demonstrations. Their recording builds have not been confirmed. They are not presented as recordings of Build 16 or as verification of its layout fix.
```

### App Store用リリース説明（日本語）

```text
0.1.6（Build 16）
Stock A/B Setting画面のレイアウトを改善しました。
狭い画面幅でHead／Tip見出しやRAINBOW状態バッジがはみ出す問題を修正しました。
見出しと状態バッジが利用可能な幅に収まるよう表示を調整しました。
```

### App Store release notes（English）

```text
0.1.6 (Build 16)
Improved the Stock A/B Setting layout.
Fixed overflow of the Head/Tip headings and the RAINBOW status badge at narrow screen widths.
Adjusted headings and status badges to fit the available space.
```

### Apple送信時の確認

- [ ] 動画①のURLをGoogle未ログインで開き、再生できることを記録する。
- [ ] ②〜⑮の未確認事項を解消または正確に注記し、「全動画がBuild 16」「全機能検証済み」と記載しない。
- [ ] 権利書類PDFの作成・署名・添付後、Guideline 5.2.1への対応状況を事実に沿ってReview Notesまたは審査メッセージへ追加する。上記Notesは添付完了を宣言していない。
- [ ] Build 16選択、スクリーンショット、日英文面、プライバシー・サポートURL、連絡先を確認する。
- [ ] `Add for Review`後に提出内容を確認し、`Submit for Review`を実行する。Console上の実際のステータスを記録する。

## 3. Google Play Console（現在: versionName 0.1.6 / versionCode 16）

### 入力・差し替えが必要な項目

| 場所 | 入力・差し替え内容 | 状態 |
| --- | --- | --- |
| クローズドテスト > 対象トラック > 下書きリリース | アップロード済みversionCode 16／versionName 0.1.6を対象にする | 10/28アップロード記録あり。今回Console再確認なし |
| 同リリース > App bundles | Build 15をこのリリースの対象から外し、Build 16のみで保存・プレビュー確認する | 下書きに15と16が両方表示との記録。除外未完了 |
| Release name | `0.1.6 (16)` | 入力・保存未確認 |
| What's new in this release? | 下記の日英リリースノート | 文面作成済み／Console入力未実施 |
| メインのストア掲載情報 > スクリーンショット | Build 16実画面へ差し替え、Head／Tip・RAINBOW表示を照合する | 差し替え・照合未完了 |
| ストア情報／App content | 説明、Data safety、Bluetooth権限、Privacy Policy、対象ユーザー、レーティング等と現行実装の一致を確認 | 最終確認待ち |
| Preview and confirm／Publishing overview | エラー・警告、対象Build・トラックを確認。必要な変更を審査へ送信し、クローズドテストのリリース状態を確認 | 正式送信・テスト配信開始は未完了 |

Build 15を外すのは今回の下書きリリースからの除外であり、過去のAAB・配信履歴を消す作業ではない。保存しただけで審査送信・テスターへの配信完了と判断しない。

Google公式の上限は言語ごとに500 Unicode文字。以下の日本語・英語はいずれも上限内。Consoleに表示される実際の言語タグを使用する（例: `ja-JP`／`en-US`。未追加の言語はローカライズを追加してから入力）。

### Google Play用リリースノート（日本語）

```text
0.1.6（Build 16）
Stock A/B Setting画面で、狭い画面幅のときにHead／Tip見出しやRAINBOW状態バッジがはみ出す問題を修正しました。
見出しの可変幅・縮小表示と状態バッジのコンパクト表示に対応しました。
```

### Google Play release notes（English）

```text
0.1.6 (Build 16)
Fixed overflow of the Head/Tip headings and the RAINBOW status badge in the Stock A/B Setting screen at narrow widths.
Added flexible, scaled-down headings and compact status badges.
```

### Google送信時の確認

- [ ] Build 15を下書きのリリース対象から外し、versionCode 16だけが含まれることを保存後とプレビューで確認する。
- [ ] 日英リリースノート、スクリーンショット、署名・パッケージ情報、Consoleのエラー・不足情報を確認する。
- [ ] Consoleに表示される手順に従って審査への変更送信とクローズドテストのリリースを進め、実際のステータスを記録する。
- [ ] 配信後、既存テスターが0.1.6（16）へ更新できることを確認する。今回は未実施。
- テスター・連続オプトインに関する過去の注意点は§5に保存する。現在のアカウント要件とProduction accessはConsoleで確認し、本書の文面整備でテスト要件達成・一般公開済みとは扱わない。

## 4. 公式参照先

- Apple: [Provide information for a complete review](https://developer.apple.com/help/app-review/before-submitting-for-review/complete-review)
- Apple: [Choose a build to submit](https://developer.apple.com/help/app-store-connect/manage-builds/choose-a-build-to-submit/)
- Apple: [Submit an app](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app/)
- Google: [App testing requirements for new personal developer accounts](https://support.google.com/googleplay/android-developer/answer/14151465)
- Google: [Set up your app on the app dashboard](https://support.google.com/googleplay/android-developer/answer/9859454)
- Apple: [Platform version information（What's New／Review Notesの項目・上限）](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information)
- Google: [Prepare and roll out a release（リリースノートの上限・保存と送信）](https://support.google.com/googleplay/android-developer/answer/9859348?hl=en)

## 5. Build 15時点の提出計画・旧文面（履歴）

以下は2026-10-28更新前から残っていたBuild 15向けのチェック項目・文面を保存したもの。チェックの未完了状態は当時の記録であり、後日のアップロード状況は§0Aが優先する。現在の入力には§1〜3のBuild 16文面・手順を使い、以下をそのまま転記しない。

### 5.1. 両ストア共通（Build 15時点）

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

### 5.2. Apple App Store Connect（Build 15時点）

#### バイナリとバージョン

- [ ] Build 15をArchiveし、App Store Connectへアップロードする。
- [ ] Apple側の処理完了後、iOSアプリバージョン`0.1.5`のBuild欄でBuild 15を選択する。
- [ ] Export Complianceの質問または不足情報が表示された場合は回答する。
- [ ] Build 8など旧ビルドが選択されている場合は外し、Build 15へ差し替える。

#### Guideline 2.1: App Completeness

- [x] 実機動画①〜⑮をMP4でGoogle Driveへアップロードする。
- [x] 動画番号と機能を対応付ける撮影手順シートをGoogle Driveへアップロードする。
- [x] 実機とiPhone画面を同時に撮影した動画①〜⑮を用意した。抽出フレームで実機・画面を部分確認した。
- [ ] 登録、接続、主要LED操作、アプリ起動時自動接続、MCU再起動後自動再接続が、Build 15の動画として必要な操作を満たすことを最終確認する（番号・機能の部分照合は実施済み）。
- [x] Google Driveの動画①〜⑮と手順シートを「リンクを知っている全員・閲覧者」に設定した（2026-10-27）。
- [x] Googleからログアウトした実ブラウザーで、動画①〜⑮すべての再生開始と終端到達を確認した（2026-10-27）。シークレットウィンドウを使用したとの記録ではない。
- [ ] Review Notesへ動画URL、必要ハードウェア、確認手順、試験端末・OSを記載する。
- [ ] 審査完了まで動画を移動・削除せず、共有権限を維持する。

Appleは、専用ハードウェアが必要なアプリについて、物理Apple端末上のアプリがハードウェアとペアリング・操作する様子を示す動画をApp Review Informationへ提供するよう案内している。

#### Guideline 5.2.1: Intellectual Property

- [x] 知的財産・所有権確認書のWord原稿をGoogle Driveへアップロードした。
- [x] 単独所有者宣言書の原稿を `0.1.5 (Build 15)` へ更新し、動画対応表URLと2026-10-27の閲覧確認結果を記載した。未署名・非共有の原稿として管理している。
- [ ] ScepTRONIC名称、ロゴ、製品およびBLEハードウェアについて、単独所有・使用・配布権限の記載が事実と一致するか本人が確認し、裏付け資料を揃える。
- [ ] 氏名、住所、連絡先、発行日、Apple Developerアカウント名、Team ID、今回のSubmission IDを本人が確認・記入し、署名する。法人の存在・役職・社印など未確認の事実を補完しない。
- [ ] `com.FAE.ScepTRONIC` のApple App Storeでの配布権限に関する記載を本人が確認する。
- [ ] 確認・署名済みの書類を提出用PDFにし、所有を裏付ける原本・開発記録・契約書など実在する補足資料を必要に応じて添付する。
- [ ] App Review InformationのAttachmentへPDFを追加し、Review NotesとAppleへの返信で説明する。

#### メタデータと再提出

- [ ] スクリーンショットをBuild 15のUIへ更新する。
- [ ] 「このバージョンの最新情報」とReview NotesへBuild 8以降の累積変更を記載する。
- [ ] Privacy Policy URL、Support URL、連絡先、App Privacy、価格・配信地域を再確認する。
- [ ] Appleの未解決メッセージへ、Build 15、動画、知的財産書類を追加したことを返信する。
- [ ] `Add for Review`後、Draft Submissionで内容を確認し、`Submit for Review`を実行する。
- [ ] ステータスが`Waiting for Review`または`In Review`へ進むことを確認する。

#### Apple用リリース説明案

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

### 5.3. Google Play Console（Build 15時点）

#### バイナリとリリース

- [ ] AndroidのversionCodeが`15`、versionNameが`0.1.5`であることを確認する。
- [ ] 署名済みAABを作成し、既存のクローズドテストトラックへアップロードする。
- [ ] リリース名を例`0.1.5 (15)`として、リリースノートを日本語・英語で入力する。
- [ ] Application ID、Play App Signing、対象APIレベル、権限警告を確認する。
- [ ] エラーと警告を解決してテストリリースを開始する。
- [ ] 既存テスターがBuild 15へ更新できることを確認する。

#### ストア情報・ポリシー

- [ ] スクリーンショットと説明文をBuild 15のUI・機能へ合わせる。
- [ ] Data safety、Bluetooth権限、Privacy Policyの内容が実装と一致していることを確認する。
- [ ] 対象ユーザー、コンテンツレーティング、広告、データ収集回答を再確認する。
- [ ] 公開の概要に保留中の変更が残っていないことを確認する。

#### 12人・14日間のクローズドテスト

- Google公式要件は、**2023年11月13日以降に作成した個人デベロッパーアカウント**がProduction accessを初めて申請する場合に適用される。
- 対象アカウントでは、12人以上のテスターがクローズドテストへ14日間連続でオプトインしている必要がある。
- Build 15へ更新しただけで既存の連続オプトイン実績が自動的にリセットされる、という要件ではない。テスターをトラックから外したりオプトアウトさせたりせず、Play ConsoleのProduction access表示を確認する。
- すでにProduction accessが承認済みの場合、通常の更新ごとに12人・14日間を最初からやり直す手順ではない。
- Consoleが追加テストを要求した場合は、その画面の指示を優先する。

#### Google Play用リリースノート案

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

