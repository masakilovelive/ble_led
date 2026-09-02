# ScepTRONIC App Store 提出前チェック表

最終更新: 2026-08-30

このチェック表は、以下の記事の流れに合わせて `ScepTRONIC` 向けに整理したものです。

- Zenn: https://zenn.dev/shusuke_bridge/articles/b5debb31e857d2
- Qiita: https://qiita.com/ryouta33/items/a12ee3f99c3c5ae0d976

## 0. 最初に確定する項目

- [ ] 正式アプリ名を確定する
  - 現在の iOS 表示名: `ScepTRONIC`
  - 確定名:
- [ ] 最終 Bundle ID を確定する
  - 現在: `com.FAE.ScepTRONIC`
  - 確定値:
- [ ] App Store の販売者名を確認する
  - Apple Developer アカウント種別:
  - App Store 上の表示名:
- [ ] Privacy Policy URL を用意する
  - URL:
- [ ] サポート URL を用意する
  - URL:
- [ ] 必要なら利用規約 URL を用意する
  - URL:
- [x] iPad 対応を残すか決める
  - 方針: iPhone 専用とし、iPad 対応は含めない
- [x] Apple Watch 対応方針を決める
  - 方針: 初回リリースには含めない

## 1. 現在のプロジェクト情報

- App 名表示: `ScepTRONIC`
- Bundle ID: `com.FAE.ScepTRONIC`
- Version: `0.1.4+8`
- Bluetooth 権限説明: 設定済み
- 1024px App Icon: 設定済み
- Device Family: `1` なので iPhone 専用

確認元:

- `septronics/ios/Runner/Info.plist`
- `septronics/ios/Runner.xcodeproj/project.pbxproj`
- `septronics/pubspec.yaml`
- `septronics/ios/Runner/Assets.xcassets/AppIcon.appiconset`

## 2. Apple Developer Program 参加確認

- [ ] Apple Developer Program に加入済み
- [ ] App Store Connect にログインできる
- [ ] 2ファクタ認証付き Apple Account で運用できる
- [ ] 必要な Team を選べる

## 3. Bundle ID 確定

- [ ] 公開用 Bundle ID を最終決定する
- [ ] App Store Connect にアプリ作成する前に決め切る
- [ ] Apple Developer の Identifiers で使用可能か確認する
- [ ] 既存の App Store Connect レコードと衝突しないことを確認する

メモ:

- 確定 Bundle ID:
- 確認日:

## 4. 証明書とプロビジョニング確認

- [ ] Xcode の `Signing & Capabilities` を開く
- [ ] `Automatically manage signing` にチェックが入っている
- [ ] Team が正しい
- [ ] Provisioning Profile が有効
- [ ] Signing Certificate が有効
- [ ] 警告やエラーが出ていない

## 5. アプリ側設定の反映

- [ ] `Runner` ターゲットの Bundle ID が公開用になっている
- [ ] Team が公開用 Team になっている
- [ ] 表記ゆれを解消する
  - 公開表示名が `ScepTRONIC` に統一されている
  - `septronics` と `septonic` が公開面に残っていない
- [ ] App 名、著作権表記、ブランド表記を最終確認する
- [ ] Release ビルドで実機起動できる

## 6. アプリ本体の最終確認

- [ ] Bluetooth スキャンが動く
- [ ] Bluetooth 接続が動く
- [ ] LED の基本操作が動く
- [ ] 主要画面が一通り開く
- [ ] クラッシュしない
- [ ] デバッグ表示や仮文言が残っていない
- [ ] バージョン番号を最終化する
- [ ] 審査に見せて困るテスト用データが入っていない

確認メモ:

- 確認端末:
- iOS バージョン:
- 確認者:

## 7. TestFlight / App Store 用ビルドをアップロード

- [x] ビルド対象を `Any iOS Device (arm64)` に変更する
- [x] `Product > Archive` 相当の Release Archive を実行する
- [x] Archive 完了後、`Distribute App` 相当の配布処理を実行する
- [x] `TestFlight & App Store`（`app-store-connect`）を選ぶ
- [x] 配布設定を確認してアップロードする
- [x] アップロード完了を確認する

アップロード記録:

- Build version: `8`（build 7のFramework検証エラー修正後）
- Archive result: `0.1.4 (8) / ARCHIVE SUCCEEDED`
- Upload 日時: `2026-08-30 06:55 PDT`（Apple受領済み、処理中）

## 8. App Store Connect の一般情報を入力

- [ ] 新規 App を作成する
- [ ] App Name を入力する
- [ ] Primary Language を設定する
- [ ] Bundle ID を選択する
- [ ] SKU を設定する
- [ ] サブタイトルを入力する
- [ ] カテゴリを設定する
- [ ] 年齢区分を設定する
- [ ] 著作権表記を入力する
- [ ] 暗号化に関する質問に回答する

入力メモ:

- App Name:
- SKU:
- Primary Language:
- Category:

## 9. 信頼と安全の設定

- [ ] Privacy Policy URL を入力する
- [ ] App Privacy のデータタイプ回答を入力する
- [ ] 取得データ、送信データ、追跡有無を見直す
- [ ] アプリ内権限説明と App Store の説明内容に矛盾がない

`ScepTRONIC` で特に確認する項目:

- [ ] `google_fonts` の利用が審査回答に影響しないか確認する
- [ ] 外部解析 SDK を入れていないことを再確認する
- [ ] ログイン、課金、広告、通知、位置情報常時取得がないことを再確認する

## 10. 価格と配信設定

- [ ] 価格を設定する
- [ ] 配信国 / 地域を設定する
- [ ] 無料アプリでも価格設定が完了している
- [ ] 配信除外したい地域があれば反映する

## 11. TestFlight の設定

- [ ] アップロード済み build が表示されるまで待つ
- [ ] TestFlight タブで build を確認する
- [ ] 内部テスターを追加する
- [ ] 必要なら外部テスト前に内部テストを実施する
- [ ] 実機で公開候補 build の最終確認を行う

テスター記録:

- 内部テスター:
- 確認結果:

## 12. 配信情報の設定

- [ ] スクリーンショットを用意する
- [ ] プレビューを設定する
- [ ] 概要を入力する
- [ ] このバージョンの最新情報を入力する
- [ ] キーワードを入力する
- [ ] サポート URL を入力する
- [ ] 必要ならマーケティング URL を入力する
- [ ] 連絡先情報を入力する
- [ ] 配信する build を選択する
- [ ] App Store バージョンのリリース方法を設定する

スクリーンショット関連メモ:

- [x] iPhone 用スクリーンショットを作成済み
  - 保存先: `Sales related documents/app-store-screenshots/`
  - 6.9 inch: `1320 x 2868`（提出時の必須枠）
  - 6.3 inch: `1206 x 2622`
  - 6.1 inch: `1170 x 2532`
  - 5.5 inch: `1242 x 2208`
- [x] iPad 用スクリーンショットは不要（iPhone 専用）

登録メモ:

- 概要:
- キーワード:
- このバージョンの最新情報:

## 13. Web ページ類の準備

- [ ] Privacy Policy ページを公開済み
- [ ] サポート / お問い合わせページを公開済み
- [ ] 必要なら利用規約ページを公開済み
- [ ] URL が公開状態で正常に開ける
- [ ] スマホから見ても崩れない

URL 一覧:

- Privacy Policy:
- Support:
- Terms:

## 14. App Review 情報の入力

- [ ] レビュー担当者向けの連絡先を入力する
- [x] デモアカウントは不要（ログイン機能なし）
- [x] Bluetooth 機器なしで確認できる Demo Mode の操作を書く
- [x] Bluetooth 利用理由をレビューメモに書く

レビューメモ下書き:

```text
ScepTRONIC controls two nearby BLE-enabled LED stock devices (Stock A and Stock B).
No account, login, or physical accessory is required for App Review.

To review all controls without hardware:
1. On the BLUETOOTH SETTING screen, tap START DEMO.
2. On STOCK SELECT, tap OPEN for Stock A or Stock B.
3. Adjust Color Tone, Color Strength, and Brightness, then tap SET for Head or Tip.
4. Tap the link icon in the upper-right corner to enable BOTH SYNCRO. Color and effect changes then apply to both virtual stocks.
5. Heart Beat and Rainbow can also be enabled for Head and Tip.

Demo Mode uses virtual Stock A/B state and does not scan, connect, or send commands to a Bluetooth device. Tap RETURN TO LIVE SCAN to leave Demo Mode.
```

## 15. 審査提出

- [ ] 必須項目の未入力がない
- [ ] build が選択済み
- [ ] App Privacy が完了済み
- [ ] 価格と配信設定が完了済み
- [ ] `Submit for Review` を実行する

提出記録:

- 提出日:
- 審査状態:

## 16. リリース

- [ ] 自動公開か手動公開かを確認する
- [ ] 手動公開なら審査通過後にリリース操作を行う
- [ ] 公開後に App Store 表示を確認する
- [ ] ダウンロード、説明文、スクリーンショット、URL に問題がないか確認する

公開記録:

- 公開日:
- App Store URL:

## 17. 今の `ScepTRONIC` で未確定のまま残りやすい項目

- [ ] 正式アプリ名
- [ ] 最終 Bundle ID
- [ ] Privacy Policy URL
- [ ] サポート URL
- [x] iPad 非対応（iPhone 専用）
- [ ] App Privacy 回答内容
