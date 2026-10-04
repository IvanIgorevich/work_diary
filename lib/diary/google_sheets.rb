module Diary
  # Google Sheets API: значения, правки, пакетные запросы. Перед правками — локальная копия файла.
  class GoogleSheets
    API = "https://sheets.googleapis.com/v4/spreadsheets/".freeze

    def initialize(id, config)
      @id = id
      @google = Google.new(config.path(config.private_setting("sheet", "key_file") || "private/google-key.json"))
      @backups = config.path("private/backups")
    end

    def values(tab, cells, render: "FORMATTED_VALUE")
      @google.get("#{API}#{@id}/values/#{ERB::Util.url_encode(range(tab, cells))}?valueRenderOption=#{render}")
             .fetch("values", [])
    end

    # data: [[ячейки, [[значения]]], ...]
    def write(tab, data, input: "USER_ENTERED")
      @google.post("#{API}#{@id}/values:batchUpdate",
                   { valueInputOption: input, data: data.map { |cells, rows| { range: range(tab, cells), values: rows } } })
    end

    def batch(requests) = @google.post("#{API}#{@id}:batchUpdate", { requests: })

    def sheet_id(tab)
      @sheet_ids ||= @google.get("#{API}#{@id}?fields=sheets.properties(sheetId,title)").fetch("sheets")
                            .to_h { [_1.dig("properties", "title"), _1.dig("properties", "sheetId")] }
      @sheet_ids.fetch(tab) { raise Error, "Нет вкладки «#{tab}»" }
    end

    # Локальная копия всего файла перед правками; путь к ней
    def backup! = Backup.new(@google, @backups).save(@id)

    private

    def range(tab, cells) = "'#{tab}'!#{cells}"
  end
end
