module Diary
  LETTERS = %w[а б в г д е ё ж з и й к л м н о п р с т у ф х ц ч ш щ э ю я].freeze
  WEEKDAYS = %w[вс пн вт ср чт пт сб].freeze

  # День: план, итог по пунктам плана, приход и уход.
  # «А портал» в трекере — пункт а) плана, «Б портал» — пункт б) и т. д.
  class DayReport
    attr_reader :date, :entries, :plan

    def initialize(date, entries, plan, config)
      @date = date
      @entries = entries
      @plan = plan || []
      @config = config
    end

    def total = entries.sum(&:seconds)
    def came = entries.filter_map(&:start).min
    def left = entries.filter_map(&:finish).max
    def title = "#{date.strftime('%d.%m')} #{WEEKDAYS[date.wday]}"

    # [[пункт, секунды], ...] в порядке плана, затем всё, чего в плане не было
    def items
      sums = Hash.new(0)
      entries.each { sums[resolve(_1.activity)] += _1.seconds }
      sums.each_with_index.sort_by { |(item, _), i| [plan.index(item) || plan.size, i] }.map(&:first)
    end

    # Записи, которые не удалось привязать к плану: «? Б портал»
    def unresolved = items.map(&:first).select { _1.start_with?("? ") }

    def plan_text
      ["План на день #{date.strftime('%d.%m')}", "1. #{@config.project}: ",
       *plan.each_with_index.map { |item, i| "    #{LETTERS[i]}) #{item}" }].join("\n")
    end

    def result_text
      ["Итог на день #{date.strftime('%d.%m')}", "1. #{@config.project}: #{Duration.hm(total)}",
       *items.each_with_index.map { |(item, seconds), i| "    #{LETTERS[i]}) #{item} #{Duration.hm(seconds)}" }].join("\n")
    end

    private

    def resolve(activity)
      return activity if activity.start_with?("#")

      if (letter = activity[@config.plan_letter, 1])
        item = plan[LETTERS.index(letter.downcase).to_i]
        item&.start_with?("#") ? item : "? #{activity}"
      else
        @config.activities.fetch(activity, activity.downcase)
      end
    end
  end
end
