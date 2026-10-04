require_relative "spec_helper"

RSpec.describe Diary::Duration do
  it "читает и пишет длительности" do
    expect(described_class.parse("5:40:28")).to eq(20_428)
    expect(described_class.parse("05:30")).to eq(19_800)
    expect(described_class.parse("-0:11:20")).to eq(-680)
    expect(described_class.parse_legacy("5h 54m")).to eq(21_240)
    expect(described_class.parse_legacy("39m")).to eq(2_340)
    expect(described_class.hms(20_428)).to eq("5:40:28")
    expect(described_class.hm(20_428)).to eq("05:40")
    expect(described_class.hm(20_431)).to eq("05:41")
    expect(described_class.signed(-680)).to eq("-0:11:20")
  end
end

RSpec.describe Diary::TrackerExport do
  subject(:export) { described_class.new(File.join(FIXTURES, "tracker.csv"), work_groups: %w[Ruby Работа Domcap]) }

  it "берёт только рабочие записи и режет их по полуночи" do
    expect(export.entries.map { [_1.date.to_s, _1.start, _1.finish, _1.seconds, _1.activity] }).to eq(
      [["2026-10-03", "07:30:00", "08:00:00", 1800, "Отчётность"],
       ["2026-10-02", "14:00:00", "16:00:00", 7200, "#7001"],
       ["2026-10-02", "10:00:00", "13:00:00", 10_800, "А портал"],
       ["2026-10-01", "23:00:00", "24:00:00", 3600, "А портал"],
       ["2026-10-02", "00:00:00", "01:00:00", 3600, "А портал"]]
    )
  end

  it "знает, какие дни покрыты целиком" do
    expect(export.complete_dates).to eq([Date.new(2026, 10, 2)])
  end
end

RSpec.describe Diary::DayReport do
  let(:plan) { ["#7386", "#7474", "отчётность", "связь с командой"] }
  let(:entries) do
    [entry("2026-10-03", "Отчётность", 600), entry("2026-10-03", "А портал", 3600, start: "13:00:00", finish: "14:00:00"),
     entry("2026-10-03", "Б портал", 1800, start: "09:00:00", finish: "09:30:00"), entry("2026-10-03", "Связь портал", 300),
     entry("2026-10-03", "В портал", 900)]
  end
  let(:report) { described_class.new(Date.new(2026, 10, 3), entries, plan, config) }

  it "привязывает «А/Б портал» к пунктам плана" do
    expect(report.items).to eq([["#7386", 3600], ["#7474", 1800], ["отчётность", 600], ["связь с командой", 300],
                                ["? В портал", 900]])
    expect(report.unresolved).to eq(["? В портал"])
    expect([report.came, report.left, report.total]).to eq(["09:00:00", "14:00:00", 7200])
  end

  it "пишет план и итог в формате чата" do
    expect(report.plan_text).to eq(
      "План на день 03.10\n1. Domcap: \n    а) #7386\n    б) #7474\n    в) отчётность\n    г) связь с командой"
    )
    expect(report.result_text).to start_with("Итог на день 03.10\n1. Domcap: 02:00\n    а) #7386 01:00\n    б) #7474 00:30")
  end
end

RSpec.describe Diary::LegacyRecords do
  let(:records) { described_class.new(File.join(FIXTURES, "records")) }

  it "переносит старые записи и чинит опечатку в годе" do
    expect(records.entries.map { [_1.date.to_s, _1.activity, _1.seconds] }).to eq(
      [["2023-03-15", "#1487", 8700], ["2023-03-15", "#1490, #1491", 3600],
       ["2026-07-28", "#7068", 21_900], ["2026-07-28", "#7069", 2340]]
    )
    expect(records.skipped).to eq(["tests this day 4h 47m"])
  end
end

RSpec.describe Diary::TelegramChat do
  it "берёт только мои «План/Итог» и восстанавливает год" do
    reports = described_class.new(File.join(FIXTURES, "chat")).reports("Ivan")
    expect(reports.map { _1.values_at("date", "kind") }).to eq(
      [%w[2026-10-04 plan], %w[2026-10-03 result], %w[2025-12-31 result]]
    )
    expect(reports.first["text"]).to eq("План на день 04.10\n1. Domcap: \n    а) #7386\n    б) отчётность")
  end
end

RSpec.describe Diary::Progress do
  it "делит цель поровну по дням месяца и режет неделю границей месяца" do
    log = instance_double(Diary::WorkLog, between: [entry("2026-10-01", "А портал", 64_790)])
    progress = described_class.new(log, config)
    expect(progress.month(Date.new(2026, 10, 3)).then { [_1.norm, _1.deviation] }).to eq([64_800, -10])
    expect(progress.week(Date.new(2026, 10, 3)).from).to eq(Date.new(2026, 10, 1))
    expect(progress.week(Date.new(2026, 10, 7)).from).to eq(Date.new(2026, 10, 5))
  end
end

RSpec.describe Diary::App do
  around do |example|
    Dir.mktmpdir do |root|
      FileUtils.cp(File.join(Diary::ROOT, "config.yml"), root)
      FileUtils.mkdir_p(File.join(root, "data"))
      @root = root
      example.run
    end
  end

  let(:app) { described_class.new(root: @root, today: Date.new(2026, 10, 4)) }
  let(:csv) { File.join(FIXTURES, "tracker.csv") }

  it "заменяет целиком покрытые дни и дописывает края выгрузки" do
    app.log.replace_day(Date.new(2026, 10, 2), [entry("2026-10-02", "А портал", 60, start: "08:00:00")])
    app.log.replace_day(Date.new(2026, 10, 1), [entry("2026-10-01", "#7000", 3600, source: "screenshot")])
    app.import_tracker(csv)

    expect(app.log.for_date(Date.new(2026, 10, 2)).map(&:start)).to contain_exactly("00:00:00", "10:00:00", "14:00:00")
    expect(app.log.for_date(Date.new(2026, 10, 1)).map(&:activity)).to eq(["#7000"])
    expect(app.log.for_date(Date.new(2026, 10, 3)).map(&:activity)).to eq(["Отчётность"])
  end

  it "собирает «План — Итог» по дням в одно сообщение" do
    app.import_tracker(csv)
    app.days.set_plan(Date.new(2026, 10, 2), ["#7386", "#7474", "отчётность"])
    app.days.set_plan(Date.new(2026, 10, 3), ["#7386", "отчётность"])
    messages = app.telegram_messages([Date.new(2026, 10, 2), Date.new(2026, 10, 3)])

    expect(messages.size).to eq(1)
    expect(messages.first.scan(/^(План|Итог) на день (\S+)/)).to eq(
      [%w[План 02.10], %w[Итог 02.10], %w[План 03.10], %w[Итог 03.10]]
    )
    expect(messages.first).to include("а) #7386 04:00\n    б) #7001 02:00")
  end

  it "пишет ежемесячный отчёт по шаблону" do
    expect(app.month_report(2026, 9, 665_327)).to eq(
      "Здравствуйте! Отчёт за сентябрь:\nСентябрь 2026го\nPortal.Domcup 184:48:47\nРасчёт зарплаты уже в таблице"
    )
  end
end

RSpec.describe Diary::Timesheet do
  let(:sheet_config) do
    instance_double(Diary::Config, private_setting: "x", path: "key.json").tap do |c|
      allow(c).to receive(:norm_seconds).and_return(186 * 3600)
    end
  end
  let(:timesheet) { described_class.new(sheet_config) }

  it "строит месяц: дни, итоги недель после воскресений и в конце месяца, ИТОГИ" do
    layout = timesheet.send(:layout, 2026, 10)
    expect(layout.map(&:first).tally).to eq(header: 1, title: 1, day: 31, subtotal: 5, totals: 1)
    expect(layout.select { _1.first == :subtotal }.map { _1.last.last.day }).to eq([4, 11, 18, 25, 31])

    values = timesheet.send(:block_values, layout, 100, 2026, 10)
    expect(values[2][:values]).to eq([["Четверг", "01.10.2026", "14:00:00", "20:00:00", "=D102-C102-F102", "0:00:00", ""]])
    expect(values[6][:values]).to eq([["", "", "", "24:00:00", "=SUM(E102:E105)", "", "=E106-D106"]])
    expect(values.last[:values].first.values_at(0, 4)).to eq(["ИТОГИ", "=E106+E114+E122+E130+E137"])
  end
end
