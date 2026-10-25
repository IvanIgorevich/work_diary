require "tempfile"

module Diary
  # Пересоздаваемая SQLite-копия data/ для запросов. CSV/YAML остаются источником.
  # В private/ не попадают ключи, настройки доступов или сырые выгрузки трекера.
  class Database
    SCHEMA = <<~SQL.freeze
      PRAGMA foreign_keys = ON;
      BEGIN;
      CREATE TABLE days (
        date TEXT PRIMARY KEY,
        project TEXT NOT NULL,
        plan_auto INTEGER NOT NULL CHECK (plan_auto IN (0, 1)),
        total_seconds INTEGER CHECK (total_seconds >= 0),
        start TEXT,
        "end" TEXT
      );
      CREATE TABLE plan_items (
        date TEXT NOT NULL REFERENCES days(date),
        position INTEGER NOT NULL CHECK (position >= 1),
        item TEXT NOT NULL,
        PRIMARY KEY (date, position)
      );
      CREATE TABLE work_entries (
        id INTEGER PRIMARY KEY,
        date TEXT NOT NULL REFERENCES days(date),
        start TEXT,
        "end" TEXT,
        duration_seconds INTEGER NOT NULL CHECK (duration_seconds >= 0),
        activity TEXT NOT NULL,
        source TEXT NOT NULL,
        report_task TEXT NOT NULL
      );
      CREATE TABLE entry_allocations (
        entry_id INTEGER NOT NULL REFERENCES work_entries(id),
        report_task TEXT NOT NULL,
        duration_seconds INTEGER NOT NULL CHECK (duration_seconds >= 0),
        PRIMARY KEY (entry_id, report_task)
      );
      CREATE TABLE task_parents (
        task TEXT PRIMARY KEY,
        report_task TEXT NOT NULL
      );
      CREATE TABLE telegram_reports (
        id INTEGER PRIMARY KEY,
        date TEXT NOT NULL REFERENCES days(date),
        kind TEXT NOT NULL,
        sent_at TEXT,
        text TEXT NOT NULL
      );
      CREATE TABLE reporting_statuses (
        date TEXT NOT NULL REFERENCES days(date),
        channel TEXT NOT NULL CHECK (channel IN ('document', 'chat', 'sheet', 'diary')),
        status TEXT NOT NULL CHECK (status IN ('done', 'partial', 'pending', 'unknown')),
        marked_at TEXT,
        PRIMARY KEY (date, channel)
      );
      CREATE INDEX work_entries_date_task ON work_entries(date, report_task);
      CREATE INDEX telegram_reports_date_kind ON telegram_reports(date, kind);
      CREATE VIEW report_totals AS
        SELECT entries.date, allocations.report_task, SUM(allocations.duration_seconds) AS duration_seconds
        FROM work_entries AS entries JOIN entry_allocations AS allocations ON allocations.entry_id = entries.id
        GROUP BY entries.date, allocations.report_task;
      PRAGMA user_version = 2;
    SQL

    attr_reader :path

    def initialize(config)
      @config = config
      @path = config.path("private/work_diary.sqlite3")
    end

    # Новая база сначала проверяется; при ошибке предыдущая копия остаётся целой.
    def rebuild
      @journals = {}
      sql = snapshot_sql
      FileUtils.mkdir_p(File.dirname(path))
      Tempfile.create(["work_diary-", ".sqlite3"], File.dirname(path)) do |file|
        file.close
        out, err, status = Open3.capture3("sqlite3", "-batch", "-bail", file.path,
                                         stdin_data: sql + "COMMIT;\nPRAGMA quick_check;\n")
        raise Error, "Не удалось пересобрать SQLite: #{err.strip}" unless status.success?
        raise Error, "Проверка SQLite завершилась ошибкой: #{out.strip}" unless out.strip == "ok"

        File.rename(file.path, path)
      end
      path
    rescue Errno::ENOENT => e
      raise Error, "Для базы дневника нужен sqlite3: #{e.message}"
    end

    def statuses(date)
      day_data = read_yaml("data/days.yml")
      first_date = day_data.keys.min&.then { Date.parse(_1) }
      sent_reports = read_telegram.select { _1["date"] == date.to_s }
      reporting_statuses(date, day_data.fetch(date.to_s, {}), first_date, sent_reports)
        .to_h { |channel, status, _| [channel, status] }
    end

    private

    def snapshot_sql
      log = WorkLog.new(@config.path("data/work_log.csv"))
      day_data = read_yaml("data/days.yml")
      days = Days.new(@config.path("data/days.yml"))
      telegram = read_telegram
      dates = (log.dates + day_data.keys.map { Date.parse(_1) } + telegram.map { Date.parse(_1.fetch("date")) }).uniq.sort
      sent_reports = telegram.group_by { _1["date"] }
      statements = [SCHEMA]
      entry_id = 0

      dates.each do |date|
        entries = log.for_date(date)
        report = DayReport.new(date, entries, days.plan(date), @config, assign: days.assign(date))
        attributes = day_data.fetch(date.to_s, {})
        statements << insert("days", [date.to_s, @config.project, days.auto_plan?(date) ? 1 : 0,
                                      entries.empty? ? nil : report.total, report.came, report.left])
        report.plan.each_with_index do |item, index|
          statements << insert("plan_items", [date.to_s, index + 1, item])
        end
        # Тот же механизм привязки, что у текстового отчёта, включая неразобранные пункты.
        resolved = entries.map(&:activity).uniq.to_h do |activity|
          sample = entries.find { _1.activity == activity }
          [activity, DayReport.new(date, [sample], report.plan, @config).items.first.first]
        end
        entries.each do |entry|
          entry_id += 1
          statements << insert("work_entries", [entry_id, date.to_s, entry.start, entry.finish,
                                                entry.seconds, entry.activity, entry.source, resolved.fetch(entry.activity)])
          # Исходный отрезок не делим: разбивка задач по assign хранится отдельно,
          # тем же механизмом, что и в каноническом отчёте дня.
          DayReport.new(date, [entry], report.plan, @config, assign: days.assign(date)).items.each do |item, seconds|
            statements << insert("entry_allocations", [entry_id, item, seconds])
          end
        end
        reporting_statuses(date, attributes, days.first_date, sent_reports[date.to_s]).each do |channel, status, marked_at|
          statements << insert("reporting_statuses", [date.to_s, channel, status, marked_at])
        end
      end

      read_yaml("data/tasks.yml").fetch("parents", {}).to_h.sort_by { _1.first.to_s }.each do |task, parent|
        statements << insert("task_parents", ["##{task}", "##{parent}"])
      end
      telegram.each do |row|
        statements << insert("telegram_reports", [nil, *row.values_at("date", "kind", "sent_at", "text")])
      end
      statements.join("\n") + "\n"
    end

    def reporting_statuses(date, attributes, first_date, sent_reports)
      managed = first_date && date >= first_date
      missing = managed ? "pending" : "unknown"
      {
        "document" => attributes["document"],
        "chat" => attributes["sent"] || attributes["chat"],
        "sheet" => attributes["sheet"],
        "diary" => attributes["diary"]
      }.map do |channel, mark|
        done = mark && mark != false
        status = done ? "done" : missing
        if channel == "chat" && !done
          kinds = (sent_reports.to_a.map { _1["kind"] } | attributes.fetch("sent_parts", [])) & %w[plan result]
          status = kinds.size == 2 ? "done" : "partial" if kinds.any?
          mark = sent_reports.to_a.select { kinds.include?(_1["kind"]) }.filter_map { _1["sent_at"] }.max
        end
        status = journal_status(date) || status if channel == "diary" && !done
        [channel, status, mark ? mark.to_s : nil]
      end
    end

    def journal_status(date)
      @journals ||= {}
      month = date.strftime("%Y-%m")
      text = @journals.fetch(month) do
        file = @config.path("journal", "#{month}.md")
        @journals[month] = File.exist?(file) ? File.read(file) : ""
      end
      return unless text.match?(/^План на день #{date.strftime('%d.%m')}$/)

      text.match?(/^Итог на день #{date.strftime('%d.%m')}$/) ? "done" : "partial"
    end

    def read_yaml(file)
      path = @config.path(file)
      File.exist?(path) ? YAML.load_file(path) || {} : {}
    end

    def read_telegram
      path = @config.path("data/telegram_reports.csv")
      File.exist?(path) ? CSV.read(path, headers: true).map(&:to_h) : []
    end

    def insert(table, values) = "INSERT INTO #{table} VALUES (#{values.map { literal(_1) }.join(', ')});"

    # Hex-литералы сохраняют кавычки и переносы строк, исключая интерпретацию CLI-команд.
    def literal(value)
      return "NULL" if value.nil?
      return value.to_s if value.is_a?(Integer)

      "CAST(X'#{value.to_s.encode(Encoding::UTF_8).unpack1('H*')}' AS TEXT)"
    end
  end
end
