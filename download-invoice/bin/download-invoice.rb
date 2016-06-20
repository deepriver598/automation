require 'csv'
require 'date'
require 'fileutils'
require 'inifile'
require 'logger'
require 'selenium-webdriver'

class DownloadInvoice
  def initialize
    # ログ出力処理を初期化
    pwd = File.expand_path(File.dirname(__FILE__))

    @log = Logger.new(File.expand_path('../log/download-invoice.log', pwd))
    @log.info("処理を開始します")

    # confファイルをパース
    @log.info("configを読み込みます")
    @conf = IniFile.load(File.expand_path('../conf/download-invoice.conf', pwd))

    # AWS関連設定情報読み込み
    @billing_url = @conf["general"]["BILLING_URL"]
    @credential_pattern = @conf["general"]["CREDENTIAL_PATTERN"]

    # ダウンロードに関する設定読み込み
    @profile = Selenium::WebDriver::Firefox::Profile.new
    @profile["browser.download.folderList"] = @conf["profile"]["browser.download.folderList"]
    @download_dir = @conf["profile"]["browser.download.dir"]
    @profile["browser.download.dir"] = @download_dir
    @profile["browser.helperApps.neverAsk.saveToDisk"] = @conf["profile"]["browser.helperApps.neverAsk.saveToDisk"]
    @profile["pdfjs.disabled"] = @conf["profile"]["pdfjs.disabled"]
    @profile["plugin.scan.plid.all"] = @conf["profile"]["plugin.scan.plid.all"]
    @profile["plugin.scan.Acrobat"] = @conf["profile"]["plugin.scan.Acrobat"]

    # ブラウザ操作に関する設定読み込み
    @driver = Selenium::WebDriver.for :firefox, profile: @profile
    @accept_next_alert = @conf["webdriver"]["accept_next_alert"]
    @driver.manage.timeouts.implicit_wait = @conf["webdriver"]["driver.manage.timeouts.implicit_wait"].to_i
    @verification_errors = @conf["webdriver"]["verification_errors"]
  end

  # 初期化処理
  def init
    @iam_url = nil
    @account = nil
    @username = nil
    @password = nil
  end

  # 引数に与えられたディレクトリ配下の条件に合致するファイルを読み込む
  def read_files(path)
    Dir.glob(path)
  end

  # 引数に与えられたcsvファイルのログイン情報をインスタンス変数に格納する
  def get_login_info(file)
    csv = CSV.read(file, headers: true)
    csv.each {|record|
      @username = record["User Name"].encode('utf-8')
      @password = record["Password"].encode('utf-8')
      @iam_url  = record["Direct Signin Link"].encode('utf-8')
      @account  = record["Direct Signin Link"].encode('utf-8').split('.')[0].sub("https://", "")
    }
  end

  # 引数に与えられたURLのページに遷移する
  def access_url(url)
    @driver.get(url)
  end

  # IAMサインインURLからAWSマネジメントコンソールにログインする
  def signin(account, user, password)
    @driver.find_element(:id, "account").clear
    @driver.find_element(:id, "account").send_keys account
    @driver.find_element(:id, "username").clear
    @driver.find_element(:id, "username").send_keys user
    @driver.find_element(:id, "password").clear
    @driver.find_element(:id, "password").send_keys password
    @driver.find_element(:id, "signin_button").click
    @driver.find_element(:id, "nav-logo")
  end

  # スクリプト実行月の前月1日の年月日を返す
  def get_last_month_start_date
    date = Date.new(Date.today.year, Date.today.month, 1) -1
    Date.new(date.year, date.month, 1).to_s
  end

  # スクリプト実行月の前月末日の年月日を返す
  def get_last_month_end_date
    (Date.new(Date.today.year, Date.today.month, 1) -1).to_s
  end

  # invoiceのフィルターを行う
  def filter_invoice(from_date, to_date)
    @driver.find_element(:xpath, "//span[text()='フィルター']")
    @driver.find_element(:xpath, "//input[@type='text']").clear
    @driver.find_element(:xpath, "//input[@type='text']").send_keys from_date
    @driver.find_element(:xpath, "(//input[@type='text'])[2]").clear
    @driver.find_element(:xpath, "(//input[@type='text'])[2]").send_keys to_date
    @driver.find_element(:xpath, "//span[text()='フィルター']").click
    @driver.find_element(:xpath, "//span[text()='フィルター処理中...']")
    @driver.find_element(:xpath, "//span[text()='フィルター']")
  end

  # invoice_idが格納された配列を返す => ["68804441", "69154123"]
  def get_invoice_numbers
    result = @driver.find_elements(:xpath, "//a[contains(@title, '請求書のダウンロード')]")
    result.map(&:text)
  end

  # invoiceをダウンロードする
  def download_invoice(invoice_number)
    @driver.find_element(:link, invoice_number).click
  end

  # AWSマネジメントコンソールからサインアウトする
  def signout
    @driver.find_element(:css, "#nav-usernameMenu > div.nav-elt-label").click
    @driver.find_element(:id, "aws-console-logout").click
  end

  # ブラウザを終了する
  def close
    @driver.quit
  end

  def element_present?(how, what)
    @driver.find_element(how, what)
    true
  rescue Selenium::WebDriver::Error::NoSuchElementError
    false
  end

  def alert_present?
    @driver.switch_to.alert
    true
  rescue Selenium::WebDriver::Error::NoAlertPresentError
    false
  end

  def verify(&blk)
    yield
  rescue ExpectationNotMetError => ex
    @verification_errors << ex
  end

  def close_alert_and_get_its_text(how, what)
    alert = @driver.switch_to().alert()
    alert_text = alert.text
    if (@accept_next_alert) then
      alert.accept()
    else
      alert.dismiss()
    end
    alert_text
  ensure
    @accept_next_alert = true
  end

  # 実行処理
  def execute
    begin
      # クレデンシャルCSVファイルの一覧を読み込み
      csv_files = []
      @log.info(@credential_pattern + " からクレデンシャルCSVファイルを取得します")
      csv_files = read_files(@credential_pattern) unless Dir.exist?(@credential_pattern)

      if csv_files.empty?
        @log.info("クレデンシャルCSVファイルが存在しません")
        exit
      end

      # クレデンシャルCSVファイルごとに処理
      csv_files.each {|file|
        # 初期化処理
        @log.info("ログイン情報を初期化します")
        init

        # 認証情報をCSVファイルから取得
        @log.info(file.encode("utf-8") + " から認証情報を取得します")
        get_login_info(file)

        # IAMユーザログインページへアクセス
        @log.info(@iam_url + " へアクセスします")
        access_url(@iam_url)

        # サインイン
        @log.info("サインインします")
        signin(@account, @username, @password)
        sleep 5

        # 課金ページへ移動
        @log.info(@billing_url + "へアクセスします")
        access_url(@billing_url)
        sleep 1

        # 対象invoice特定
        from_date = get_last_month_start_date
        to_date = get_last_month_end_date
        @log.info(from_date + " から" + to_date + " の期間でフィルタリングします")
        filter_invoice(from_date, to_date)
        sleep 1

        # 取得対象invoice一覧取得
        @log.info("対象のinvoice一覧を取得します")
        invoice_numbers = get_invoice_numbers
        if invoice_numbers.empty?
          @log.info("対象のinvoiceが存在しません")
          next
        end
        @log.info("対象のinvoiceは " + invoice_numbers.to_s + " です")

        # 格納先のディレクトリがない場合は作成
        unless FileTest.exist?(@download_dir)
          @log.info("格納先のディレクトリが存在しないため作成します")
          FileUtils.mkdir_p(@download_dir)
        end

        # invoiceダウンロード
        invoice_numbers.each{|invoice_number|
          @log.info("invoice-number:" + invoice_number + " をダウンロードします")
          download_invoice(invoice_number)
          sleep 3
        }
        # サインアウト
        @log.info("サインアウトします")
        signout
        sleep 3
      }
    rescue Exception => e
      @log.error(e)
      puts e
      raise
    ensure
      # 終了処理
      @log.info("処理を終了します")
      close
    end
  end
end

download_invoice = DownloadInvoice.new
download_invoice.execute