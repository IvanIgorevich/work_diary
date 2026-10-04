module Diary
  # Таблица времени в Google Sheets, вкладка с моим именем. Месяц — блок строк: шапка, название месяца,
  # дни, после каждого воскресенья и в конце месяца — итог недели (норма, факт, разница), внизу «ИТОГИ».
  # В строку дня пишутся «Пришёл», «Ушёл» и «Перерыв(ы)»; «Время на рабочем месте» считает формула.
  # Новый месяц заполняется целью (14:00 + норма дня, без перерыва), дальше дни перезаписываются фактом.
  class Timesheet
    API = "https://sheets.googleapis.com/v4/spreadsheets/".freeze
    SCOPE = "https://www.googleapis.com/auth/spreadsheets".freeze
    WEEKDAYS = %w[Воскресенье Понедельник Вторник Среда Четверг Пятница Суббота].freeze
    DEFAULT_START = 14 * 3600

    Block = Struct.new(:header, :title, :rows, :subtotals, :totals, keyword_init: true)

    def initialize(config)
      @config = config
      @id = config.private_setting("sheet", "id") or raise Error, "Нет sheet.id в private/config.yml"
      @tab = config.private_setting("sheet", "tab")
      @key_file = config.path(config.private_setting("sheet", "key_file") || "private/google-key.json")
    end

    # Пишет фактические приход, уход и перерыв по дням (DayReport с отрезками времени)
    def write_days(reports)
      reports.group_by { [_1.date.year, _1.date.month] }.each do |(year, month), month_reports|
        block = find_block(year, month) || create_block(year, month)
        data = month_reports.flat_map do |report|
          row = block.rows.fetch(report.date)
          pause = Duration.parse(report.left) - Duration.parse(report.came) - report.total
          [{ range: range("C#{row}:D#{row}"), values: [[report.came, report.left]] },
           { range: range("F#{row}"), values: [[Duration.hms(pause)]] }]
        end
        post("/values:batchUpdate", { valueInputOption: "USER_ENTERED", data: })
      end
    end

    # Итог месяца, как его видит компания (строка «ИТОГИ», «Время на рабочем месте»)
    def month_total(year, month)
      block = find_block(year, month) or return
      value = get("/values/#{escape(range("E#{block.totals}"))}").dig("values", 0, 0)
      value && Duration.parse(value)
    end

    private

    # Первый блок месяца сверху: ниже лежат пустые блоки-заготовки с такими же названиями.
    def find_block(year, month)
      title = "#{MONTHS[month - 1]} #{year}"
      start = column_ab.index { _1[0] == title } or return
      rows = {}
      subtotals = []
      (start + 1...column_ab.size).each do |i|
        a, b = column_ab[i]
        return Block.new(header: start, title: start + 1, rows:, subtotals:, totals: i + 1) if a == "ИТОГИ"

        if b.to_s.match?(/\A\d{2}\.\d{2}\.\d{4}\z/)
          rows[Date.strptime(b, "%d.%m.%Y")] = i + 1
        elsif a.to_s.empty? && b.to_s.empty? && rows.any?
          subtotals << i + 1
        end
      end
      nil
    end

    # Новый месяц под последним заполненным, по образцу его строк (формат, объединения, формулы).
    def create_block(year, month)
      prev = month == 1 ? [year - 1, 12] : [year, month - 1]
      source = find_block(*prev) or raise Error, "Нет блока #{MONTHS[prev[1] - 1]} #{prev[0]} — не по чему строить"
      layout = layout(year, month)
      top = source.totals + 2
      sample = { header: source.header, title: source.title, day: source.rows.values.min,
                 subtotal: source.subtotals.first, totals: source.totals }
      requests = [{ insertDimension: { range: { sheetId: sheet_id, dimension: "ROWS", startIndex: top - 1,
                                                endIndex: top - 1 + layout.size },
                                       inheritFromBefore: false } }]
      layout.each_with_index do |(kind, _), i|
        requests << { copyPaste: { source: grid(sample.fetch(kind)), destination: grid(top + i), pasteType: "PASTE_NORMAL" } }
      end
      requests << { addDimensionGroup: { range: { sheetId: sheet_id, dimension: "ROWS", startIndex: top + 1,
                                                  endIndex: top + layout.size - 2 } } }
      post(":batchUpdate", { requests: })
      post("/values:batchUpdate", { valueInputOption: "USER_ENTERED", data: block_values(layout, top, year, month) })
      @column_ab = nil
      find_block(year, month)
    end

    # [[:header], [:title], [:day, date], ..., [:subtotal, [даты недели]], ..., [:totals]]
    def layout(year, month)
      rows = [[:header], [:title]]
      week = []
      (Date.new(year, month, 1)..Date.new(year, month, -1)).each do |date|
        rows << [:day, date]
        week << date
        next unless date.sunday? || date == Date.new(year, month, -1)

        rows << [:subtotal, week]
        week = []
      end
      rows << [:totals]
    end

    def block_values(layout, top, year, month)
      norm = @config.norm_seconds(year, month)
      days = Date.new(year, month, -1).day
      per_day = (norm / days.to_r).round
      day_rows = []
      subtotal_rows = []
      layout.each_with_index.map do |(kind, arg), i|
        row = top + i
        next { range: range("H#{row}"), values: [["#{days} #{norm / 3600}ч"]] } if kind == :header
        next { range: range("A#{row}"), values: [["#{MONTHS[month - 1]} #{year}"]] } if kind == :title

        values =
          case kind
          when :day
            day_rows << row
            [WEEKDAYS[arg.wday], arg.strftime("%d.%m.%Y"), Duration.hms(DEFAULT_START),
             Duration.hms(DEFAULT_START + per_day), "=D#{row}-C#{row}-F#{row}", "0:00:00", ""]
          when :subtotal
            first = day_rows[-arg.size]
            subtotal_rows << row
            ["", "", "", Duration.hms(per_day * arg.size), "=SUM(E#{first}:E#{row - 1})", "", "=E#{row}-D#{row}"]
          when :totals
            ["ИТОГИ", "", "", "", "=#{subtotal_rows.map { "E#{_1}" }.join('+')}",
             "=#{subtotal_rows.map { "D#{_1}" }.join('+')}", "=#{subtotal_rows.map { "G#{_1}" }.join('+')}"]
          end
        { range: range("A#{row}:G#{row}"), values: [values] }
      end
    end

    def column_ab = @column_ab ||= get("/values/#{escape(range('A1:B'))}").fetch("values", [])

    def sheet_id
      @sheet_id ||= get("?fields=sheets.properties(sheetId,title)").fetch("sheets")
                    .map { _1["properties"] }.find { _1["title"] == @tab }&.fetch("sheetId") ||
                    raise(Error, "Нет вкладки «#{@tab}»")
    end

    def grid(row) = { sheetId: sheet_id, startRowIndex: row - 1, endRowIndex: row, startColumnIndex: 0, endColumnIndex: 8 }
    def range(cells) = "'#{@tab}'!#{cells}"
    def escape(text) = ERB::Util.url_encode(text)

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
          Google::Auth::ServiceAccountCredentials.make_creds(json_key_io: key, scope: SCOPE).fetch_access_token!.fetch("access_token")
        end
      end
    end
  end
end
