module Diary
  # Ежедневная текстовая версия прежнего дневника — в том же виде, что писал diary.rb:
  # время, рабочая дата, только номерные задачи и их часы, разделитель.
  # Служебные активности остаются в CSV, журнале и БД. Файлы, сгенерированные из data/,
  # записано отдельно, в data/records_generated.yml (имя файла → SHA-256 содержимого):
  # такие файлы можно перезаписывать и нельзя повторно мигрировать как рабочие часы.
  class Records
    Result = Struct.new(:written, :unchanged, :preserved, :conflicts, keyword_init: true)
    # Заголовок первых сгенерированных файлов; такие файлы тоже считаются производными
    OLD_MARKER = "# work_diary derived record v1; source=data/work_log.csv,data/days.yml".freeze

    def self.digest(text) = Digest::SHA256.hexdigest(text)

    def initialize(dir, manifest)
      @dir = dir
      @manifest_path = manifest
      @generated = File.exist?(manifest) ? YAML.load_file(manifest) || {} : {}
    end

    # Имя файла — следующий день после работы, как в прежнем дневнике.
    # Архивы и записи, сделанные вручную, не перезаписываются, даже если заняли ожидаемый путь.
    def write(reports, totals:)
      result = Result.new(written: [], unchanged: [], preserved: [], conflicts: [])
      archive_dates = LegacyRecords.new(@dir, generated: @generated).dates
      FileUtils.mkdir_p(@dir) unless reports.empty?
      reports.each do |report|
        if archive_dates.include?(report.date)
          result.preserved << report.date
          next
        end

        name = "#{report.date + 1}.txt"
        file = File.join(@dir, name)
        existing = File.exist?(file) ? File.read(file, encoding: "UTF-8") : nil
        unless existing.nil? || generated?(name, existing)
          result.conflicts << report.date
          next
        end

        text = render(report, totals.fetch(report.date))
        if existing == text
          @generated[name] = self.class.digest(text)
          result.unchanged << report.date
          next
        end

        Tempfile.create(["record-", ".txt"], @dir) do |temp|
          temp.write(text)
          temp.close
          File.rename(temp.path, file)
        end
        @generated[name] = self.class.digest(text)
        result.written << report.date
      end
      save_manifest
      result
    end

    private

    def generated?(name, text) = @generated[name] == self.class.digest(text) || text.start_with?(OLD_MARKER)

    # Как diary.rb: "\n\r17:59\n\r\n2026-09-20:\n1) ...\n-----\n". Время — конец работы в этот день.
    def render(report, totals)
      head = report.left ? "\n\r#{report.left[0, 5]}\n\r\n" : "\n"
      lines = ["#{report.date}:"]
      report.items.select { |item, _| item.match?(/\A#\d+\z/) }.each_with_index do |(item, seconds), index|
        lines << "#{index + 1}) #{item}, this day #{duration(seconds)}, total #{duration(totals.fetch(item))}"
      end
      head + lines.push("------------------------------", "").join("\n")
    end

    def save_manifest
      FileUtils.mkdir_p(File.dirname(@manifest_path))
      File.write(@manifest_path, YAML.dump(@generated.sort.to_h))
    end

    def duration(seconds)
      hours, rest = seconds.divmod(3600)
      minutes, seconds = rest.divmod(60)
      [hours.positive? ? "#{hours}h" : nil, minutes.positive? ? "#{minutes}m" : nil,
       seconds.positive? ? "#{seconds}s" : nil].compact.then { _1.empty? ? "0m" : _1.join(" ") }
    end
  end
end
