# Sound Control

macOSのメニューバーから、出力音量・ミュート・サウンド出力デバイスを操作する自分用Macアプリです。

## 構成

- `SoundControl.xcodeproj`: Xcodeプロジェクト
- `SoundControl/`: SwiftUI / CoreAudio実装
- `docs/SPEC-RQD.md`: 仕様・要求
- `docs/MENU-SPEC.md`: 画面・メニュー仕様
- `docs/CODEX-IMPLEMENTATION.md`: Codex実装指示書

## ビルド

```sh
xcodebuild -project SoundControl.xcodeproj -scheme SoundControl -configuration Debug -destination 'platform=macOS' build
```

## /Applications へ配置

Launchpadやメニューバー管理アプリから見つけやすくするため、ビルド後の `Sound Control.app` を `/Applications` に配置します。

```sh
ditto ~/Library/Developer/Xcode/DerivedData/SoundControl-*/Build/Products/Debug/Sound\ Control.app /Applications/Sound\ Control.app
```

## 実装済みMVP

- `MenuBarExtra` によるメニューバー常駐
- Dock非表示用の `LSUIElement`
- 現在の出力音量表示
- 音量スライダー
- ミュートON/OFF
- CoreAudioによる出力デバイス一覧取得
- 現在の出力デバイス表示
- 出力デバイス切り替え
- サウンド設定を開く
- `SMAppService.mainApp` による自動起動ON/OFF
- メニューから終了
- オリジナルのApp Icon

## 注意

HDMI / DisplayPortなど、macOS側で音量やミュートを変更できない出力デバイスでは、該当操作を無効化します。
