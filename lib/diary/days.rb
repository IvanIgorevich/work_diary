module Diary
  # data/days.yml — план на каждый день и отметки: внесён ли день в таблицу и отправлен ли в чат.
  class Days
    def initialize(path)
      @path = path
      @days = File.exist?(path) ? YAML.load_file(path) || {} : {}
    end

    def [](date) = @days.fetch(date.to_s, {})
    def first_date = @days.keys.min&.then { Date.parse(_1) }
    def dates = @days.keys.map { Date.parse(_1) }.sort

    def plan(date) = self[date]["plan"]
    def assign(date) = self[date].fetch("assign", [])
    # Части дня, уже отправленные в чат, если день отправлен не целиком: ["plan"]
    def sent_parts(date) = self[date].fetch("sent_parts", [])
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

    def mark_sent_part(date, part)
      day = (@days[date.to_s] ||= {})
      day["sent_parts"] = (day.fetch("sent_parts", []) | [part])
    end

    def mark(date, key, value = Date.today.to_s)
      (@days[date.to_s] ||= {})[key] = value
    end

    def save = File.write(@path, YAML.dump(@days.sort.to_h))
  end
end
