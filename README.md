# tool-make-rpi-sd-card

Raspberry Pi OS のSDカード作成と初期設定をワンコマンドで行うPowerShellスクリプトです。
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

Imagerが`C:\Program Files\Raspberry Pi Imager`にインストールされていることを確認してください。
異なる場合は、`Make-RpiSdCard.ps1`の以下の行を変更してください。

```powershell
$imager = "C:\Program Files\Raspberry Pi Imager\rpi-imager.exe"
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
