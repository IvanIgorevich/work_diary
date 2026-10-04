module Diary
  # Записи старого diary.rb (records/*.txt): «1) #6077, this day 5h 54m, total 124h 12m».
  # Ранние записи: «2) #1487, start, this day 02:25». Файл назван датой сохранения,
  # рабочая дата — в строке «2026-09-20:».
  class LegacyRecords
    LINE = %r{\A\d+\)\s*(.*?)\bthis day(?:/total)?\s+(\d+h(?:\s*\d+m)?|\d+m|\d{1,2}:\d{2})\b}

    def initialize(dir)
      @dir = dir
    end

    def entries
      blocks.flat_map do |date, lines|
        lines.filter_map do |line|
          match = LINE.match(line) or next
          tasks = match[1].scan(/#\d+/)
          next if tasks.empty?

          seconds = match[2].include?(":") ? Duration.parse(match[2]) : Duration.parse_legacy(match[2])
          Entry.new(date:, start: nil, finish: nil, seconds:, activity: tasks.join(", "), source: "diary")
        end
      end
    end

    # Строки с «this day», которые не удалось разобрать (свободные записи 2023 года)
    def skipped
      blocks.flat_map(&:last).select do |line|
        line.include?("this day") && !LINE.match(line)&.then { _1[1].match?(/#\d+/) }
      end
    end

    private

    def blocks
      @blocks ||= Dir[File.join(@dir, "*.txt")].sort.flat_map do |file|
        saved = Date.parse(File.basename(file, ".txt"))
        File.read(file, encoding: "UTF-8").delete("\r").split(/^(\d{4}-\d{2}-\d{2}):[ \t]*$/).drop(1)
            .each_slice(2).map { |date, body| [work_date(Date.parse(date), saved), body.to_s.lines.map(&:strip)] }
      end
    end

    # Рабочий день не бывает позже сохранения: «2027-07-28» в файле от 2026-07-29 — опечатка в годе
    def work_date(date, saved) = date > saved ? Date.new(saved.year, date.month, date.day) : date
  end
end
