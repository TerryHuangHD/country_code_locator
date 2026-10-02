# country_code_locator

[English](README.md) | [繁體中文](README.zh-TW.md) | **日本語**

[![CI](https://github.com/TerryHuangHD/country_code_locator/actions/workflows/ci.yml/badge.svg)](https://github.com/TerryHuangHD/country_code_locator/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Flutter 向けの、オフラインで WGS 84 座標から国コードを検索するパッケージです。同梱された
バージョン管理済みの境界インデックスを一度読み込むだけで、以降は正式に割り当てられた
ISO 3166-1 Alpha-2 または Alpha-3 コードを同期的に返します。ネットワーク接続、GPS、
権限、プラットフォームのジオコーダー、地図サービス SDK は不要です。

> 本ドキュメントは翻訳版です。内容に相違がある場合は英語版 [README.md](README.md) が優先されます。

## 機能

- パッケージのインストール後は完全にオフラインで検索できます。
- 一度の非同期初期化の後、検索はすべて同期呼び出しです。
- 空間グリッド、バウンディングボックス、点の多角形内判定（point-in-polygon）を純粋な Dart で実装しています。
- Polygon、MultiPolygon、穴、島、日付変更線（antimeridian）をまたぐ形状に対応しています。
- 共有境界の判定は決定的で、ソースデータの行順序に依存しません。
- 正式な ISO Alpha-2/Alpha-3 の組のみを厳密に扱い、プレースホルダーや `XK` が返されることはありません。
- バイナリデータは、フォーマットバージョン、長さ、意味的チェック、CRC-32 による整合性保護で検証されます。
- 再現可能で、チェックサムによってバージョンを固定した Natural Earth データパイプラインを備えています。

## インストール

```shell
flutter pub add country_code_locator
```

境界アセットはパッケージ側で宣言されているため、アプリケーション自身の `pubspec.yaml` に
追加する必要はありません。

## 使い方

アプリケーションの起動時に locator を一つ読み込み、すべての検索で使い回します。

```dart
import 'package:country_code_locator/country_code_locator.dart';

final locator = await OfflineCountryCode.load();

final alpha2 = locator.lookup(
  latitude: 35.6812,
  longitude: 139.7671,
); // JP（デフォルト）

final alpha3 = locator.lookup(
  latitude: 35.6812,
  longitude: 139.7671,
  format: CountryCodeFormat.alpha3,
); // JPN
```

海洋、データ範囲外またはコードのない陸地、異なるコードが共有する境界上の点に対しては、
`lookup` は `null` を返します。

検索ごとに `CountryCodeFormat.alpha2` または `CountryCodeFormat.alpha3` を選択できます。
どちらの形式も読み込み済みの同じジオメトリと境界判定を共有し、デフォルトは Alpha-2 です。

### 入力の検証

緯度は有限値かつ `[-90, 90]` の範囲、経度は有限値かつ `[-180, 180]` の範囲でなければなりません。
無効な値は `ArgumentError` をスローします。経度 `-180` と `180` は同じ子午線として扱われます。

### カスタムアセットの読み込み

独自の読み込み層を持つアプリケーションは、バイト列から直接検証・初期化できます。

```dart
final locator = OfflineCountryCode.fromBytes(bytes);
```

`fromBytes` はすべての実行時構造を即座にデコードし、渡された `Uint8List` を保持も変更もしません。
カスタムの Flutter `AssetBundle` を使う場合は `OfflineCountryCode.load(bundle: customBundle)`
も利用できます。

## 結果のポリシー

| 状況 | 結果 |
| --- | --- |
| 正式なコードを持つ陸地多角形の一つに点が含まれる | `format` に応じた、その大文字の正式 Alpha-2 または Alpha-3 コード |
| 一致する複数の多角形が同じコードを持つ | そのコード |
| 異なるコードが共有する境界上 | `null` |
| 海洋またはデータの空白 | `null` |
| コードのない、または非公式なソース地域（コソボ／`XK` を含む） | `null` |
| 無効な座標 | `ArgumentError` をスロー |

このパッケージは陸地の多角形のみを識別します。領海、排他的経済水域、住所、行政区画、
法的な主権は識別**しません**。

## データと精度

同梱アセットは **Natural Earth 5.1.1, 1:10m Admin 0 – Map Units** から生成されています。
Natural Earth は事実上（de facto）の方針に基づいて境界を描画しており、結果は法的立場、
主権の主張、外交上の承認を表すものではありません。

座標は `1e-5` 度単位で量子化され、多角形の簡略化や島の面積しきい値は適用していません。
精度はソース地図の縮尺と方針に依存します。[データの出典と再生成](doc/DATA.md)および
[バイナリフォーマット](doc/BINARY_FORMAT.md)を参照してください。

Natural Earth のデータは[パブリックドメイン](https://www.naturalearthdata.com/about/terms-of-use/)です。
ライブラリのソースコードは MIT ライセンスです。

## パフォーマンス

1.1.0 のアセットは **2,573,123 バイト（2.45 MiB）** です。実機の Pixel 10 で profile モードで
実行した計測では、コールドロード 52.019 ms、ウォーム検索の平均が Alpha-2 で 8.571 µs、
Alpha-3 で 8.573 µs、プロセス全体のピーク RSS 増加量が 13.38 MiB でした。これらは 1 回の
実行による計測値であり、保証されたしきい値でも他リリースからの改善を示すものでもありません。
ワークロードと注意点は [PERFORMANCE.md](doc/PERFORMANCE.md) を参照してください。

実行時の検索では、多角形とリングのバウンディングボックスを調べる前に 2° の空間グリッドを参照します。
検索ごとに全世界の多角形を走査したり、アセットを再解析したり、ジオメトリをコピーしたりはしません。

## サンプル

`example/lib/main.dart` には、緯度と経度を編集できるフィールドを備えた Material 3
アプリケーションが含まれています。パッケージのテストスイートでは、固定の実在座標、穴、
MultiPolygon のメンバー、日付変更線をまたぐ処理、境界の曖昧さ、無効な入力、破損したアセットも
検証しています。

## データの更新

ジェネレーターは Python 標準ライブラリのみを使用します。

```shell
python3 tool/generate_boundaries.py
python3 tool/generate_boundaries.py --check
```

1 つ目のコマンドは、ローカルキャッシュがない場合にのみソースをダウンロードし、SHA-256 を検証して、
アセットと付随するメタデータを再生成し、以前のアセットからの変更を報告します。2 つ目のコマンドは
メモリ上で再生成し、コミット済みの出力と異なる場合は失敗します。バージョン固定を変更する前に
[DATA.md](doc/DATA.md) を確認してください。

## コントリビュートとリリース

- [コントリビューションガイド](CONTRIBUTING.md)
- [セキュリティポリシー](SECURITY.md)
- [pub.dev リリースチェックリスト](PUBLISHING.md)
- [変更履歴](CHANGELOG.md)
