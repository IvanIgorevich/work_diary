module Diary
  class CLI
    USAGE = <<~TEXT.freeze
      bin/report                     новые выгрузки трекера → журнал, планы, сводка по неотчитанным дням
      bin/report telegram            «План — Итог» для чата по неотправленным дням
      bin/report sheet               внести дни в таблицу времени
      bin/report month [ГГГГ-ММ]     ежемесячный отчёт (по умолчанию — за прошлый месяц)
      bin/report push                коммит и пуш дневника
      bin/report summary С ПО        часы по задачам за период
      bin/report db                  пересобрать SQLite из CSV/YAML (источники не меняются)
      bin/report import-chat ПАПКА   сохранить экспорт чата Telegram
      bin/report migrate-records     перенести старые records/*.txt в журнал
      bin/report backfill-records    дополнить прежние записи по завершённым дням

        --today            включить сегодняшний (незаконченный) день
        --plan-today       в конце сообщения для чата — план на сегодня (без итога)
        --from ДАТА        с какого дня (для сводки, telegram, sheet)
        --to ДАТА          по какой день
        --city ГОРОД       город для сообщения коммита (по умолчанию — из прошлого коммита)
        -y, --yes          не спрашивать подтверждение
    TEXT

    def initialize(argv)
      @options = {}
      @args = OptionParser.new do |o|
        o.banner = USAGE
        o.on("--today") { @options[:today] = true }
        o.on("--plan-today") { @options[:plan_today] = true }
        o.on("--from DATE") { @options[:from] = Date.parse(_1) }
        o.on("--to DATE") { @options[:to] = Date.parse(_1) }
        o.on("--city CITY") { @options[:city] = _1 }
        o.on("-y", "--yes") { @options[:yes] = true }
      end.parse(argv)
      @command = @args.shift || "status"
    end

    def run
      case @command
      when "status" then status
      when "telegram" then telegram
      when "sheet" then sheet
      when "month" then month
      when "push" then push
      when "summary" then summary
      when "db" then database
      when "import-chat" then import_chat
      when "migrate-records" then migrate_records
      when "backfill-records" then backfill_records
      else abort USAGE
      end
    rescue Error => e
      abort "Ошибка: #{e.message}"
    end

    private

    def app = @app ||= App.new

    def status
      imported = app.import_exports
      dates = app.work_dates(app.last_day(@options[:today]))
      app.fill_plans(dates)
      app.save
      puts "Импортировано: #{imported.map { File.basename(_1) }.join(', ')}\n\n" if imported.any?

      shown = @options[:from] ? dates.select { _1 >= @options[:from] } : dates.reject { app.reporting_statuses(_1).values.all? { |status| status == "done" } }
      if shown.empty?
        puts "Все четыре части отчётности завершены."
      else
        shown.each { puts day_line(_1) }
        auto = shown.select { app.days.auto_plan?(_1) }
        puts "\nПлан составлен автоматически (проверьте в data/days.yml): #{auto.map { _1.strftime('%d.%m') }.join(', ')}" if auto.any?
      end
      puts "", progress_lines(dates.last || app.last_day)
    end

    def day_line(date)
      report = app.report(date)
      span = report.came ? "#{report.came[0, 5]}–#{report.left[0, 5]}" : "     —     "
      items = report.items.map { |item, seconds| "#{item} #{Duration.hm(seconds)}" }.join(" · ")
      labels = { "document" => "документ", "chat" => "чат", "sheet" => "таблица", "diary" => "дневник" }
      symbols = { "done" => "✓", "partial" => "частично", "pending" => "✗", "unknown" => "?" }
      flags = app.reporting_statuses(date).map { |channel, status| "#{labels.fetch(channel)} #{symbols.fetch(status)}" }
      flags << "план авто" if app.days.auto_plan?(date)
      flags << "непонятно: #{report.unresolved.join(', ')}" if report.unresolved.any?
      format("%-9s %9s  %-11s  %s   [%s]", report.title, Duration.hms(report.total), span, items, flags.join(", "))
    end

    def progress_lines(date)
      month = app.progress.month(date)
      week = app.progress.week(date)
      ["#{MONTHS[date.month - 1]}: #{month}, цель на месяц #{month.month_norm / 3600} ч",
       "Неделя #{week}"]
    end

    def telegram
      dates = selected_dates { !app.days.sent?(_1) }
      return puts("Все дни уже отправлены.") if dates.empty?

      unresolved = dates.select { app.report(_1).unresolved.any? }
      abort "Сначала поправьте план (data/days.yml) для: #{unresolved.map { _1.strftime('%d.%m') }.join(', ')}" if unresolved.any?

      messages = app.telegram_messages(dates, pending_only: true)
      if @options[:plan_today] && app.days.plan(app.today) && !app.days.sent_parts(app.today).include?("plan")
        today = app.report(app.today).plan_text
        messages.empty? || messages.last.size + today.size + 3 > 4000 ? messages << today : messages.last << "\n\n\n" << today
      end
      return puts("Все части отчётов уже отправлены.") if messages.empty?

      messages.each_with_index do |text, i|
        puts "----- сообщение #{i + 1} из #{messages.size} -----" if messages.size > 1
        puts text, ""
      end
      return unless confirm?("Отметить #{dates.size} дн. как отправленные?")

      dates.each { app.days.mark(_1, "sent") }
      app.days.mark_sent_part(app.today, "plan") if @options[:plan_today] && app.days.plan(app.today)
      app.save
    end

    def sheet
      reports = selected_dates { !app.days.in_sheet?(_1) }.map { app.report(_1) }
      without_time = reports.reject(&:came)
      puts "Нет отрезков времени, пропускаю: #{without_time.map(&:title).join(', ')}" if without_time.any?
      reports -= without_time
      return puts("Все дни уже в таблице.") if reports.empty?

      reports.each do |r|
        pause = Duration.parse(r.left) - Duration.parse(r.came) - r.total
        puts format("%-9s пришёл %s  ушёл %s  перерыв %s  на месте %s", r.title, r.came, r.left,
                    Duration.hms(pause), Duration.hms(r.total))
      end
      return unless confirm?("Записать в таблицу времени?")

      backup = Timesheet.new(app.config).write_days(reports)
      reports.each { app.days.mark(_1.date, "sheet") }
      app.save
      puts "Готово. Копия таблицы до изменений: #{relative(backup)}", progress_lines(reports.last.date)
    end

    def month
      year, month = (@args.first || (app.today << 1).strftime("%Y-%m")).split("-").map(&:to_i)
      sheet_total = begin
        Timesheet.new(app.config).month_total(year, month)
      rescue Error, SystemCallError => e
        warn "Таблица времени недоступна (#{e.message}), считаю по журналу."
        nil
      end
      total = sheet_total || app.log.between(Date.new(year, month, 1), Date.new(year, month, -1)).sum(&:seconds)
      text = app.month_report(year, month, total)
      puts text
      salary(month, total) if sheet_total && app.config.private_setting("salary", "id")
      reports_doc(year, month, text) if sheet_total && app.config.private_setting("reports_doc", "id")
    end

    # Дата и часы в строке месяца в таблице зарплаты (сумму считает формула)
    def salary(month, total)
      salary = Salary.new(app.config)
      row = salary.row(month) or return puts("\nВ таблице зарплаты нет строки «за #{MONTHS[month - 1].downcase}».")
      return puts("\nТаблица зарплаты: «#{row.description}» уже заполнена — #{row.hours} ч.") unless row.hours.to_s.strip.empty?

      hours = Salary.hours(total)
      puts "\nТаблица зарплаты, строка #{row.number} «#{row.description}»: дата #{app.today.strftime('%d.%m.%Y')}, " \
           "часы #{format('%g', hours)} (итог месяца вверх до четверти часа)"
      return unless confirm?("Записать?")

      backup = salary.fill(row, hours, app.today)
      puts "Записано. Копия таблицы до изменений: #{relative(backup)}"
    end

    # Месячный отчёт — в документ «Отчёты», перед планом на первое число следующего месяца
    def reports_doc(year, month, text)
      doc = ReportsDoc.new(app.config)
      return puts("\nДокумент «Отчёты»: отчёт уже есть.") if doc.include?(text.lines[0, 2].join)

      index, place = doc.place_for(year, month)
      puts "\nДокумент «Отчёты»: вставить отчёт #{place}"
      return unless confirm?("Вставить?")

      puts "Вставлено. Копия документа до изменений: #{relative(doc.insert(text, index))}"
    end

    def relative(path) = path.delete_prefix("#{app.config.root}/")

    def database
      puts "База пересобрана: #{relative(app.rebuild_database)}"
    end

    def push
      Dir.chdir(app.config.root) do
        system("git", "add", "data", "journal", exception: true)
        staged = `git diff --cached --name-only`.lines.map(&:chomp)
        return puts("Нечего коммитить.") if staged.empty?
        abort "В коммит попало личное: #{staged.grep(%r{\Aprivate/}).join(', ')}" if staged.grep(%r{\Aprivate/}).any?

        city = @options[:city] || `git log -1 --format=%s`.strip[%r{\A\d+/\d+/\d{4} (.+)\z}, 1]
        message = [app.today.strftime("%-m/%-d/%Y"), city].compact.join(" ")
        puts `git diff --cached --stat`, "", "Коммит: #{message}"
        return unless confirm?("Закоммитить и запушить?")

        system("git", "commit", "-q", "-m", message, exception: true)
        system("git", "push", "-q", exception: true)
        puts "Запушено."
      end
    end

    def summary
      from, to = @args.map { Date.parse(_1) }
      abort USAGE unless from && to

      rows = app.summary(from, to)
      rows.each { |item, period, all| puts format("%-28s %10s за период, %10s всего", item, Duration.hms(period), Duration.hms(all)) }
      puts format("%-28s %10s", "Итого", Duration.hms(rows.sum { _2 }))
    end

    def import_chat
      abort USAGE if @args.empty?

      @args.each do |dir|
        archive = app.config.path("private/telegram", File.basename(dir))
        FileUtils.mkdir_p(File.dirname(archive))
        FileUtils.cp_r(dir, archive) unless File.exist?(archive)
        added = app.save_telegram_reports(TelegramChat.new(dir).reports(app.config.telegram_name))
        puts "#{File.basename(dir)}: новых отчётов #{added}, копия — private/telegram/"
      end
    end

    def migrate_records
      manifest = app.config.path("data/records_generated.yml")
      generated = File.exist?(manifest) ? YAML.load_file(manifest) || {} : {}
      legacy = LegacyRecords.new(app.config.path("records"), generated:)
      # Даже архивы не добавляются поверх более точного CSV/трекера той же даты.
      covered = app.log.entries.reject { _1.source == "diary" }.map(&:date).uniq
      entries = legacy.entries.reject { covered.include?(_1.date) }
      app.log.replace_source("diary", entries)
      app.log.save
      app.rebuild_database
      puts "Перенесено #{entries.size} записей за #{entries.map(&:date).uniq.size} дн., " \
           "всего #{Duration.hms(entries.sum(&:seconds))}"
      puts "Не разобрано (оставлено в records/):", legacy.skipped.map { "  #{_1}" } if legacy.skipped.any?
    end

    def backfill_records
      result = app.backfill_records
      puts "Записано #{result.written.size} дн., актуальных #{result.unchanged.size}, " \
           "архивов сохранено #{result.preserved.size}."
      if result.conflicts.any?
        puts "Архив занимает имя файла, оставлен без изменений: #{result.conflicts.map(&:to_s).join(', ')}"
      end
    end

    # Дни для telegram/sheet: явный диапазон или все, что ещё не сделаны
    def selected_dates(&pending)
      dates = app.work_dates(app.last_day(@options[:today]))
      return dates.select(&pending) unless @options[:from] || @options[:to]

      dates.select { _1.between?(@options[:from] || dates.first, @options[:to] || dates.last) }
    end

    def confirm?(question)
      return true if @options[:yes]
      return false unless $stdin.tty?

      print "#{question} [y/N] "
      answer = $stdin.gets.to_s.strip
      # «н» — та же клавиша, что «y», в русской раскладке
      return true if answer.downcase.match?(/\A[yдн]/)

      puts "Ответ #{answer.inspect} — ничего не меняю."
      false
    end
  end
end
