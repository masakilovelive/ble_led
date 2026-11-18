ScepTRONIC 0.1.6 (Build 16) — 4画面・10サイズ再出力
作成日: 2026-11-18 / America/Los_Angeles

【画像の内容】
01-stock-select.png       Stock Select / A:82%・Rainbow、B:75%・単色
02-color-setting.png      Stock A Setting / Head・TipのRAINBOW表示
03-bluetooth-setting.png  Bluetooth Setting / Auto reconnect・デバイス名
04-splash.png             起動画面（参考・保管用）

【サイズ一覧: 幅×高さpx、各4枚】
android/phone-1080x1920                     1080×1920 / 論理幅540dp
android/tablet-7-inch-1080x1920             1080×1920 / 論理幅720dp
android/tablet-10-inch-1440x2560            1440×2560 / 論理幅960dp
ios-ui-renders/6.9-inch                    1320×2868 / 論理幅440pt
ios-ui-renders/6.3-inch                    1206×2622 / 論理幅402pt
ios-ui-renders/6.1-inch                    1170×2532 / 論理幅390pt
ios-ui-renders/5.5-inch                    1242×2208 / 論理幅414pt
ios-ui-renders/ipad-13-inch                2064×2752 / 論理幅1032pt
ios-ui-renders/ipad-12.9-inch              2048×2732 / 論理幅1024pt
ios-ui-renders/ipad-11-inch                1668×2420 / 論理幅834pt

すべて24-bit RGB PNG、アルファなし。旧画像の拡大・縦横の引き伸ばしや
黒帯追加ではなく、各ビューポートでBuild 16のウィジェットを描画した。
PNG再エンコード前後でRGB画素が同一であることを照合。
IMAGE_MANIFEST.csvに各寸法・形式・SHA-256を記録。
previews-not-for-uploadは確認用の縮小一覧であり、提出画像ではない。

【Android画像の撮影方法】
保存済み撮影専用APK（versionName=0.1.6 / versionCode=16）を、
アカウント未登録の専用Android 16/API 36エミュレータで実行して画面取得。
使用APKのSHA-256:
558969f1e30884b1fcb5f1bfba1223c107eac2d8e5bde1055604aef831dd219e
Pixel 7ベースの同一AVDで解像度と密度を変更し、スマートフォン・7インチ相当・
10インチ相当の論理幅を再現。異なる実物のタブレットでの動作保証ではない。
密度は順に320/240/240dpi。フォント倍率1.0。OSバーを含むADB直接キャプチャ。
撮影専用AVDではOSの通知アイコンだけを非表示にし、電池表示を100%に設定。
OS時計は実際の撮影時刻。画像上から通知やOSロゴを描き消す加工はしていない。
SCEPTRONIC_SCREENSHOT=trueの既存撮影モードを使用。
CONNECTED・82%/75%は表示用データで、ハードウェア通信の証明ではない。
Bluetooth Settingは登録済みNoxel-1/Noxel-2の未接続状態を表示する。
これはStock Selectの撮影用CONNECTED表示と区別する。
実テスターのエミュレータ・Googleアカウント・導入記録は変更していない。

【iPhone・iPadサイズ画像の生成方法と制限】
iOS 26.2のiPhone 17 Pro Simulator上のFlutterエンジンで、各サイズを
論理幅・高さとして製品の実ウィジェットを再レイアウトし、RepaintBoundaryで
直接PNG化した「UI描画画像」。各機種のSimulatorを個別起動した画面写真ではない。
OSの時刻・電池・ホームインジケータ等は画像に含めていない。
製品のBleLedAppのテーマを使用し、iOSプラットフォーム設定で描画。
撮影専用エントリーポイント: tool/capture_build16_ios.dart
登録・CONNECTED・電池残量は撮影用の固定データ。BLE走査は撮影ホストで停止。
これらは製品の新ビルドや機能追加ではなく、製品にはこのホストを組み込まない。
特にiPad用は参考画像。現行iOS製品のTARGETED_DEVICE_FAMILYは1（iPhone専用）。
iPad対応・iPad審査提出が完了したという意味ではない。
App Store提出の最終画像にする場合は、対象端末/Simulatorで製品版の表示との
一致を確認すること。UI描画画像を実機キャプチャの証拠として使用しないこと。
5.5インチなど高さの短い画面では、Stock Selectの下端操作やBluetoothの
SCAN RESULTSはスクロール下にある。全内容を1画面に縮小合成してはいない。

【Build 16との照合】
製品Dartソース: b0bee5fae3d84fd7a40e1d05b74e841723226814 のapp/lib/。
今回の撮影前にローカルseptronics/lib/の全ファイルとバイト単位で一致を確認。
pubspec.yamlとpubspec.lockも同じコミットとバイト単位で一致。
アプリの機能・製品ソース・ファームウェア・提出済みIPA/AABは変更していない。
撮影用iOSホストは別エントリーポイントで、ストアへアップロードしていない。
Flutter 3.38.9 / Dart 3.10.8。

【掲載時の注意・現在の状態】
依頼に合わせて起動画面も全サイズに収録したが、機能を伝える操作画面01〜03を
掲載の中心とする。以前のApp Store審査対応と同様、起動画面04は原則参考用。
画像出力・検証後、ユーザーからGitHubへのアップロードとApp Store Connectへの
iPhone画像登録の依頼あり。GitHub保存対象はこのフォルダーと撮影用ツール。
ストア登録・審査送信の完了を意味しない。登録状況はUPLOAD_STATUS.txtを参照。
旧版画像および11月5日版3枚セットは上書きしていない。
撮影後、今回だけ作成したアカウント未登録のAndroid撮影用AVDは削除する。
他のエミュレータ・テスターのアカウントやアプリデータは保持する。

Google公式の画像要件（2026-11-18参照）:
https://support.google.com/googleplay/android-developer/answer/9866151?hl=en
Android用は9:16の縦長、1080px以上、RGB PNGとした。

【再実行】
Android: python3 tool/capture_build16_android.py
  同スクリプトは専用AVD名を検査する。テスター端末へは実行しない。
iOS UI: flutter build ios --simulator --debug --no-pub
  -t tool/capture_build16_ios.dart --dart-define=SCEPTRONIC_SCREENSHOT=true
  --build-name=0.1.6 --build-number=16
  実行するとアプリDocuments/build16-ios-ui-rendersへ28枚生成。
検証・ZIP化: python3 tool/package_build16_captures.py

【検証】
40枚の寸法・不透明性・RGB PNG形式・再エンコード時の画素同一性を機械検査。
10サイズすべての4枚一覧を目視確認。色設定のHead/TipとRAINBOW文字の
はみ出しやFlutterのエラー画面がないことを確認。
撮影用Dartエントリーポイントはflutter analyzeでNo issues found。
撮影とZIP化のPythonスクリプトはpy_compile成功。

バッテリー・色・登録名に関するデータは撮影用。実利用やGoogle Playの
テスター関与・継続オプトインの証拠としては扱わない。
