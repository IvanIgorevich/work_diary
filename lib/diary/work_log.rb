module Diary
  # Одна строка журнала — отрезок работы (из трекера) или итог за день (старые записи).
  Entry = Struct.new(:date, :start, :finish, :seconds, :activity, :source, keyword_init: true) do
    def to_row = [date.to_s, start, finish, Duration.hms(seconds), activity, source]
  end

  # data/work_log.csv — все рабочие часы. Суммы не хранятся, а считаются.
  class WorkLog
    HEADERS = %w[date start end duration activity source].freeze

    attr_reader :entries

    def initialize(path)
      @path = path
      @entries = File.exist?(path) ? load : []
    end

    def for_date(date) = entries.select { _1.date == date }
    def between(from, to) = entries.select { (from..to).cover?(_1.date) }
    def dates = entries.map(&:date).uniq.sort

    def replace_day(date, new_entries)
      @entries = entries.reject { _1.date == date } + new_entries
    end

    def replace_source(source, new_entries)
      @entries = entries.reject { _1.source == source } + new_entries
    end

    def save
      CSV.open(@path, "w") do |csv|
        csv << HEADERS
        entries.sort_by { [_1.date, _1.start.to_s, _1.activity] }.each { csv << _1.to_row }
      end
    end

    private

    def load
      CSV.read(@path, headers: true).map do |row|
        Entry.new(date: Date.parse(row["date"]), start: row["start"], finish: row["end"],
                  seconds: Duration.parse(row["duration"]), activity: row["activity"], source: row["source"])
      end
    end
  end
end
