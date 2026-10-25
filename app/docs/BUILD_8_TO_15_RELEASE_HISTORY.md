# ScepTRONIC Build 8–15 変更履歴

最終更新: 2026-10-25

## この文書の目的

App Storeへ提出したBuild 8を基準として、Build 15までに行った製品版アプリの変更を整理する。Build 15は現在の再提出候補で、iOS実機（iPhone 16／iOS 26.2.1）へインストールして主要なAuto reconnect動作を確認済み。

## ビルド別履歴

| Build | バージョン | 主な位置付け・変更 | 確認状況 |
|---|---|---|---|
| 8 | 0.1.4 (8) | Appleへ提出した基準ビルド。旧レビュー案にはDemo Mode、旧Launch Image、登録済みデバイス識別子表示、旧接続説明が含まれていた。 | App Store Connectへのアップロード記録あり。Apple審査でGuideline 2.1（App Completeness）および5.2.1（Intellectual Property）の対応が必要になった。 |
| 9 | 中間ビルド | Build 8以降の修正途中で使用した中間番号。独立した確定リリース仕様としては扱わず、変更はBuild 10以降へ集約した。 | ストア提出対象外。 |
| 10 | 0.1.4系 | 製品版から`START DEMO`／Demo Modeを除外。Launch Screenを製品UIへ合わせ、表示デバイス名を`Noxel-1`／`Noxel-2`へ統一。登録済みカード下部のUUID／MAC相当識別子を非表示化。 | iOS実機へインストールして画面を確認。 |
| 11 | 中間検証ビルド | Auto reconnectの起動時動作、登録情報保持、手動接続との関係を確認するための中間ビルド。確定仕様とUI説明はBuild 12へ集約した。 | ストア提出対象外。 |
| 12 | 0.1.5 (12) | `Auto reconnect`をONにした場合の起動時自動接続を追加。OFFの場合は起動時接続と切断後再接続を停止し、手動接続は可能とした。接続失敗時も登録情報を保持。Bluetooth SettingのInformation「4. Connect」を更新。STOCK A/B SETTING右上のリンク状態アイコンを削除。 | `flutter analyze`およびテスト合格。iOS IPA／Android AABを作成。 |
| 13 | 0.1.5 (13) | iOSで保存UUIDが未検出のまま直接接続される問題に対応。保存デバイスへの接続前スキャンを追加。誤解を招く`Auto reconnect is waiting for the registered devices.`表示を削除。 | iOS実機へインストール。ただしBluetooth Setting画面の通常スキャン後でないと安定しない事象を確認。 |
| 14 | 0.1.5 (14) | アプリ起動時にA/B共通スキャンを1回実行し、`Noxel-1`／`Noxel-2`をiOSへ認識させてから接続する方式へ変更。 | iOS実機へインストール。起動時経路を改善。 |
| 15 | 0.1.5 (15) | アプリ起動中のMCU再起動にも対応。切断後のA/B個別スキャン競合を廃止し、共通スキャン→検出できた側を接続→未検出側のみ再試行する方式へ変更。 | iPhone 16／iOS 26.2.1で、(1) MCU起動後にアプリ起動、(2) アプリ起動中にMCU再起動、の両方でBluetooth Setting画面を開かず自動接続・再接続することを確認。解析エラーなし、テスト5件合格。 |

## Build 15の確定仕様

- 表示デバイス名は`Noxel-1`と`Noxel-2`。
- 登録カードにはデバイス名のみを表示し、UUID／MAC相当識別子は表示しない。
- 製品版にDemo Modeおよび`START DEMO`を含めない。
- Auto reconnect ON:
  - 登録済みデバイスがある場合、アプリ起動時に共通スキャン後、自動接続する。
  - アプリ起動中にMCUが再起動または一時切断した場合、共通スキャン後、自動再接続する。
  - 片側だけ未検出の場合、接続済み側を維持し、未検出側だけ再試行する。
- Auto reconnect OFF:
  - アプリ起動時の自動接続と切断後の自動再接続を行わない。
  - `CONNECT`／`CONNECT BOTH`による手動接続は可能。
- 自動接続に失敗してもNoxel-1／Noxel-2の登録情報を削除しない。
- 手動で切断したデバイスへは直ちに自動再接続しない。
- STOCK A/B SETTING右上に旧リンク状態アイコンを表示しない。A+B同期操作はSTOCK SELECT側の導線を使用する。
- 充電電圧検知、LED制御、Bluetoothボンディングを変更するファームウェア修正はBuild 8–15のアプリ変更に含まれない。

## Build 15で実施済みの確認

- `flutter analyze`: 問題なし。
- Flutterテスト: 5件合格。
- iOS Releaseビルド: 成功。
- iOS実機インストール: `ScepTRONIC 0.1.5 (15)`を確認。
- MCU起動→アプリ起動: Bluetooth Setting画面へ移動せず自動接続。
- アプリ起動中→MCU再起動: Bluetooth Setting画面へ移動せず自動再接続。

## 提出前に残る確認

- Android実機でBuild 15と同じ起動時接続・MCU再起動後再接続を確認する。
- Auto reconnect OFFの起動時非接続、手動接続、設定値保持をiOS／Android両方で確認する。
- 色、明るさ、Head、Tip、Heart Beat、Rainbow、A+B同期、充電検知・電圧表示の回帰試験を行う。
- Release版にDemo Mode、デバッグ表示、UUID／MAC相当識別子がないことを最終確認する。
- Build 15用IPA／AABを作成し、成果物のハッシュと作成日時を保存する。
