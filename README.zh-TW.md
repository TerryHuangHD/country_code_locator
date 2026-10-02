# country_code_locator

[English](README.md) | **繁體中文** | [日本語](README.ja.md)

[![CI](https://github.com/TerryHuangHD/country_code_locator/actions/workflows/ci.yml/badge.svg)](https://github.com/TerryHuangHD/country_code_locator/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

適用於 Flutter 的離線 WGS 84 座標轉國家代碼查詢套件。套件只需載入一次內建且有版本控管的
邊界索引，之後即可同步回傳正式指派的 ISO 3166-1 Alpha-2 或 Alpha-3 代碼——不需要網路、
GPS、權限、平台地理編碼器或地圖服務 SDK。

> 本文件為翻譯版本；若內容有出入，以英文版 [README.md](README.md) 為準。

## 功能

- 安裝套件後即可完全離線查詢。
- 一次非同步初始化後，所有查詢皆為同步呼叫。
- 以純 Dart 實作空間網格、邊界框（bounding box）與點在多邊形內（point-in-polygon）判定。
- 支援 Polygon、MultiPolygon、孔洞、島嶼與跨換日線（antimeridian）。
- 共用邊界的判定具確定性，不受來源資料列順序影響。
- 僅輸出嚴格對應的正式 ISO Alpha-2/Alpha-3 代碼；佔位代碼與 `XK` 絕不會被回傳。
- 二進位資料經過驗證，包含格式版本、長度、語意檢查與 CRC-32 完整性保護。
- 可重現、以校驗碼鎖定版本的 Natural Earth 資料產生流程。

## 安裝

```shell
flutter pub add country_code_locator
```

邊界資源檔已由套件本身宣告，應用程式不需要在自己的 `pubspec.yaml` 中加入。

## 使用方式

在應用程式啟動時載入一個 locator，並在所有查詢中重複使用：

```dart
import 'package:country_code_locator/country_code_locator.dart';

final locator = await OfflineCountryCode.load();

final alpha2 = locator.lookup(
  latitude: 35.6812,
  longitude: 139.7671,
); // JP（預設）

final alpha3 = locator.lookup(
  latitude: 35.6812,
  longitude: 139.7671,
  format: CountryCodeFormat.alpha3,
); // JPN
```

對於海洋、未涵蓋或無代碼的陸地，以及落在不同代碼共用邊界上的點，`lookup` 會回傳 `null`。

每次查詢都可選擇 `CountryCodeFormat.alpha2` 或 `CountryCodeFormat.alpha3`。兩種格式共用
同一份已載入的幾何資料與邊界判定；預設為 Alpha-2。

### 輸入驗證

緯度必須為有限值且位於 `[-90, 90]`；經度必須為有限值且位於 `[-180, 180]`。無效值會拋出
`ArgumentError`。經度 `-180` 與 `180` 視為同一條經線。

### 自訂資源載入

擁有自己載入層的應用程式，可以直接從位元組驗證並初始化：

```dart
final locator = OfflineCountryCode.fromBytes(bytes);
```

`fromBytes` 會立即解碼所有執行期結構，且不會保留或修改傳入的 `Uint8List`。也可使用
`OfflineCountryCode.load(bundle: customBundle)` 搭配自訂的 Flutter `AssetBundle`。

## 結果規則

| 情況 | 結果 |
| --- | --- |
| 點位於單一具正式代碼的陸地多邊形內 | 依 `format` 回傳該大寫正式 Alpha-2 或 Alpha-3 代碼 |
| 多個相符多邊形具有相同代碼 | 該代碼 |
| 落在不同代碼的共用邊界上 | `null` |
| 海洋或資料空缺 | `null` |
| 無代碼或非正式的來源區域，包括科索沃／`XK` | `null` |
| 無效座標 | 拋出 `ArgumentError` |

本套件僅識別陸地多邊形，**不**識別領海、專屬經濟區、地址、行政區劃或法律上的主權歸屬。

## 資料與準確度

內建資源檔由 **Natural Earth 5.1.1, 1:10m Admin 0 – Map Units** 產生。Natural Earth
依其事實現況（de facto）政策繪製邊界；查詢結果不代表任何法律立場、主權主張或外交承認。

座標量化至 `1e-5` 度，且未套用任何多邊形簡化或島嶼面積門檻。準確度仍受來源地圖的比例尺與
政策限制。請參閱[資料來源與重新產生](doc/DATA.md)以及[二進位格式](doc/BINARY_FORMAT.md)。

Natural Earth 資料屬於[公有領域](https://www.naturalearthdata.com/about/terms-of-use/)。
本函式庫原始碼採用 MIT 授權。

## 效能

1.1.0 版資源檔大小為 **2,573,123 位元組（2.45 MiB）**。在實體 Pixel 10 上以 profile 模式
執行的量測結果為：冷載入 52.019 ms、熱查詢 Alpha-2 平均 8.571 µs、熱查詢 Alpha-3 平均
8.573 µs，整體行程峰值 RSS 增量 13.38 MiB。這些是單次執行的量測值，並非保證門檻，也不代表
相較其他版本有所改善；工作負載與注意事項請參閱 [PERFORMANCE.md](doc/PERFORMANCE.md)。

執行期查詢會先查詢 2° 空間網格，再檢查多邊形與環的邊界框。每次查詢不會掃描全球所有多邊形、
不會重新解析資源檔，也不會複製幾何資料。

## 範例

`example/lib/main.dart` 是一個 Material 3 應用程式，提供可編輯的緯度與經度欄位。套件測試
也涵蓋固定的真實世界座標、孔洞、MultiPolygon 成員、跨換日線、邊界歧義、無效輸入與損毀的資源檔。

## 更新資料

產生器僅使用 Python 標準函式庫：

```shell
python3 tool/generate_boundaries.py
python3 tool/generate_boundaries.py --check
```

第一個指令僅在本機快取不存在時下載來源資料，驗證其 SHA-256，重新產生資源檔與附屬中繼資料，
並回報相對於前一版資源檔的變更。第二個指令在記憶體中重新產生，若與已提交的輸出不同則失敗。
變更版本鎖定前請先閱讀 [DATA.md](doc/DATA.md)。

## 貢獻與發佈

- [貢獻指南](CONTRIBUTING.md)
- [安全性政策](SECURITY.md)
- [pub.dev 發佈檢查清單](PUBLISHING.md)
- [變更紀錄](CHANGELOG.md)
