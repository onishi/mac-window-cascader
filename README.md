# MacWindowCascader

macOS の前面アプリに通常ウィンドウが 3 つ以上あるとき、同じ画面内でリサイズしてカスケード配置するアプリです。通常の操作ウィンドウに加えて、メニューバーにもアイコンを出します。

## 使い方

```sh
make app
open build/MacWindowCascader.app
```

普段使う場合は、権限が安定するようにユーザーの Applications フォルダへ入れてから使ってください。

```sh
make install
```

初回起動後、アプリの `権限を確認` ボタン、またはメニューバーアイコンから `アクセシビリティ権限を確認` を選び、システム設定で `MacWindowCascader` を許可してください。許可後は MacWindowCascader を一度終了して開き直してください。

`MacWindowCascader` が一覧にない場合は、`build/MacWindowCascader.app` をシステム設定のアクセシビリティ一覧へドラッグして追加してください。すでに ON なのに許可されない場合は、一度 OFF/ON してからアプリを開き直してください。

対象アプリをプルダウンから選び、`選択したアプリをカスケード` を押します。通常ウィンドウが 3 つ未満の場合は何もしません。

## 実装メモ

- `NSStatusItem` でメニューバーにも操作アイコンを出します。
- `AXUIElement` で前面アプリの `AXWindows` を読み、通常ウィンドウだけを対象にします。
- `AXPosition` と `AXSize` を設定するため、macOS のアクセシビリティ権限が必要です。
