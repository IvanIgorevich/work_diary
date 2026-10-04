module Diary
  # data/days.yml — план на каждый день и отметки: внесён ли день в таблицу и отправлен ли в чат.
  class Days
    def initialize(path)
      @path = path
      @days = File.exist?(path) ? YAML.load_file(path) || {} : {}
    end

    def [](date) = @days.fetch(date.to_s, {})
    def first_date = @days.keys.min&.then { Date.parse(_1) }

    def plan(date) = self[date]["plan"]
    def auto_plan?(date) = self[date].fetch("auto", false)
    def sent?(date) = self[date].key?("sent")
    def in_sheet?(date) = self[date].key?("sheet")

    def previous_plan(date)
      key = @days.keys.select { _1 < date.to_s && @days[_1]["plan"] }.max
      key && @days[key]["plan"]
    end

    def set_plan(date, items, auto: false)
      day = (@days[date.to_s] ||= {})
      day["plan"] = items
      auto ? day["auto"] = true : day.delete("auto")
    end

    def mark(date, key, value = Date.today.to_s)
      (@days[date.to_s] ||= {})[key] = value
    end

    def save = File.write(@path, YAML.dump(@days.sort.to_h))
  end
end
