module Diary
  # CSV-выгрузка трекера времени. В ней весь день целиком, наружу отдаются только рабочие записи.
  class TrackerExport
    Row = Struct.new(:groups, :activity, :comment, :start, :finish)
    TIME_FORMAT = "%Y-%m-%d %H:%M:%S".freeze

    attr_reader :from, :to

    def initialize(path, work_groups:)
      @rows = parse(File.read(path, encoding: "bom|utf-8"))
      @work_groups = work_groups
      @from = @rows.map(&:start).min
      @to = @rows.map(&:finish).max
    end

    def empty? = @rows.empty?

    # Дни, которые выгрузка покрывает с 00:00 до 24:00: только их записи можно заменить целиком.
    def complete_dates
      return [] if empty?

      first = from.to_date
      first += 1 if midnight(first) < from
      (first..(to.to_date - 1)).to_a
    end

    # Рабочие отрезки; переход через полночь режется на два дня.
    # Номер задачи в комментарии («#7386») важнее вида записи.
    def entries
      @rows.select { _1.groups == @work_groups }.flat_map do |row|
        activity = row.comment[/#\d+/] || row.activity
        split_by_day(row.start, row.finish).map do |start, finish|
          Entry.new(date: start.to_date, start: start.strftime("%H:%M:%S"),
                    finish: finish.to_date > start.to_date ? "24:00:00" : finish.strftime("%H:%M:%S"),
                    seconds: (finish - start).round, activity:, source: "tracker")
        end
      end
    end

    private

    # Первая таблица файла — отрезки; после пустой строки идёт сводка, она не нужна.
    def parse(text)
      CSV.parse(text.split(/\r?\n[ \t]*\r?\n/, 2).first).drop(1).filter_map do |cells|
        next if cells.compact.empty?

        Row.new(cells[0, 3].map(&:to_s).reject(&:empty?), cells[3], cells[7].to_s,
                Time.strptime(cells[5], TIME_FORMAT), Time.strptime(cells[6], TIME_FORMAT))
      end
    end

    def split_by_day(start, finish)
      parts = []
      while finish > (boundary = midnight(start.to_date + 1))
        parts << [start, boundary]
        start = boundary
      end
      parts << [start, finish] if finish > start
      parts
    end

    def midnight(date) = Time.new(date.year, date.month, date.day)
  end
end
