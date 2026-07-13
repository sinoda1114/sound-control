# Sound Control — Codex実装指示書

## 目的

macOS向けのメニューバー常駐アプリ **Sound Control** を作成する。

このアプリは、macOSの音量調整とサウンド出力デバイス切り替えを、システム設定やコントロールセンターを開かずにメニューバーから実行できるようにするための自分用アプリである。

## アプリ名・PJ名

| 項目 | 内容 |
| --- | --- |
| アプリ名 | Sound Control |
| PJ名 | SoundControl |
| Xcodeプロジェクト名 | SoundControl |
| Bundle Display Name | Sound Control |
| リポジトリ名候補 | sound-control |

## 技術スタック

- Swift
- SwiftUI
- macOS App
- MenuBarExtra
- CoreAudio
- ServiceManagement
- Xcodeプロジェクト
- App Store配布は不要
- 自分用アプリとして動作すればよい

## アプリ形式

- macOSネイティブアプリ
- メニューバー常駐アプリ
- Dockには表示しない
- メニューバーアイコンをクリックするとメニューを表示する

## 操作対象

MVPでは、以下のみを操作する。

- 現在の出力音量
- ミュートON/OFF
- サウンド出力デバイス

変更してよいもの:

- output volume
- output mute
- default output device

変更してはいけないもの:

- input device
- input volume
- microphone
- alert sound
- sound effects
- notification sound
- Bluetooth pairing
- Bluetooth connection / disconnection
- app-specific volume

## 実装構成

```text
SoundControlApp
 ├─ App entry point
 ├─ MenuBarExtra
 ├─ AudioDevice
 ├─ AudioManager
 ├─ LoginItemManager
 └─ Error handling
```

## MVP受け入れ条件

- アプリを起動するとメニューバーにアイコンが表示される
- Dockには表示されない
- メニューを開くと現在音量が表示される
- 音量スライダーで音量を変更できる
- ミュートON/OFFを切り替えられる
- 接続中の出力デバイス一覧が表示される
- 現在の出力デバイスにチェックが付く
- 出力デバイスをクリックすると切り替えられる
- Bluetoothイヤホンなど後から接続したデバイスも一覧に反映できる
- 「サウンド設定を開く」でmacOS標準のサウンド設定を開ける
- 「終了」からアプリを終了できる
- エラー時に簡単なエラー表示が出る
- 自分のMacで動作確認できる
