module Diary
  # Google Sheets API от имени сервисного аккаунта (ключ — private/google-key.json).
  class GoogleSheets
    API = "https://sheets.googleapis.com/v4/spreadsheets/".freeze
    SCOPE = "https://www.googleapis.com/auth/spreadsheets".freeze

    def initialize(id, key_file)
      @id = id
      @key_file = key_file
    end

    def values(tab, cells, render: "FORMATTED_VALUE")
      get("/values/#{ERB::Util.url_encode(range(tab, cells))}?valueRenderOption=#{render}").fetch("values", [])
    end

    # data: [[ячейки, [[значения]]], ...]
    def write(tab, data, input: "USER_ENTERED")
      post("/values:batchUpdate", { valueInputOption: input,
                                    data: data.map { |cells, rows| { range: range(tab, cells), values: rows } } })
    end

    def batch(requests) = post(":batchUpdate", { requests: })

    def sheet_id(tab)
      sheets.find { _1["title"] == tab }&.fetch("sheetId") || raise(Error, "Нет вкладки «#{tab}»")
    end

    # Скрытая копия вкладки в том же файле, раз в день — до первого изменения.
    # Откат: показать вкладку «Бэкап …» и переименовать её обратно.
    def backup!(tab, now: Time.now)
      return if sheets.any? { _1["title"].start_with?("Бэкап #{now.strftime('%Y-%m-%d')}") && _1["title"].end_with?("· #{tab}") }

      name = "Бэкап #{now.strftime('%Y-%m-%d %H:%M')} · #{tab}"
      reply = batch([{ duplicateSheet: { sourceSheetId: sheet_id(tab), insertSheetIndex: sheets.size, newSheetName: name } }])
      copy = reply.dig("replies", 0, "duplicateSheet", "properties", "sheetId")
      batch([{ updateSheetProperties: { properties: { sheetId: copy, hidden: true }, fields: "hidden" } }])
      @sheets = nil
      name
    end

    private

    def sheets
      @sheets ||= get("?fields=sheets.properties(sheetId,title)").fetch("sheets").map { _1["properties"] }
    end

    def range(tab, cells) = "'#{tab}'!#{cells}"

    def get(path) = request(Net::HTTP::Get, path)
    def post(path, body) = request(Net::HTTP::Post, path, body)

    def request(klass, path, body = nil)
      uri = URI("#{API}#{@id}#{path}")
      req = klass.new(uri)
      req["Authorization"] = "Bearer #{token}"
      req["Content-Type"] = "application/json"
      req.body = JSON.generate(body) if body
      res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { _1.request(req) }
      raise Error, "Google Sheets #{res.code}: #{res.body}" unless res.is_a?(Net::HTTPSuccess)

      JSON.parse(res.body)
    end

    def token
      @token ||= begin
        require "googleauth"
        File.open(@key_file) do |key|
          Google::Auth::ServiceAccountCredentials.make_creds(json_key_io: key, scope: SCOPE)
                                                 .fetch_access_token!.fetch("access_token")
        end
      end
    end
  end
end
