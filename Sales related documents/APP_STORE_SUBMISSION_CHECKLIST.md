
最終更新: 2026-04-26

このチェック表は、以下の記事の流れに合わせて `septronics` 向けに整理したものです。

- Zenn: https://zenn.dev/shusuke_bridge/articles/b5debb31e857d2
- Qiita: https://qiita.com/ryouta33/items/a12ee3f99c3c5ae0d976

## 0. 最初に確定する項目

- [☑️] 正式アプリ名を確定する
  - 現在の iOS 表示名: `ScepTRONIC`
  - 確定名:`ScepTRONIC`
- [☑️] 最終 Bundle ID を確定する
  - 現在: `com.masacookie.septronics`
  - 確定値:`com.FAE.ScepTRONIC`
- [☑️] App Store の販売者名を確認する
  - Apple Developer アカウント種別:
  - App Store 上の表示名:
- [☑️] Privacy Policy URL を用意する
  - URL:[https://github.com/Fortuna-Advanced-Engineering](https://github.com/Fortuna-Advanced-Engineering/ScepTRONIC/tree/main)
- [☑️] サポート URL を用意する
  - URL:https://thebase.com/inquiry/sceptronic-base-shop?_gl=1*gqi4xr*_gcl_au*MTQ5NDQ1MzY4OC4xNzc3MjAxNTkx*_ga*MTcyMDQ1OTY2MS4xNzc3MjAxNTkx*_ga_574HL6KGKQ*czE3NzcyMDE1OTEkbzEkZzAkdDE3NzcyMDE1OTQkajU3JGwwJGgw
- [☑️] 必要なら利用規約 URL を用意する
  - URL:none
- [☑️] iPad 対応を残すか決める
  - 現状は iPhone / iPad 両対応
  - 方針:iPhone only

## 1. 現在のプロジェクト情報

- App 名表示: `ScepTRONIC`
- Bundle ID: `com.FAE.ScepTRONIC`
- Version: `0.1.4+5`
- Bluetooth 権限説明: 設定済み
- Local Network 権限説明: 設定済み
- 1024px App Icon: 設定済み
- Device Family: `1,2` なので iPad 対応あり

確認元:

- `septronics/ios/Runner/Info.plist`
- `septronics/ios/Runner.xcodeproj/project.pbxproj`
- `septronics/pubspec.yaml`
- `septronics/ios/Runner/Assets.xcassets/AppIcon.appiconset`

## 2. Apple Developer Program 参加確認

- [☑️] Apple Developer Program に加入済み
- [☑️] App Store Connect にログインできる
- [☑️] 2ファクタ認証付き Apple Account で運用できる
- [☑️ ] 必要な Team を選べる
- 確定Team:`Masaki Hayashi`

## 3. Bundle ID 確定

- [☑️] 公開用 Bundle ID を最終決定する
- [☑️] App Store Connect にアプリ作成する前に決め切る
- [☑️] Apple Developer の Identifiers で使用可能か確認する
- [☑️] 既存の App Store Connect レコードと衝突しないことを確認する

メモ:

- 確定 Bundle ID:`com.FAE.ScepTRONIC`
- 確認日:2026/04/29

## 4. 証明書とプロビジョニング確認

- [☑️] Xcode の `Signing & Capabilities` を開く
- [☑️ ] `Automatically manage signing` にチェックが入っている
- [☑️ ] Team が正しい
- [☑️ ] Provisioning Profile が有効
- [☑️ ] Signing Certificate が有効
- [☑️ ] 警告やエラーが出ていない

## 5. アプリ側設定の反映

- [☑️ ] `Runner` ターゲットの Bundle ID が公開用になっている
- [☑️ ] Team が公開用 Team になっている
- [☑️ ] 表記ゆれを解消する
  - `ScepTRONIC`
  - `septronics`
  - `septonic`
- [☑️] App 名、著作権表記、ブランド表記を最終確認する
- [☑️ ] Release ビルドで実機起動できる

## 6. アプリ本体の最終確認

- [☑️ ] Bluetooth スキャンが動く
- [☑️ ] Bluetooth 接続が動く
- [ ] Local Network 経由の MCU bridge 接続が動く
- [☑️ ] 主要画面が一通り開く
- [☑️ ] クラッシュしない
- [☑️ ] デバッグ表示や仮文言が残っていない
- [☑️ ] バージョン番号を最終化する
- [☑️ ] 審査に見せて困るテスト用データが入っていない

確認メモ:

- 確認端末:`a4os5nのiPhone`
- iOS バージョン:
- 確認者:`masacookie`

## 7. TestFlight / App Store 用ビルドをアップロード

- [☑️ ] ビルド対象を `Any iOS Device (arm64)` に変更する
- [☑️ ] `Product > Archive` を実行する
- [☑️ ] Archive 完了後、`Distribute App` を押す
- [☑️ ] `TestFlight & App Store` を選ぶ
- [☑️ ] 配布設定を確認してアップロードする
- [☑️ ] アップロード完了を確認する

アップロード記録:

- Build version: 0.1.4.6
- Upload 日時: 2026/04/29

## 8. App Store Connect の一般情報を入力

- [☑️ ] 新規 App を作成する
- [☑️ ] App Name を入力する
- [☑️ ] Primary Language を設定する
- [☑️ ] Bundle ID を選択する
- [☑️ ] SKU を設定する
- [ ] サブタイトルを入力する
- [☑️ ] カテゴリを設定する
- [☑️ ] 年齢区分を設定する
- [ ] 著作権表記を入力する
- [ ] 暗号化に関する質問に回答する

入力メモ:

- App Name:ScepTRONIC
- SKU:sceptronic-ios
- Primary Language:英語
- Category:スポーツ

## 9. 信頼と安全の設定

- [ ] Privacy Policy URL を入力する
- [ ] App Privacy のデータタイプ回答を入力する
- [ ] 取得データ、送信データ、追跡有無を見直す
- [ ] アプリ内権限説明と App Store の説明内容に矛盾がない

`septronics` で特に確認する項目:

- [ ] `google_fonts` の利用が審査回答に影響しないか確認する
- [ ] 外部解析 SDK を入れていないことを再確認する
- [ ] ログイン、課金、広告、通知、位置情報常時取得がないことを再確認する

## 10. 価格と配信設定

- [☑️ ] 価格を設定する
- [☑️ ] 配信国 / 地域を設定する
- [☑️ ] 無料アプリでも価格設定が完了している
- [ ] 配信除外したい地域があれば反映する

## 11. TestFlight の設定

- [☑️ ] アップロード済み build が表示されるまで待つ
- [☑️ ] TestFlight タブで build を確認する
- [☑️ ] 内部テスターを追加する
- [ ] 必要なら外部テスト前に内部テストを実施する
- [☑️ ] 実機で公開候補 build の最終確認を行う

テスター記録:

- 内部テスター:
- 確認結果:

## 12. 配信情報の設定

- [ ] スクリーンショットを用意する
- [☑️ ] プレビューを設定する
- [☑️ ] 概要を入力する
- [☑️ ] このバージョンの最新情報を入力する
- [☑️ ] キーワードを入力する
- [☑️ ] サポート URL を入力する
- [☑️ ] 必要ならマーケティング URL を入力する
- [☑️ ] 連絡先情報を入力する
- [☑️ ] 配信する build を選択する
- [☑️ ] App Store バージョンのリリース方法を設定する

スクリーンショット関連メモ:

- [ ] iPhone 用スクリーンショットを作成済み
- [ ] iPad 対応を残すなら iPad 用スクリーンショットも用意済み

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
- [ ] デモアカウントが必要なら入力する
- [ ] 特殊な操作がある場合は説明を書く
- [ ] Bluetooth / Local Network 利用理由をレビューメモに書く

レビューメモ下書き:

```text
This app connects to nearby BLE devices for stock control and diagnostics.
It also uses the local network only when connecting to an MCU bridge on the same LAN.
No account signup is required for basic use.
If needed, we can provide additional review instructions.
```

## 15. 審査提出

- [ ] 必須項目の未入力がない
- [ ] build が選択済み
- [ ] App Privacy が完了済み
- [☑️ ] 価格と配信設定が完了済み
- [ ] `Submit for Review` を実行する

提出記録:

- 提出日:
- 審査状態:

## 16. リリース

- [☑️ ] 自動公開か手動公開かを確認する
- [ ] 手動公開なら審査通過後にリリース操作を行う
- [ ] 公開後に App Store 表示を確認する
- [ ] ダウンロード、説明文、スクリーンショット、URL に問題がないか確認する

公開記録:

- 公開日:
- App Store URL:

## 17. 今の `septronics` で未確定のまま残りやすい項目

- [☑️ ] 正式アプリ名
- [☑️ ] 最終 Bundle ID
- [☑️ ] Privacy Policy URL
- [☑️ ] サポート URL
- [ ] iPad 対応を残すかどうか
- [ ] App Privacy 回答内容



