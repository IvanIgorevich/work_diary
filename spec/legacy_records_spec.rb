require_relative "spec_helper"

RSpec.describe Diary::LegacyRecords, "производные записи с прежними переносами строк" do
  it "сверяет SHA до удаления CR, исключает производные часы и сохраняет ручные архивы" do
    Dir.mktmpdir do |dir|
      archive = "\n\r17:59\n\r\n2026-09-20:\n1) #6077, this day 6h, total 135h 12m\n"
      generated = "\n\r20:45\n\r\n2026-10-08:\n1) #7208, this day 6h 5m, total 27h 47m\n" \
                  "2) отчётность, this day 20m, total recorded 35m\n"
      name = "2026-10-09.txt"
      File.write(File.join(dir, "2026-09-21.txt"), archive)
      File.write(File.join(dir, name), generated)
      manifest = { name => Diary::Records.digest(generated) }
      records = described_class.new(dir, generated: manifest)

      expect(records.entries.map { [_1.date.to_s, _1.activity, _1.seconds] }).to eq(
        [["2026-09-20", "#6077", 21_600]]
      )
      expect(records.dates).to eq([Date.new(2026, 9, 20)])
      expect(records.skipped).to be_empty
      expect(File.read(File.join(dir, "2026-09-21.txt"))).to eq(archive)

      # Изменённый вручную файл больше не совпадает с манифестом и остаётся архивом.
      File.write(File.join(dir, name), generated.sub("this day 6h 5m", "this day 5h"))
      edited = described_class.new(dir, generated: manifest)
      expect(edited.entries.map { [_1.date.to_s, _1.activity, _1.seconds] }).to include(
        ["2026-10-08", "#7208", 18_000]
      )
      expect(edited.dates).to include(Date.new(2026, 10, 8))
    end
  end
end
