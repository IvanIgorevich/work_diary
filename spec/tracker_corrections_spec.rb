require_relative "spec_helper"

RSpec.describe Diary::App, "подтверждённые исправления выгрузки" do
  it "исключает только указанные части отрезка для известного SHA и не возвращает их при повторном импорте" do
    Dir.mktmpdir do |root|
      FileUtils.cp(File.join(Diary::ROOT, "config.yml"), root)
      FileUtils.mkdir_p(File.join(root, "data"))
      FileUtils.mkdir_p(File.join(root, "private"))
      file = File.join(root, "report.csv")
      FileUtils.cp(File.join(FIXTURES, "tracker.csv"), file)
      original = Diary::TrackerExport.new(file, work_groups: %w[Ruby Работа Domcap])
      initial = described_class.new(root:, today: Date.new(2026, 10, 4))
      initial.import_tracker(file)
      initial.save
      expect(initial.log.entries).to match_array(original.entries)
      exclusions = [
        { "date" => "2026-10-01", "start" => "23:00:00", "end" => "24:00:00", "activity" => "А портал" },
        { "date" => "2026-10-02", "start" => "00:00:00", "end" => "01:00:00", "activity" => "А портал" }
      ]
      File.write(File.join(root, "private/tracker_corrections.yml"),
                 YAML.dump("exports" => { Digest::SHA256.file(file).hexdigest => { "exclude" => exclusions } }))
      expected = original.entries.reject { _1.date == Date.new(2026, 10, 1) || _1.start == "00:00:00" }

      2.times do
        app = described_class.new(root:, today: Date.new(2026, 10, 4))
        app.import_tracker(file)
        app.save

        expect(app.log.entries).to match_array(expected)
        expect(app.log.for_date(Date.new(2026, 10, 1))).to be_empty
        expect(app.log.for_date(Date.new(2026, 10, 2)).find { _1.activity == "А портал" }.seconds).to eq(10_800)
        export = Diary::TrackerExport.new(file, work_groups: %w[Ruby Работа Domcap])
        expect([export.from, export.to, export.complete_dates]).to eq([original.from, original.to, original.complete_dates])
      end

      # Те же данные с другим SHA не наследуют исключения предыдущей выгрузки.
      changed = File.join(root, "another.csv")
      File.binwrite(changed, File.binread(file) + "\n")
      app = described_class.new(root:, today: Date.new(2026, 10, 4))
      app.import_tracker(changed)
      expect(app.log.entries).to match_array(original.entries)
    end
  end
end
