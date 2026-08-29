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

## 使い方

1. 本リポジトリをクローンします。

2. `cloud-init/user-data.template` に、管理PCのSSH公開鍵を設定します。

```yaml
ssh_authorized_keys:
  - "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA..."
```

3. `cloud-init/network-config` に、Raspberry Piで使用するネットワーク設定を記述します。

4. SDカードをPCに装着します。

5. PowerShellからスクリプトを実行します。

```powershell
powershell -ExecutionPolicy Bypass .\Make-RpiSdCard.ps1 -Hostname rpi-01
```

6. 書き込み対象として検出されたSDカードの情報を確認し、確認プロンプトに回答します。

```text
Type ERASE-1 to confirm:
```

7. Raspberry Pi OSのイメージダウンロード、書き込み、検証、cloud-init設定ファイルの配置が完了するまで待ちます。

8. スクリプトが正常終了したら、SDカードをPCから取り外し、Raspberry Piに装着します。

9. Raspberry PiをLANに接続して起動します。

10. 初回起動時は cloud-init による初期設定が行われるため、`network-config` に設定したIPアドレスへ ping が通るまで待ちます。

```bash
ping 192.168.1.251
```

11. ping が通るようになったら、SSH接続できることを確認します。

```bash
ssh pi@192.168.1.251
```

SSH秘密鍵を明示する場合は以下のようにします。

```bash
ssh -i ~/.ssh/id_ed25519 pi@192.168.1.251
```

## 注意事項

本スクリプトはSDカードへRaspberry Pi OSイメージを直接書き込みます。対象ディスク上の既存データはすべて削除されます。

書き込み前に表示されるディスク情報を必ず確認してください。内蔵SSDなど、誤ったディスクを対象にしないよう注意してください。

## 補足

`user-data` および `network-config` は、UTF-8 BOMなし・LF改行でSDカードへ書き込まれます。
cloud-initではBOM付きUTF-8の `user-data` が正しく認識されないため、この処理はスクリプト側で行っています。
