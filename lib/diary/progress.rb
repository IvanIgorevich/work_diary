module Diary
  # Отклонение от цели — ради этого и ведётся таблица времени.
  # Цель на месяц делится поровну на все дни месяца, недели режутся границей месяца, как в таблице.
  class Progress
    Result = Struct.new(:from, :to, :fact, :norm, :month_norm, keyword_init: true) do
      def deviation = fact - norm

      def to_s
        "#{from.strftime('%d.%m')}–#{to.strftime('%d.%m')}: #{Duration.hms(fact)} из #{Duration.hms(norm)} " \
          "(#{Duration.signed(deviation)})"
      end
    end

    def initialize(log, config)
      @log = log
      @config = config
    end

    def month(date) = build(Date.new(date.year, date.month, 1), date)
    def week(date) = build([date - (date.cwday - 1), Date.new(date.year, date.month, 1)].max, date)

    private

    def build(from, to)
      month_norm = @config.norm_seconds(to.year, to.month)
      days_in_month = Date.new(to.year, to.month, -1).day
      Result.new(from:, to:, fact: @log.between(from, to).sum(&:seconds), month_norm:,
                 norm: (month_norm * (to - from + 1) / days_in_month.to_r).round)
    end
  end
end
