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
      @pending_export_digests = []
    end

    def save
      log.save
      days.save
      write_journal
      backfill_records
      rebuild_database
      save_processed_exports
    end

    def rebuild_database = (@database = Database.new(config)).rebuild
    def reporting_statuses(date) = (@database ||= Database.new(config)).statuses(date)

    def last_day(include_today = false) = include_today ? today : today - 1

    # Дни с работой, которые ведутся по-новому (с первого дня в data/days.yml)
    def work_dates(to = last_day)
      from = days.first_date or return []
      log.dates.select { _1.between?(from, to) }
    end

    def report(date) = DayReport.new(date, log.for_date(date), days.plan(date), config, assign: days.assign(date))
    def progress = Progress.new(log, config)

    # Дополняет прежние records/*.txt по всем управляемым завершённым дням.
    # Исторические файлы остаются как были; новые обновляются из CSV/YAML.
    def backfill_records
      dates = work_dates
      reports = dates.map { report(_1) }
      totals = dates.to_h { |date| [date, summary(date, date).to_h { |item, _, all| [item, all] }] }
      Records.new(config.path("records"), config.path("data/records_generated.yml")).write(reports, totals:)
    end

    # Новые выгрузки трекера: копия как есть — в private/tracker/, рабочие записи — в журнал.
    def import_exports
      archive = config.path("private/tracker")
      FileUtils.mkdir_p(archive)
      processed = processed_exports | @pending_export_digests
      config.export_globs.flat_map { Dir[_1] }.uniq.sort_by { File.mtime(_1) }.filter_map do |file|
        digest = Digest::SHA256.file(file).hexdigest
        next if processed.include?(digest)

        archived = File.join(archive, "#{File.basename(file, '.csv')}-#{digest[0, 8]}.csv")
        FileUtils.cp(file, archived) unless File.exist?(archived)
        import_tracker(file)
        @pending_export_digests << digest
        processed << digest
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
        items = tasks + (rest.empty? ? config.default_items : rest)
        scheduled = config.scheduled_items
        items = items.reject { scheduled.key?(_1) && !scheduled[_1].include?(date.cwday) }
        scheduled.each { |item, weekdays| items << item if weekdays.include?(date.cwday) && !items.include?(item) }
        days.set_plan(date, items, auto: true)
      end
    end

    # Сообщения в чат: «План — Итог» по дням подряд, не длиннее лимита Telegram
    def telegram_messages(dates, limit: 4000, pending_only: false)
      sent = pending_only ? sent_report_parts : {}
      dates.each_with_object([]) do |date, messages|
        next if pending_only && days.sent?(date)

        parts = { "plan" => report(date).plan_text,
                  "result" => report(date).result_text }
        parts.reject! { |kind, _| sent.fetch(date.to_s, []).include?(kind) }
        next if parts.empty?

        day = parts.values.join("\n\n")
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
      rebuild_database
      merged.size - existing.size
    end

    private

    def sent_report_parts
      file = config.path("data/telegram_reports.csv")
      return {} unless File.exist?(file)

      parts = CSV.read(file, headers: true).group_by { _1["date"] }
                 .transform_values { _1.map { |row| row["kind"] }.uniq }
      days.dates.each { |date| parts[date.to_s] = parts.fetch(date.to_s, []) | days.sent_parts(date) }
      parts
    end

    def processed_exports
      file = config.path("private/imported_exports.yml")
      File.exist?(file) ? (YAML.load_file(file) || {}).fetch("sha256", []) : []
    end

    def save_processed_exports
      return if @pending_export_digests.empty?

      file = config.path("private/imported_exports.yml")
      digests = (processed_exports | @pending_export_digests).sort
      Tempfile.create(["imported_exports-", ".yml"], File.dirname(file)) do |temp|
        temp.write(YAML.dump("sha256" => digests))
        temp.close
        File.rename(temp.path, file)
      end
      @pending_export_digests.clear
    end

    def write_journal
      from = days.first_date or return
      journal = Journal.new(config.path("journal"))
      planned_dates = days.dates.select do |date|
        date <= today && days.plan(date) && (date == today || log.for_date(date).empty?)
      end
      months = (from..last_day).map { [_1.year, _1.month] }.uniq
      months |= planned_dates.map { [_1.year, _1.month] }
      months.each do |year, month|
        month_start = Date.new(year, month, 1)
        to = [Date.new(year, month, -1), last_day].min
        reports = work_dates(to).select { _1.year == year && _1.month == month }.map { report(_1) }
        legacy_until = log.between(month_start, to).select { _1.source == "diary" }.map(&:date).max
        planned_reports = planned_dates.select { _1.year == year && _1.month == month }.map { report(_1) }
        totals = to >= month_start ? progress.month(to) : nil
        journal.write(year, month, reports, totals, legacy_until:, planned_reports:)
      end
    end
  end
end
