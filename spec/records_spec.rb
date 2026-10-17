require_relative "spec_helper"

RSpec.describe "Прежние ежедневные записи" do
  around do |example|
    Dir.mktmpdir do |root|
      @root = root
      FileUtils.cp(File.join(Diary::ROOT, "config.yml"), root)
      FileUtils.mkdir_p(File.join(root, "data"))
      FileUtils.mkdir_p(File.join(root, "records"))
      example.run
    end
  end

  let(:day) { Date.new(2026, 9, 21) }
  let(:app) { Diary::App.new(root: @root, today: Date.new(2026, 10, 8)) }
  let(:old_text) { "\n\r17:59\n\r\n2026-09-20:\n1) #6077, this day 6h, total 135h 12m\n------------------------------\n" }

  def record(date) = app.config.path("records", "#{date + 1}.txt")

  before do
    File.write(app.config.path("records/2026-09-21.txt"), old_text)
    app.log.replace_day(day - 1, [entry((day - 1).to_s, "#6077", 21_600, source: "diary")])
    app.days.set_plan(day, ["#6077", "отчётность", "связь с командой", "документация"])
    app.log.replace_day(day, [entry(day.to_s, "А портал", 17_659), entry(day.to_s, "Отчётность", 900),
                             entry(day.to_s, "Документация", 947)])
    app.days.set_plan(day + 1, ["#6077", "отчётность"])
    app.log.replace_day(day + 1, [entry((day + 1).to_s, "А портал", 3600),
                                 entry((day + 1).to_s, "Связь портал", 61)])
    app.days.set_plan(app.today, ["#7208", "отчётность"])
    app.log.replace_day(app.today, [entry(app.today.to_s, "А портал", 999)])
  end

  it "автоматически дополняет завершённые дни в прежнем формате со всеми работами и точными секундами" do
    app.save
    first = File.read(record(day))
    second = File.read(record(day + 1))

    expect(File.binread(app.config.path("records/2026-09-21.txt"))).to eq(old_text)
    expect(first).to start_with("\n2026-09-21:\n")
    expect(first.lines.grep(/\A# /)).to be_empty
    expect(first).to include("2026-09-21:\n1) #6077, this day 4h 54m 19s, total 10h 54m 19s",
                            "2) отчётность, this day 15m, total recorded 15m",
                            "3) документация, this day 15m 47s, total recorded 15m 47s")
    expect(first).not_to include("связь с командой, this day")
    expect(second).to include("2026-09-22:\n1) #6077, this day 1h, total 11h 54m 19s",
                             "2) связь с командой, this day 1m 1s, total recorded 1m 1s")
    expect(File).not_to exist(record(app.today))
    generated = YAML.load_file(app.config.path("data/records_generated.yml"))
    expect(generated.keys).to eq(["2026-09-22.txt", "2026-09-23.txt"])
    legacy = Diary::LegacyRecords.new(app.config.path("records"), generated:)
    expect(legacy.entries.map(&:date)).to eq([day - 1])
    expect(legacy.skipped).to be_empty
  end

  it "сохраняет архивы и повторяется без изменения файлов, а исправленный CSV обновляет накопление следующих дней" do
    result = app.backfill_records
    expect(result.written).to eq([day, day + 1])
    originals = Dir[app.config.path("records/*.txt")].to_h { [_1, File.binread(_1)] }
    modified_at = File.mtime(record(day))
    result = app.backfill_records

    expect(result.written).to be_empty
    expect(result.unchanged).to eq([day, day + 1])
    expect(Dir[app.config.path("records/*.txt")].to_h { [_1, File.binread(_1)] }).to eq(originals)
    expect(File.mtime(record(day))).to eq(modified_at)
    app.log.replace_day(day, [entry(day.to_s, "А портал", 7201)])
    expect(app.backfill_records.written).to eq([day, day + 1])
    expect(File.read(record(day + 1))).to include("total 9h 1s")
    expect(File.binread(app.config.path("records/2026-09-21.txt"))).to eq(old_text)
  end

  it "сохраняет историческую рабочую дату независимо от имени файла и сообщает конфликт пути" do
    existing = "2026-09-21:\n1) #6077, this day 4h\n"
    File.write(app.config.path("records/2026-09-23.txt"), existing)
    result = app.backfill_records

    expect(result.preserved).to eq([day])
    expect(result.conflicts).to eq([day + 1])
    expect(result.written).to be_empty
    expect(File).not_to exist(record(day))
    expect(File.read(app.config.path("records/2026-09-23.txt"))).to eq(existing)
  end

  it "не создаёт записей без фактов и сохраняет неизвестные задачи как неразобранные вместо выдуманного номера" do
    app.days.set_plan(day + 2, ["#6077", "отчётность"])
    app.days.set_plan(day + 3, ["отчётность"])
    app.log.replace_day(day + 3, [entry((day + 3).to_s, "Б портал", 17)])
    app.backfill_records

    expect(File).not_to exist(record(day + 2))
    expect(File.read(record(day + 3))).to include("1) ? Б портал, this day 17s, total recorded 17s")
  end

  it "migrate-records не дублирует производные дни и не добавляет архив поверх более точных данных" do
    app.save
    # Непроизводная старая запись той же рабочей даты тоже не может дублировать трекер.
    File.write(app.config.path("records/2026-09-24.txt"), "2026-09-22:\n1) #6077, this day 1h\n")
    original = File.binread(app.config.path("data/work_log.csv"))
    2.times do
      cli = Diary::CLI.new(["migrate-records"])
      allow(cli).to receive(:app).and_return(app)
      expect { cli.run }.to output("Перенесено 1 записей за 1 дн., всего 6:00:00\n").to_stdout
    end

    expect(File.binread(app.config.path("data/work_log.csv"))).to eq(original)
    expect(app.log.for_date(day).sum(&:seconds)).to eq(19_506)
    expect(app.log.for_date(day + 1).map(&:source).uniq).to eq(["tracker"])
  end

  it "позволяет заполнить все управляемые завершённые даты отдельной командой, не меняя канонические источники" do
    app.log.save
    app.days.save
    sources = %w[data/work_log.csv data/days.yml].to_h { [_1, File.binread(app.config.path(_1))] }
    cli = Diary::CLI.new(["backfill-records"])
    allow(cli).to receive(:app).and_return(app)

    expect { cli.run }.to output("Записано 2 дн., актуальных 0, архивов сохранено 0.\n").to_stdout
    expect(%w[data/work_log.csv data/days.yml].to_h { [_1, File.binread(app.config.path(_1))] }).to eq(sources)
  end

  it "пишет время конца работы в начале, как diary.rb" do
    app.log.replace_day(day, [entry(day.to_s, "А портал", 3600, start: "17:00:00", finish: "18:00:00")])
    app.backfill_records
    expect(File.binread(record(day))).to start_with("\n\r18:00\n\r\n2026-09-21:\n1) #6077, this day 1h")
  end
end
