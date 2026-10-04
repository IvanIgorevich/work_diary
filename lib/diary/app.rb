module Diary
  # Журнал работы, планы, отметки и всё, что из них собирается.
  class App
    attr_reader :config, :log, :days, :today

    def initialize(root: ROOT, today: Date.today)
      @config = Config.new(root)
      @log = WorkLog.new(config.path("data/work_log.csv"))
      @days = Days.new(config.path("data/days.yml"))
      @tasks = Tasks.new(config.path("data/tasks.yml"))
      @today = today
    end

    def save
      log.save
      days.save
      write_journal
    end

    def last_day(include_today = false) = include_today ? today : today - 1

    # Дни с работой, которые ведутся по-новому (с первого дня в data/days.yml)
    def work_dates(to = last_day)
      from = days.first_date or return []
      log.dates.select { _1.between?(from, to) }
    end

    def report(date) = DayReport.new(date, log.for_date(date), days.plan(date), config)
    def progress = Progress.new(log, config)

    # Новые выгрузки трекера: копия как есть — в private/tracker/, рабочие записи — в журнал.
    def import_exports
      archive = config.path("private/tracker")
      FileUtils.mkdir_p(archive)
      known = Dir[File.join(archive, "*")].map { Digest::SHA256.file(_1).hexdigest }
      config.export_globs.flat_map { Dir[_1] }.uniq.sort_by { File.mtime(_1) }.filter_map do |file|
        digest = Digest::SHA256.file(file).hexdigest
        next if known.include?(digest)

        FileUtils.cp(file, File.join(archive, "#{File.basename(file, '.csv')}-#{digest[0, 8]}.csv"))
        known << digest
        import_tracker(file)
        file
      end
    end

    # Полностью покрытые выгрузкой дни заменяются целиком, края выгрузки дописываются.
    def import_tracker(file)
      export = TrackerExport.new(file, work_groups: config.work_groups)
      return if export.empty?

      fresh = export.entries.group_by(&:date)
      complete = export.complete_dates
      (export.from.to_date..export.to.to_date).each do |date|
        if complete.include?(date)
          log.replace_day(date, fresh.fetch(date, []))
        elsif fresh.key?(date)
          existing = log.for_date(date)
          next if existing.any? { _1.source != "tracker" }

          starts = fresh[date].map(&:start)
          log.replace_day(date, existing.reject { starts.include?(_1.start) } + fresh[date])
        end
      end
    end

    # План для дней без плана: задачи по веткам и коммитам, остальные пункты — как в предыдущем плане.
    def fill_plans(dates)
      missing = dates.reject { days.plan(_1) }
      return [] if missing.empty?

      git = GitActivity.new(repos: config.git_repos, tasks: @tasks, since: missing.min - 90)
      missing.each do |date|
        previous = days.previous_plan(date) || []
        tasks = git.tasks_on(date)
        tasks = previous.select { _1.start_with?("#") } if tasks.empty?
        rest = previous.reject { _1.start_with?("#") }
        days.set_plan(date, tasks + (rest.empty? ? config.default_items : rest), auto: true)
      end
    end

    # Сообщения в чат: «План — Итог» по дням подряд, не длиннее лимита Telegram
    def telegram_messages(dates, limit: 4000)
      dates.each_with_object([]) do |date, messages|
        day = "#{report(date).plan_text}\n\n#{report(date).result_text}"
        if messages.empty? || messages.last.size + day.size + 3 > limit
          messages << day
        else
          messages.last << "\n\n\n" << day
        end
      end
    end

    def month_report(year, month, total)
      format(config.month_report, month_lower: MONTHS[month - 1].downcase, month: MONTHS[month - 1],
                                  year:, total: Duration.hms(total))
    end

    # Часы по задачам: за период и всего к концу периода
    def summary(from, to)
      period = Hash.new(0)
      total = Hash.new(0)
      log.dates.select { _1 <= to }.each do |date|
        report(date).items.each do |item, seconds|
          total[item] += seconds
          period[item] += seconds if date >= from
        end
      end
      period.keys.map { [_1, period[_1], total[_1]] }.sort_by { |item, _, all| [item.start_with?("#") ? 0 : 1, -all] }
    end

    # Мои «План/Итог» из экспорта чата → data/telegram_reports.csv (без повторов)
    def save_telegram_reports(rows)
      path = config.path("data/telegram_reports.csv")
      existing = File.exist?(path) ? CSV.read(path, headers: true).map(&:to_h) : []
      merged = (existing + rows).uniq { _1.values_at("sent_at", "kind", "date") }.sort_by { _1.values_at("sent_at", "date") }
      CSV.open(path, "w") do |csv|
        csv << %w[date kind sent_at text]
        merged.each { csv << _1.values_at("date", "kind", "sent_at", "text") }
      end
      merged.size - existing.size
    end

    private

    def write_journal
      from = days.first_date or return
      journal = Journal.new(config.path("journal"))
      (from..last_day).map { [_1.year, _1.month] }.uniq.each do |year, month|
        to = [Date.new(year, month, -1), last_day].min
        reports = work_dates(to).select { _1.year == year && _1.month == month }.map { report(_1) }
        legacy_until = log.between(Date.new(year, month, 1), to).select { _1.source == "diary" }.map(&:date).max
        journal.write(year, month, reports, progress.month(to), legacy_until:)
      end
    end
  end
end
