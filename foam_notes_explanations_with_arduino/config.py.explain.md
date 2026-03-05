---
tags: [BLE, Python, Foam, 解説]
---

# [[config.py]] 解説

**役割の要約**：
- 共通設定（アドレス、スキャン時間、対象名、特性UUIDなど）を集中管理します。

**実行例**：
```bash
例: `python config.py` を実行します。必要に応じて `config.py` を編集してください。
```

## コード全文
```python
import config
# ここに後で値を入れます。最初は空でOK。
ADDRESS = "C0:2C:ED:68:C1:EC"          # 例: "E3:12:AB:34:56:78"
WRITE_CHAR_UUID = config.CHR_UUID  # 例: "6e400002-b5a3-f393-e0a9-e50e24dcca9e" など
DEVICE_NAME_HINT = "XIAO"  # スキャン結果の候補を絞るヒント。分からなければ "" でもOK

```

## 行単位の読み解き（ポイント）
- 主要APIの呼び出しと入出力を中心に構成されています。
