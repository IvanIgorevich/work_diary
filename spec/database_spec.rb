require_relative "spec_helper"

RSpec.describe Diary::Database do
  around do |example|
    Dir.mktmpdir do |root|
      @root = root
      FileUtils.cp(File.join(Diary::ROOT, "config.yml"), root)
      FileUtils.mkdir_p(File.join(root, "data"))
      example.run
    end
  end

  let(:app) { Diary::App.new(root: @root, today: Date.new(2026, 10, 8)) }
  let(:database) { described_class.new(app.config) }
  let(:day) { Date.new(2026, 10, 4) }

  def rows(sql)
    out, err, status = Open3.capture3("sqlite3", "-json", database.path, sql)
    raise err unless status.success?

    out.empty? ? [] : JSON.parse(out)
  end

  def source_bytes
    Dir[File.join(@root, "{data,journal}", "*")].sort.to_h { [_1, File.binread(_1)] }
  end

  before do
    app.days.set_plan(day, ["#7208", "отчётность"])
    app.days.set_plan(day + 1, ["#7208", "отчётность", "связь с командой"])
    app.days.set_plan(app.today, ["#7208", "отчётность"])
    app.log.replace_day(day, [entry(day.to_s, "А портал", 12_341, start: "12:00:00", finish: "15:25:41"),
                             entry(day.to_s, "Связь портал", 300, start: "23:55:00", finish: "24:00:00")])
    app.log.replace_day(day + 1, [entry((day + 1).to_s, "Отчётность", 67)])
    app.days.mark(day, "document", "2026-10-08")
    app.days.mark(day, "sheet", "вручную")
    File.write(app.config.path("data/tasks.yml"), YAML.dump("parents" => { 7494 => 7208 }))
  end

  it "автоматически сохраняет точные секунды, привязку к плану и четыре статуса" do
    app.save

    expect(rows("SELECT date, start, \"end\", duration_seconds, activity, source, report_task FROM work_entries ORDER BY id")).to eq(
      [{ "date" => day.to_s, "start" => "12:00:00", "end" => "15:25:41", "duration_seconds" => 12_341,
         "activity" => "А портал", "source" => "tracker", "report_task" => "#7208" },
       { "date" => day.to_s, "start" => "23:55:00", "end" => "24:00:00", "duration_seconds" => 300,
         "activity" => "Связь портал", "source" => "tracker", "report_task" => "связь с командой" },
       { "date" => (day + 1).to_s, "start" => nil, "end" => nil, "duration_seconds" => 67,
         "activity" => "Отчётность", "source" => "tracker", "report_task" => "отчётность" }]
    )
    expect(rows("SELECT * FROM report_totals ORDER BY date, report_task").sum { _1.fetch("duration_seconds") }).to eq(12_708)
    expect(rows("SELECT * FROM task_parents")).to eq([{ "task" => "#7494", "report_task" => "#7208" }])
    expect(database.statuses(day)).to eq("document" => "done", "chat" => "pending", "sheet" => "done", "diary" => "done")
    expect(database.statuses(app.today)).to eq("document" => "pending", "chat" => "pending", "sheet" => "pending", "diary" => "partial")
    expect(rows("SELECT total_seconds FROM days WHERE date = '2026-10-08'")).to eq([{ "total_seconds" => nil }])
    expect(rows("SELECT * FROM reporting_statuses WHERE date = '2026-10-04'").size).to eq(4)
    expect(File.stat(database.path).mode & 0o777).to eq(0o600)
  end

  it "пересобирается без повторов и изменений источников" do
    app.save
    original_sources = source_bytes
    snapshot = rows("SELECT * FROM work_entries ORDER BY id")
    2.times { database.rebuild }

    expect(rows("SELECT * FROM work_entries ORDER BY id")).to eq(snapshot)
    expect(source_bytes).to eq(original_sources)
  end

  it "заменяет прежнюю копию актуальными строками и не хранит частные настройки" do
    app.save
    File.write(app.config.path("private/config.yml"), YAML.dump("secret" => "test-private-token"))
    app.log.replace_day(day, [entry(day.to_s, "А портал", 17)])
    app.save

    expect(rows("SELECT SUM(duration_seconds) AS total FROM work_entries")).to eq([{ "total" => 84 }])
    expect(File.binread(database.path)).not_to include("test-private-token")
  end

  it "сохраняет сообщения дословно и считает чат завершённым только при полной паре План–Итог" do
    app.save
    message = "Итог на день 04.10\nDomcap's отчёт\n.shell never-run"
    app.save_telegram_reports([{ "date" => day.to_s, "kind" => "result", "sent_at" => "2026-10-08T12:00:00+04:00", "text" => message }])

    expect(rows("SELECT text FROM telegram_reports")).to eq([{ "text" => message }])
    expect(described_class.new(app.config).statuses(day).fetch("chat")).to eq("partial")
    expect(rows("SELECT status FROM reporting_statuses WHERE channel='chat' AND date='2026-10-04'")).to eq([{ "status" => "partial" }])
    app.save_telegram_reports([{ "date" => day.to_s, "kind" => "plan", "sent_at" => "2026-10-04T12:00:00+04:00", "text" => "План на день 04.10" }])
    expect(described_class.new(app.config).statuses(day).fetch("chat")).to eq("done")
    expect(rows("SELECT status FROM reporting_statuses WHERE channel='chat' AND date='2026-10-04'")).to eq([{ "status" => "done" }])
  end

  it "считает один архивный План частичным даже для старой даты, а явную отметку sent завершением" do
    app.save
    old_day = Date.new(2023, 3, 14)
    app.save_telegram_reports([{ "date" => old_day.to_s, "kind" => "plan", "sent_at" => "2023-03-14T12:00:00+04:00", "text" => "План на день 14.03" }])
    expect(described_class.new(app.config).statuses(old_day).fetch("chat")).to eq("partial")
    expect(described_class.new(app.config).statuses(old_day - 1).fetch("chat")).to eq("unknown")
    app.days.mark(old_day, "sent", "2023-03-14")
    app.save

    expect(described_class.new(app.config).statuses(old_day).fetch("chat")).to eq("done")
    expect(rows("SELECT status FROM reporting_statuses WHERE channel='chat' AND date='2023-03-14'")).to eq([{ "status" => "done" }])
  end

  it "оставляет целую предыдущую базу, если новые данные не проходят ограничения" do
    app.save
    snapshot = File.binread(database.path)
    app.log.replace_day(day, [entry(day.to_s, "А портал", -60)])
    app.log.save

    expect { database.rebuild }.to raise_error(Diary::Error, /SQLite/)
    expect(File.binread(database.path)).to eq(snapshot)
    expect(Dir[app.config.path("private/work_diary-*")]).to be_empty
  end

  it "не выдаёт отсутствие сведений о старой отчётности за незавершённую работу" do
    app.log.replace_day(Date.new(2023, 3, 14), [entry("2023-03-14", "#1487", 123, source: "diary")])
    app.save

    expect(database.statuses(Date.new(2023, 3, 14)).values).to eq(%w[unknown unknown unknown unknown])
  end

  it "позволяет пересобрать базу командой db, не меняя CSV/YAML и дневник" do
    app.save
    originals = source_bytes
    cli = Diary::CLI.new(["db"])
    allow(cli).to receive(:app).and_return(app)

    expect { cli.run }.to output("База пересобрана: private/work_diary.sqlite3\n").to_stdout
    expect(source_bytes).to eq(originals)
  end
end

RSpec.describe "Планы и сохранение дневника" do
  around do |example|
    Dir.mktmpdir do |root|
      @root = root
      settings = YAML.load_file(File.join(Diary::ROOT, "config.yml"))
      settings.fetch("plan")["scheduled_items"] = { "связь с командой" => [1, 5] }
      settings.fetch("git")["repos"] = []
      settings.fetch("tracker")["exports"] = ["inbox/*.csv"]
      File.write(File.join(root, "config.yml"), YAML.dump(settings))
      FileUtils.mkdir_p(File.join(root, "data"))
      example.run
    end
  end

  let(:app) { Diary::App.new(root: @root, today: Date.new(2026, 10, 8)) }

  it "включает связь только по понедельникам и пятницам, в том числе после плана без неё" do
    app.days.set_plan(Date.new(2026, 10, 3), ["#7208", "отчётность", "связь с командой"])
    dates = (Date.new(2026, 10, 4)..Date.new(2026, 10, 10)).to_a
    app.fill_plans(dates)

    expect(dates.select { app.days.plan(_1).include?("связь с командой") }).to eq([Date.new(2026, 10, 5), Date.new(2026, 10, 9)])
    app.log.replace_day(Date.new(2026, 10, 4), [entry("2026-10-04", "Связь портал", 321)])
    expect(app.report(Date.new(2026, 10, 4)).items).to eq([["связь с командой", 321]])
  end

  it "сохраняет пары План–Итог и сегодняшний План без фиктивного итога, а прогресс считает по вчера" do
    dates = (Date.new(2026, 10, 4)..Date.new(2026, 10, 7)).to_a
    dates.each do |date|
      app.days.set_plan(date, ["#7208", "отчётность"])
      app.log.replace_day(date, [entry(date.to_s, "А портал", 3600)])
    end
    app.days.set_plan(app.today, ["#7208", "отчётность"])
    app.log.replace_day(app.today, [entry(app.today.to_s, "А портал", 999)])
    app.save
    journal = File.read(app.config.path("journal/2026-10.md"))

    expect(journal.scan(/^(План|Итог) на день (\S+)/)).to eq(
      dates.flat_map { |date| [["План", date.strftime("%d.%m")], ["Итог", date.strftime("%d.%m")]] } + [["План", "08.10"]]
    )
    expect(journal).to include("Отработано 4:00:00", "на 07.10")
    expect(journal).not_to include("Итог на день 08.10", "08.10 чт — 0:00:00")
  end

  it "на первом числе сохраняет план нового месяца без переноса прошлого баланса" do
    first = Diary::App.new(root: @root, today: Date.new(2026, 11, 1))
    first.days.set_plan(Date.new(2026, 10, 31), ["#7208"])
    first.log.replace_day(Date.new(2026, 10, 31), [entry("2026-10-31", "А портал", 7200)])
    first.days.set_plan(first.today, ["#7208", "отчётность"])
    first.save
    journal = File.read(first.config.path("journal/2026-11.md"))

    expect(journal).to include("План на день 01.11", "Завершённых дней в этом месяце пока нет.")
    expect(journal).not_to include("Итог на день", "2:00:00", "на 31.10")
  end

  it "сохраняет прошлые планы без фактов после смены даты, в общем порядке с полными парами" do
    [6, 7, 8].each { app.days.set_plan(Date.new(2026, 10, _1), ["#7208", "отчётность"]) }
    app.log.replace_day(Date.new(2026, 10, 7), [entry("2026-10-07", "А портал", 3600)])
    app.save
    next_day = Diary::App.new(root: @root, today: Date.new(2026, 10, 9))
    next_day.days.set_plan(next_day.today, ["#7208", "отчётность", "связь с командой"])
    next_day.log.replace_day(next_day.today, [entry("2026-10-09", "А портал", 999)])
    next_day.save
    journal = File.read(next_day.config.path("journal/2026-10.md"))

    expect(journal.scan(/^(План|Итог) на день (\S+)/)).to eq(
      [%w[План 06.10], %w[План 07.10], %w[Итог 07.10], %w[План 08.10], %w[План 09.10]]
    )
    expect(journal).not_to include("Итог на день 06.10", "Итог на день 08.10", "Итог на день 09.10")
    expect(next_day.reporting_statuses(Date.new(2026, 10, 8)).fetch("diary")).to eq("partial")
    expect(next_day.reporting_statuses(next_day.today).fetch("diary")).to eq("partial")
  end

  it "повторно импортирует архивированный, но не сохранённый CSV и отмечает digest только после save" do
    FileUtils.mkdir_p(app.config.path("inbox"))
    file = app.config.path("inbox/report.csv")
    FileUtils.cp(File.join(FIXTURES, "tracker.csv"), file)
    app.import_exports
    expect(File).not_to exist(app.config.path("private/imported_exports.yml"))

    fresh = Diary::App.new(root: @root, today: app.today)
    expect(fresh.import_exports).to eq([file])
    expect(fresh.import_exports).to be_empty
    fresh.days.set_plan(Date.new(2026, 10, 1), ["#7208", "отчётность"])
    fresh.save
    digest = Digest::SHA256.file(file).hexdigest
    expect(YAML.load_file(app.config.path("private/imported_exports.yml"))).to eq("sha256" => [digest])

    again = Diary::App.new(root: @root, today: app.today)
    count = again.log.entries.size
    expect(again.import_exports).to be_empty
    expect(again.log.entries.size).to eq(count)
  end

  it "не отмечает импорт обработанным при незавершённом сохранении" do
    FileUtils.mkdir_p(app.config.path("inbox"))
    FileUtils.cp(File.join(FIXTURES, "tracker.csv"), app.config.path("inbox/report.csv"))
    app.import_exports
    allow(app).to receive(:rebuild_database).and_raise(Diary::Error, "ошибка базы")

    expect { app.save }.to raise_error(Diary::Error, "ошибка базы")
    expect(File).not_to exist(app.config.path("private/imported_exports.yml"))
  end
end
