module Diary
  # Таблица зарплаты: строка на месяц — дата, «за сентябрь», часы, ставка, сумма (формула).
  # Строки с описанием заготовлены заранее; заполняются дата и часы.
  # Часы — итог месяца из таблицы времени, округлённый вверх до четверти часа.
  class Salary
    Row = Struct.new(:number, :date, :description, :hours, keyword_init: true)
    SERIAL_EPOCH = Date.new(1899, 12, 30)

    def self.hours(seconds) = (seconds / 900r).ceil / 4r

    def initialize(config)
      id = config.private_setting("salary", "id") or raise Error, "Нет salary.id в private/config.yml"
      @tab = config.private_setting("salary", "tab")
      @sheets = GoogleSheets.new(id, config)
    end

    # Последняя строка «за <месяц>» — заготовка или уже заполненная
    def row(month)
      description = "за #{MONTHS[month - 1].downcase}"
      rows = @sheets.values(@tab, "A1:C").each_with_index.filter_map do |(date, desc, hours), i|
        Row.new(number: i + 1, date:, description: desc, hours:) if desc.to_s.strip == description
      end
      rows.last
    end

    # Дата пишется числом, поэтому формат ячейки берётся у строки прошлого месяца:
    # у заготовок его нет, и без этого видно 46299 вместо даты.
    # Возвращает путь к локальной копии таблицы до изменений
    def fill(row, hours, date)
      backup = @sheets.backup!
      @sheets.write(@tab, [["A#{row.number}", [[(date - SERIAL_EPOCH).to_i]]],
                           ["C#{row.number}", [[hours.to_f]]]], input: "RAW")
      cell = ->(number) { { sheetId: @sheets.sheet_id(@tab), startRowIndex: number - 1, endRowIndex: number,
                            startColumnIndex: 0, endColumnIndex: 1 } }
      @sheets.batch([{ copyPaste: { source: cell.(row.number - 1), destination: cell.(row.number),
                                    pasteType: "PASTE_FORMAT" } }])
      backup
    end
  end
end
