# GC9A01 Display Assets

ESP-12S（ESP8266）と 240×240 IPS（GC9A01）パネルで大神ミオの画像を表示するための補助データです。  
著作権保護素材は含めていません。手元で正規に入手した画像を本ディレクトリの手順で変換してください。

## ディレクトリ構成

- `convert_to_rgb565.py` – 画像を 240×240/RGB565 (big-endian) のバイナリへ変換するツール。
- `mio_gc9a01_display.ino` – LittleFS 内の `mio_rgb565.bin` を読み取って GC9A01 に描画する Arduino スケッチ。
- `tissue_counter_display.ino` – 画像を使わず、ティッシュ枚数カウンター UI を表示するサンプル。ボタン入力で目標枚数設定と残数更新を行います。
- `assets/` – 画像の変換入力を置く場所（空）。
- `data/` – LittleFS へ書き込む完成バイナリを置く場所。`mio_rgb565.bin` を配置し `ESP8266 LittleFS Data Upload` などで転送します。

```
tissue_counter/
└── gc9a01_display/
    ├── README.md
    ├── convert_to_rgb565.py
    ├── mio_gc9a01_display.ino
    ├── assets/
    └── data/
```

## 1. ハードウェア接続（例）

| GC9A01 | ESP-12S (ESP8266) |
| ------ | ----------------- |
| VCC    | 3.3 V（>=200 mA） |
| GND    | GND               |
| SCL    | GPIO14 (HSPI CLK) |
| SDA    | GPIO13 (HSPI MOSI)|
| CS     | GPIO15            |
| DC     | GPIO2             |
| RST    | GPIO5             |
| BL     | GPIO4（PWM で輝度制御） |

※ 3.3 V 系で統一。電源ラインに 10 µF 以上のバルクコンデンサを入れると安定します。

## 2. 画像変換

1. 正方形にトリミング済みの大神ミオ画像（PNG/JPG 等）を `assets/` へ保存。
2. Pillow をインストール: `pip install pillow`.
3. 変換コマンドを実行。

```bash
cd tissue_counter/gc9a01_display
python convert_to_rgb565.py assets/oogami_mio.png data/mio_rgb565.bin
```

`--size` や `--rotate`, `--center-crop` オプションで微調整可能です。

## 3. ファームウェア側

1. `TFT_eSPI` ライブラリを導入し、`User_Setup.h` で `GC9A01_DRIVER` と上記ピン配置を定義（例はスケッチ内のコメント参照）。
2. Arduino IDE で `ESP8266 LittleFS Data Upload` プラグインを用い、`data/` を LittleFS に書き込む。
3. `mio_gc9a01_display.ino` をビルド・書き込み。

起動すると `data/mio_rgb565.bin` を中央に表示します。SPIFFS/LittleFS に別のバイナリをアップロードすれば差し替え可能です。

## 4. ティッシュ枚数カウンター UI（画像なし）

`tissue_counter_display.ino` は TFT_eSPI を使ってカウンターと HX711 の生値を同時表示します。接続例は以下の通りです（必要に応じてコード中の `PIN_*` を変更してください）。

| 機能               | 推奨ピン | 説明                                                                 |
| ------------------ | -------- | -------------------------------------------------------------------- |
| BTN_SET            | GPIO12   | 1回押すごとに目標枚数を +5（最大200）                               |
| BTN_COUNT          | GPIO0    | 短押しで残り枚数 -1、長押し（0.8秒以上）で残り枚数を目標値に戻す（注意1） |
| HX711 DATA         | GPIO5    | HX711 の DATAOUT（DT）                                               |
| HX711 SCK          | GPIO4    | HX711 の SCK                                                         |
| BACKLIGHT (PWM)    | GPIO2    | `analogWrite` で輝度調整                                             |

注意1: GPIO0 は起動時 LOW だと書き込みモードに入るため、リセット時はボタンを押さないでください。

起動時は目標50枚/残り50枚です。HX711 の生値は 200ms ごとに平均 5 回でサンプリングされ、LCD とシリアルモニタ（115200bps）へ同時に出力されます。HX711 が接続されていない場合は `HX711 raw: waiting...` と表示されます。

## 5. よくあるトラブル

- **色が入れ替わる** – `tft.setSwapBytes(true);` を忘れているか、RGB565 のエンディアンが一致していません。
- **縞模様／同期しない** – SPI クロックを 20 MHz などへ下げて確認。配線が長い場合はシリーズ抵抗を入れると改善します。
- **起動時にリセットループ** – GPIO0/GPIO2/GPIO15 のレベルに注意。上記ピン割り当てを変更するか、プルアップ/プルダウンを適切に配置します。

必要に応じてアニメーションや複数画像切り替えなどを追加してください。
