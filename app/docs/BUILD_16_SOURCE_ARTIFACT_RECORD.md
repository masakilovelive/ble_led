# Build 16 ソースと保存済み成果物の対応記録

確認日: 2026-11-04（America/Los_Angeles）

対象: ScepTRONIC `0.1.6 (Build 16)`、iOS Bundle ID / Android Application ID `com.FAE.ScepTRONIC`。

## ソースの保存先

- ソース反映コミット: [`b0bee5fae3d84fd7a40e1d05b74e841723226814`](https://github.com/masakilovelive/ble_led/commit/b0bee5fae3d84fd7a40e1d05b74e841723226814)
- 元の作業ディレクトリ: `/Users/masacookie/ski_led_app_ios_work/ble_led/septronics/`
- GitHubの正式なアプリディレクトリ: `app/`
- `app/pubspec.yaml`: `version: 0.1.6+16`
- Flutter `3.38.9` / Dart `3.10.8`。依存パッケージは同コミットの`app/pubspec.lock`を参照。

バージョン番号だけでなく、元の作業ディレクトリにあるDartソース、依存定義・lockfile、製品画像、iOS/Android設定および既存テストを反映した。`app/lib/`は元の製品ソースとファイル単位で一致を確認した。製品ソースから既に削除されていた出荷検査・耐久試験・LANブリッジ等の開発用ファイルは、GitHub上の製品ソースからも除外した。旧版は親コミット以前のGit履歴に残る。製品アプリの既存ドキュメント・ファームウェア・配布用補助スクリプトは保持した。

mainに未反映だったBuild 8〜16の累積差分を含む。自動接続・再接続、端末名判定、識別子非表示、Demoの入口除去、起動画面、アイコン、権限・署名設定などを含み、すべてがBuild 16で新規追加されたという意味ではない。mainとの差分にはバッテリー残量換算実装の相違も含む。今回新しい換算式を設計したのではなく、ローカルの製品ソースをそのまま保存したもの。

Build 16として記録されている新規画面修正は、Head/Tip見出しの可変幅・縮小表示と、RAINBOW等の状態バッジのcompact表示。

| ファイル | Git blob SHA-1 |
| --- | --- |
| `app/lib/screens/led_setting_screen.dart` | `83c999a8fe98843d3f94e311f6a75a8fe6840a42` |
| `app/lib/screens/sceptronic_ui.dart` | `7c857f30cb0ff40b3c6e3a999f6b6e6679bb0928` |
| `app/lib/ble/stock_controller.dart` | `92d4890f82732e31390b8455cafb35b82f0ae04e` |
| `app/pubspec.yaml` | `1b9aa0cee4b2dca4b021895ab2ad799553f67dc0` |
| `app/pubspec.lock` | `fe83079303d545e55da045a499848140a5a74a7e` |

## 保存済みIPAとAAB

元の作業ディレクトリ配下の保存ファイルを確認した。バイナリはGitHubへ追加せず、上書きされやすい`build/`とは別に`artifacts/releases/`へ同一内容を保存した。

| 項目 | iOS | Android |
| --- | --- | --- |
| 元ファイル（元作業ディレクトリからの相対パス） | `build/ios/ipa/ScepTRONIC.ipa` | `build/app/outputs/bundle/release/app-release.aab` |
| 保存コピー | `artifacts/releases/ScepTRONIC-0.1.6-16.ipa` | `artifacts/releases/ScepTRONIC-0.1.6-16.aab` |
| ファイルサイズ | 24,623,113 bytes | 41,820,237 bytes |
| ID | `com.FAE.ScepTRONIC` | `com.FAE.ScepTRONIC` |
| バージョン | `0.1.6` | `0.1.6` |
| Build | `16` | `16` |
| 内部確認箇所 | IPA内`Payload/Runner.app/Info.plist` | AAB内`base/manifest/AndroidManifest.xml`のprotobuf XML属性 |

SHA-256（2026-11-04取得）:

```text
ccfb2c8f116b32bcb7a2066a7ffe3739c3881be0b8b09938f1d36c2ef69d9e56  ScepTRONIC-0.1.6-16.ipa
c43d4494c8a0a32b1950f5126621a2104a742b711d64b20eb79cf9347eafd2f1  ScepTRONIC-0.1.6-16.aab
```

iOSの保存済み`DistributionSummary.plist`もBuild `16`を示し、`ExportOptions.plist`のmethodは`app-store-connect`。保存済み`ios/Flutter/Generated.xcconfig`は`FLUTTER_TARGET=lib/main.dart`、`FLUTTER_BUILD_NAME=0.1.6`、`FLUTTER_BUILD_NUMBER=16`で、DART_DEFINESにスクリーンショットモード指定はない。Androidの保存済み`android/local.properties`もrelease / versionName `0.1.6` / versionCode `16`を示す。端末固有パスや署名秘密情報を含むこれらのローカル設定ファイルはコミットしない。

## 対応確認の範囲

このコミットは、10月28日のビルド時点に作成されたコミットではなく、11月4日に保存したソースのスナップショット。アップロード時のソースコミットID・ファイルハッシュを当時記録していなかったため、今回の記録だけで「このコミットから当時の提出バイナリを生成した」と厳密に証明したことにはならない。

確認できたのは、元作業環境の製品ソース・バージョン設定・残存ビルド設定・保存済みIPA/AAB内部のIDとバージョン、および10月28日のアップロード作業記録の整合。ストア側バイナリとのハッシュ照合は未実施。今回のハッシュは以後のローカルファイル同一性確認に使用できる。

この記録整理のためのIPA/AAB再生成・ストア再アップロード・実機インストールは行っていない。

## 今回の検証

ソース反映先`app/`で次を実施した。

- `flutter pub get --enforce-lockfile`: 成功。
- `flutter analyze`: 問題なし。
- `flutter test`: 5件合格（起動、Demo初期無効、Noxelの大小文字判定、旧XIAO名互換、無関係な端末名の除外）。
- `plutil -lint`: iOS Info.plist / Xcode project.pbxprojともに成功。
- 元作業環境との`lib/`ファイル比較: 一致。

これらはネイティブのリリース再ビルドや実機BLE再試験を意味しない。ユーザーから2026-11-04に、必要な動作確認・画面修正の確認および動画・手順シート確認を完了したとの報告を受けた。端末・OS・操作ごとの詳細結果はこの報告では追加されていない。

## 今後再ビルドする場合

以下は現在のソースからの再ビルド例であり、当時実行したコマンドの完全なログではない。アップロード済みBuild 16を置換する目的では使わない。新しいバイナリをストアへ追加する場合は、別のBuild番号を使用する。

```sh
cd app
flutter pub get --enforce-lockfile
flutter build ipa --release --build-name=0.1.6 --build-number=16
flutter build appbundle --release --build-name=0.1.6 --build-number=16
```

署名は所有者の開発環境で設定する。Androidは`android/key.properties`とkeystore、iOSはApple Developerの署名権限が必要。証明書・秘密鍵・パスワードはGitHubへ追加しない。

## 過去Buildの保存状況

- iOS: `artifacts/releases/ScepTRONIC-0.1.5-12.ipa`があり、IPA内部のBuild `12`を確認。Xcode Archiveには`0.1.4 (7)`、`0.1.5 (15)`、`0.1.6 (16)`が残る。署名・端末対応を確認し、必要に応じて再署名・開発用書き出しする。App Store配布用IPAをそのまま実機へ直接インストールできるとは限らない。
- Android: `artifacts/releases/ScepTRONIC-0.1.5-11.aab`と`ScepTRONIC-0.1.5-12.aab`が残る。AABは直接インストールできず、端末用APK生成と署名確認が必要。旧版へのダウングレード時は保存データの互換性を確認する。
- TestFlightからの旧版インストールは、対象Buildがテスターへ提供され、有効期限内であることが条件。今回TestFlightの配信状態は確認していない。

全過去Buildのバイナリや完全なソーススナップショットが揃っているとは断定しない。
