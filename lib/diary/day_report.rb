module Diary
  LETTERS = %w[а б в г д е ё ж з и й к л м н о п р с т у ф х ц ч ш щ э ю я].freeze
  WEEKDAYS = %w[вс пн вт ср чт пт сб].freeze

  # День: план, итог по пунктам плана, приход и уход.
  # «А портал» в трекере — пункт а) плана, «Б портал» — пункт б) и т. д.
  class DayReport
    attr_reader :date, :entries, :plan

    # assign — уточнения по git, когда одна запись трекера захватывает две задачи:
    # [{"from" => "10:27", "to" => "14:27", "item" => "#7386"}] — это время идёт в указанный пункт.
    def initialize(date, entries, plan, config, assign: [])
      @date = date
      @entries = entries
      @plan = plan || []
      @config = config
      @assign = assign || []
    end

    def total = entries.sum(&:seconds)
    def came = entries.filter_map(&:start).min
    def left = entries.filter_map(&:finish).max
    def title = "#{date.strftime('%d.%m')} #{WEEKDAYS[date.wday]}"

    # [[пункт, секунды], ...] в порядке плана, затем всё, чего в плане не было
    def items
      sums = Hash.new(0)
      entries.each do |entry|
        moved = assigned(entry)
        moved.each { |item, seconds| sums[item] += seconds }
        sums[resolve(entry.activity)] += entry.seconds - moved.sum(&:last)
      end
      sums.delete_if { |_, seconds| seconds.zero? }
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

    # [[пункт, секунды], ...] — части отрезка, попавшие в уточнения assign
    def assigned(entry)
      return [] unless entry.start && entry.finish

      start = Duration.parse(entry.start)
      finish = Duration.parse(entry.finish)
      @assign.filter_map do |rule|
        overlap = [finish, Duration.parse(rule["to"])].min - [start, Duration.parse(rule["from"])].max
        [rule["item"], overlap] if overlap.positive?
      end
    end

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
