# aws-billing
AWSマネジメントコンソールから前月のinvoiceをダウンロードするスクリプト

### 必要ソフトウェア＆動作確認バージョン
* Chrome 51.0.2704.103 m
* chromedriver 2.22 
* Ruby 2.2.4 
* Bundler 1.12.5 
* Windows 7 Professional 32bit  

### 動作環境セットアップ方法
* chromedriverインストール  
    以下URLからダウンロード  
    <https://sites.google.com/a/chromium.org/chromedriver/downloads>  
    [chromedriver_win32.zip] 

    ZIPを展開し、Rubyのインストールパスのbinディレクトリに配置  

### 利用方法
* conf修正  
<任意のパス>¥aws-billing-master¥download-invoice/confの以下の部分を修正  
```
[general]  
credential_pattern = "C:/aws-billing/download-invoice/credential/*.csv"  

[webdriver]  
browser.download.dir = "C:\downloads"  
```
* 実行(コマンドプロンプトから)  
```
cd <任意のパス>¥aws-billing-master¥download-invoice/bin  
ruby download-invoice.rb
```
