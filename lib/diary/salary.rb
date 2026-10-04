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
      @sheets = GoogleSheets.new(id, config.path(config.private_setting("sheet", "key_file") || "private/google-key.json"))
    end

    # Последняя строка «за <месяц>» — заготовка или уже заполненная
    def row(month)
      description = "за #{MONTHS[month - 1].downcase}"
      rows = @sheets.values(@tab, "A1:C").each_with_index.filter_map do |(date, desc, hours), i|
        Row.new(number: i + 1, date:, description: desc, hours:) if desc.to_s.strip == description
      end
      rows.last
    end

    def fill(row, hours, date)
      @sheets.backup!(@tab)
      @sheets.write(@tab, [["A#{row.number}", [[(date - SERIAL_EPOCH).to_i]]],
                           ["C#{row.number}", [[hours.to_f]]]], input: "RAW")
    end
  end
end
