require_relative "spec_helper"

RSpec.describe Diary::App do
  around do |example|
    Dir.mktmpdir do |root|
      FileUtils.cp(File.join(Diary::ROOT, "config.yml"), root)
      FileUtils.mkdir_p(File.join(root, "data"))
      @root = root
      example.run
    end
  end

  subject(:app) do
    described_class.new(root: @root, today: Date.new(2026, 10, 8))
  end

  let(:dates) { [Date.new(2026, 10, 4), Date.new(2026, 10, 5)] }
  let(:sent_kinds) { ["plan"] }

  before do
    dates.each do |date|
      app.log.replace_day(date, [entry(date.to_s, "А портал", 3600)])
      app.days.set_plan(date, ["#7208", "отчётность"])
    end
    CSV.open(File.join(@root, "data/telegram_reports.csv"), "w") do |csv|
      csv << %w[date kind sent_at text]
      sent_kinds.each do |kind|
        csv << [dates.first.to_s, kind, "2026-10-04T16:53:29+04:00", kind]
      end
    end
  end

  context "when the first plan is already in the chat" do
    it "starts with the missing result and retains subsequent pairs" do
      expect(app.telegram_messages(dates, pending_only: true).join
        .scan(/^(План|Итог) на день (\S+)/)).to eq(
          [["Итог", "04.10"], ["План", "05.10"], ["Итог", "05.10"]]
        )
    end

    it "keeps full pairs when preparing the complete record" do
      expect(app.telegram_messages(dates).join
        .scan(/^(План|Итог) на день (\S+)/)).to eq(
          [["План", "04.10"], ["Итог", "04.10"],
           ["План", "05.10"], ["Итог", "05.10"]]
        )
    end
  end

  context "when both parts are already in the chat" do
    let(:sent_kinds) { ["plan", "result"] }

    it "omits the completed first day" do
      expect(app.telegram_messages(dates, pending_only: true).join
        .scan(/^(План|Итог) на день (\S+)/)).to eq(
          [["План", "05.10"], ["Итог", "05.10"]]
        )
    end
  end

  context "when the user has confirmed the whole day was sent" do
    before { app.days.mark(dates.last, "sent", "2026-10-08") }

    it "does not resend the confirmed day" do
      expect(app.telegram_messages(dates, pending_only: true).join
        .scan(/^(План|Итог) на день (\S+)/)).to eq([["Итог", "04.10"]])
    end
  end
end
