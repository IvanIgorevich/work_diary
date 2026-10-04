module Diary
  MONTHS = %w[Январь Февраль Март Апрель Май Июнь Июль Август Сентябрь Октябрь Ноябрь Декабрь].freeze

  # journal/ГГГГ-ММ.md — планы и итоги по дням в том виде, в каком они уходят в чат.
  # Файлы собираются заново из data/, руками их не правлю.
  class Journal
    def initialize(dir)
      @dir = dir
    end

    # legacy_until — последний день месяца, записанный старым дневником (там только время задач)
    def write(year, month, reports, progress, legacy_until: nil)
      FileUtils.mkdir_p(@dir)
      File.write(File.join(@dir, format("%04d-%02d.md", year, month)),
                 render(year, month, reports, progress, legacy_until))
    end

    private

    def render(year, month, reports, progress, legacy_until)
      lines = ["# #{MONTHS[month - 1]} #{year}", "",
               "Отработано #{Duration.hms(progress.fact)} при цели #{Duration.hms(progress.norm)} " \
               "на #{progress.to.strftime('%d.%m')} (#{Duration.signed(progress.deviation)}), " \
               "цель на месяц #{progress.month_norm / 3600} ч.", ""]
      if legacy_until
        lines.push("По #{legacy_until.strftime('%d.%m')} — записи старого дневника: в них только время задач, " \
                   "без отчётности и связи с командой. Полный итог месяца — в таблице времени.", "")
      end
      reports.each do |report|
        span = report.came ? " (#{report.came[0, 5]}–#{report.left[0, 5]})" : ""
        lines.push("## #{report.title} — #{Duration.hms(report.total)}#{span}", "", "```",
                   report.plan_text, "", report.result_text, "```", "")
      end
      lines.join("\n")
    end
  end
end
