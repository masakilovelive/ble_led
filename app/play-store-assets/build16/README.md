# ScepTRONIC Build 16 Google Play screenshots

作成日: 2026-11-05（America/Los_Angeles）

Google Playの「スマートフォンのスクリーンショット」差し替え用画像。アプリのBuild 16ソースをAndroidエミュレーターで動かし、画面を直接取得した。

## 提出する画像

| 順番 | ファイル | 内容 |
| --- | --- | --- |
| 1 | [01-stock-select.png](phone-screenshots/01-stock-select.png) | STOCK SELECT。A/B CONNECTED、残量82%／75%、Stock AはRainbow、Stock Bは単色 |
| 2 | [02-stock-a-setting.png](phone-screenshots/02-stock-a-setting.png) | STOCK A SETTING。Head／TipのRAINBOWバッジ、色・明るさ、Heart Beat／Rainbow操作 |
| 3 | [03-stock-b-setting.png](phone-screenshots/03-stock-b-setting.png) | STOCK B SETTING。Head／TipのSOLIDバッジ、シアン系の単色設定 |

まとめて取得する場合は[ScepTRONIC-Build16-GooglePlay-Screenshots.zip](ScepTRONIC-Build16-GooglePlay-Screenshots.zip)を使用する。ZIPを展開し、上記順番で3枚のPNGを登録する。

## 画像仕様と確認

- 各画像1080×1920ピクセル、縦9:16、24-bit RGB PNG（アルファチャンネルなし）。
- アプリの描画内容を切り抜いたり引き伸ばしたりせず、Android画面をそのまま取得した。PNGの再エンコード時には不透明なアルファチャンネルだけを除去し、RGB画素が変化していないことを比較確認した。
- 3枚とも目視で確認し、Head／TipとRAINBOW／SOLIDの文字が枠内に収まり、主要操作が表示されていることを確認した。
- Google Playのスマートフォン画像要件に合わせた。参照: [Google公式のプレビューアセット要件](https://support.google.com/googleplay/android-developer/answer/9866151?hl=en)。アイコンやフィーチャーグラフィックの新規作成は今回の対象に含まない。

## 撮影条件

- 製品ソース: [`b0bee5fae3d84fd7a40e1d05b74e841723226814`](https://github.com/masakilovelive/ble_led/commit/b0bee5fae3d84fd7a40e1d05b74e841723226814)（`app/`）。撮影時のmainは`bcbd1203974e6982f53345fe502908bdcc8b3984`で、以降の変更は進捗文書のみ。
- アプリ: `com.FAE.ScepTRONIC`、versionName `0.1.6`、versionCode `16`。エミュレーターのパッケージ情報でも確認した。
- 実行環境: Android 16 / API 36、Pixel 7ベースの一時エミュレーター。画面1080×1920、密度320dpi、フォント倍率1.0。
- Flutter `3.38.9` / Dart `3.10.8`。既存の`SCEPTRONIC_SCREENSHOT=true`を指定した撮影専用APKで取得。製品のDartソース・ファームウェアは変更していない。
- CONNECTED表示・残量82%／75%は既存の撮影専用モードの表示用データ。実機の接続・電池測定を証明する画像ではない。時刻9:41などのシステム表示にもAndroidの撮影用設定を使用した。
- 製品UIにはSTART DEMOやDemoバナーを表示しない。今回の撮影専用APKはストアへアップロードしていない。

撮影用ビルドコマンド:

```sh
flutter build apk --debug \
  --dart-define=SCEPTRONIC_SCREENSHOT=true \
  --build-name=0.1.6 --build-number=16
```

## Consoleへの反映状況

画像の作成とGitHubへの保存まで完了。Google Play Consoleへの登録・保存・審査送信は今回実施していない。iOSのスクリーンショット登録状況とは分けて管理する。
