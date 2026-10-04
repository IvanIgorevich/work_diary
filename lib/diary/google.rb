module Diary
  # Запросы к Google API от имени сервисного аккаунта (ключ — private/google-key.json).
  class Google
    SCOPES = %w[https://www.googleapis.com/auth/spreadsheets
                https://www.googleapis.com/auth/documents
                https://www.googleapis.com/auth/drive.readonly].freeze

    def initialize(key_file)
      @key_file = key_file
    end

    def get(url) = JSON.parse(request(Net::HTTP::Get, url))
    def post(url, body) = JSON.parse(request(Net::HTTP::Post, url, body))
    def download(url) = request(Net::HTTP::Get, url)

    private

    def request(klass, url, body = nil)
      uri = URI(url)
      req = klass.new(uri)
      req["Authorization"] = "Bearer #{token}"
      req["Content-Type"] = "application/json"
      req.body = JSON.generate(body) if body
      res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { _1.request(req) }
      raise Error, "Google #{res.code}: #{res.body}" unless res.is_a?(Net::HTTPSuccess)

      res.body
    end

    def token
      @token ||= begin
        require "googleauth"
        File.open(@key_file) do |key|
          ::Google::Auth::ServiceAccountCredentials.make_creds(json_key_io: key, scope: SCOPES)
                                                   .fetch_access_token!.fetch("access_token")
        end
      end
    end
  end

  # Перед любым изменением файл Google целиком сохраняется локально:
  # private/backups/<название> <время>.xlsx|docx. Откат — открыть копию или загрузить её обратно.
  class Backup
    DRIVE = "https://www.googleapis.com/drive/v3/files/".freeze
    FORMATS = {
      "application/vnd.google-apps.spreadsheet" => ["xlsx", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"],
      "application/vnd.google-apps.document" => ["docx", "application/vnd.openxmlformats-officedocument.wordprocessingml.document"]
    }.freeze

    def initialize(google, dir)
      @google = google
      @dir = dir
    end

    def save(file_id, now: Time.now)
      meta = @google.get("#{DRIVE}#{file_id}?fields=name,mimeType")
      extension, mime = FORMATS.fetch(meta["mimeType"])
      FileUtils.mkdir_p(@dir)
      path = File.join(@dir, "#{meta['name'].tr('/|:', '---')} #{now.strftime('%Y-%m-%d %H-%M-%S')}.#{extension}")
      File.binwrite(path, @google.download("#{DRIVE}#{file_id}/export?mimeType=#{ERB::Util.url_encode(mime)}"))
      path
    end
  end
end
