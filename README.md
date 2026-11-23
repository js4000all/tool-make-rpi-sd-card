# tool-make-rpi-sd-card

Raspberry Pi向けSDカード作成を行うPowerShellスクリプトです。現在は Raspberry Pi OS の書き込み・初期設定に対応しています。NixOS対応は準備中です。
SDカード作成時に以下を自動設定します。

- Raspberry Pi OS Lite 64-bit の書き込み
- hostname の設定
- 固定IPアドレスなどのネットワーク設定
- 管理ユーザー `pi` の作成
- SSH公開鍵の登録
- SSHサーバーの有効化
- `sudo` の利用設定

作成したSDカードをRaspberry Piに装着して起動すると、管理PCからSSH公開鍵認証で接続できる状態になります。
つまり、Ansible等で管理できる状態を一発で作れます。


## 動作環境

- PowerShell 5.1以降
- Raspberry Pi Imager 1.9以降

Raspberry Pi Imagerは公式サイトでダウンロードできます。
https://www.raspberrypi.com/software/

Imagerの実行ファイルは自動検出されます。次の優先順位で探します。

1. `-ImagerPath` で明示指定された絶対パス（指定された場合は他の候補を探しません）
2. 環境変数 `PATH` 上の `rpi-imager.exe`
3. `Program Files`、`Program Files (x86)`、`LOCALAPPDATA` 配下の代表的なインストール先（`Raspberry Pi Ltd\Imager`、旧 `Raspberry Pi Imager` など）

見つからない場合は、SDカードの消去確認より前にエラーを表示します。`-SkipImager` 指定時はImagerを使用しないため検出しません。

標準以外の場所にインストールされている場合はフルパスを渡せます。


```powershell
.\Make-RpiSdCard.ps1 -Hostname rpi-01 -ImagerPath "C:\Program Files\Raspberry Pi Ltd\Imager\rpi-imager.exe"
```

## 使い方

大きくは次の3ステップです。

1. 設定ファイル編集
2. コマンド実行
3. Raspberry Pi起動後の接続確認


### 1. 設定ファイルを編集する

`cloud-init/user-data.template` に、管理PCのSSH公開鍵を設定します。

```yaml
ssh_authorized_keys:
  - "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA..."
```

`cloud-init/network-config` に、Raspberry Piで使用するネットワーク設定を記述します。

例:

```yaml
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: false
      addresses:
        - 192.168.1.251/24
      routes:
        - to: default
          via: 192.168.1.1
      nameservers:
        addresses:
          - 192.168.1.1
```


### 2. コマンドを実行する

SDカードをPCに装着します。

PowerShellからスクリプトを実行します。

```powershell
powershell -ExecutionPolicy Bypass .\Make-RpiSdCard.ps1 -Hostname rpi-01
```

書き込み対象として検出されたSDカードの情報が表示されるので、対象が正しいことを確認します。
確認プロンプトに、表示された文字列を入力します。

```text
Type ERASE-1 to confirm:
```

その後、以下の処理が自動的に行われます。

- Raspberry Pi OS Lite 64-bit のイメージダウンロード
- SDカードへのイメージ書き込み
- 書き込み内容の検証
- `user-data` の配置
- `network-config` の配置
- SSH有効化用ファイルの配置
- 各設定ファイルの確認

スクリプトが正常終了したら、SDカードをPCから取り外します。


### 3. Raspberry Piを起動して接続確認する

作成したSDカードをRaspberry Piに装着し、LANケーブルを接続して起動します。

初回起動時は cloud-init による初期設定が行われるため、`network-config` に設定したIPアドレスへ ping が通るまで待ちます。

```bash
ping 192.168.1.251
```

ping が通るようになったら、SSH接続できることを確認します。

```bash
ssh pi@192.168.1.251
```

SSH秘密鍵を明示する場合は以下のようにします。

```bash
ssh -i ~/.ssh/id_ed25519 pi@192.168.1.251
```

SSH公開鍵認証でログインでき、`sudo` が実行できれば初期セットアップ完了です。

以降のソフトウェアインストールや構成変更は、Git管理されたAnsibleコードから実施します。


## 注意事項

本スクリプトはSDカードへRaspberry Pi OSイメージを直接書き込みます。対象ディスク上の既存データはすべて削除されます。

書き込み前に表示されるディスク情報を必ず確認してください。内蔵SSDなど、誤ったディスクを対象にしないよう注意してください。


## 補足

`user-data` および `network-config` は、UTF-8 BOMなし・LF改行でSDカードへ書き込まれます。
cloud-initではBOM付きUTF-8の `user-data` が正しく認識されないため、この処理はスクリプト側で行っています。


## OS選択とモジュール構成


従来どおり `-Hostname` だけを指定すると Raspberry Pi OS が選択されます。

明示的に指定する場合:

 
```powershell
.\Make-RpiSdCard.ps1 -OS RaspberryPiOS -Hostname rpi-01
```

現在 `-OS NixOS` は未実装で、ディスク操作より前にエラーとなります。NixOSのイメージ書き込みは後続PRで追加します。

内部処理は次のファイルへ分割しました。

- `Make-RpiSdCard.ps1`: 引数および処理のオーケストレーション
- `modules/Disk.ps1`: ディスク候補検出と消去確認
- `modules/Image.ps1`: Raspberry Pi Imager CLIの実行
- `modules/BootPartition.ps1`: FAT32ブート領域の特定とUTF-8書き込み
- `modules/RaspberryPiOS.ps1`: Raspberry Pi OSのイメージ選択と初期設定ファイル配置
- `modules/NixOS.ps1`: NixOS未対応の明示的エラー

設定ファイルは従来の `cloud-init/` に置いたままです。設定ファイルと各モジュールは、実行時のカレントディレクトリに依存せず、スクリプトの位置から解決されます。

## テストの実行

ユニットテストには **Pester 5以降** が必要です。Windows PowerShell 5.1に付属するPester 3.4.0では実行できません。

未インストールの場合は、PowerShellで以下を実行してください。

```powershell
Install-Module Pester -MinimumVersion 5.0.0 -Scope CurrentUser -Force -SkipPublisherCheck
```

プロジェクトのルートでテスト用スクリプトを実行します。

```powershell
.\Run-Tests.ps1
```

`Run-Tests.ps1` はインストール済みPester 5の最新バージョンを読み込み、スクリプト位置を基準に `tests/` を実行します。Pester 5が存在しない場合、失敗したテストがある場合、テストが実行されなかった場合にはエラーを返します。実SDカードの書き込みは行いません。

テストスクリプトを `powershell tests/Modules.Tests.ps1` のように直接実行せず、`Run-Tests.ps1` を使用してください。
