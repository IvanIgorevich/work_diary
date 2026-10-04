module Diary
  # Google-документ «Отчёты»: черновики планов и месячные отчёты. Месячный отчёт встаёт
  # перед последним «План на день 01.<следующий месяц>», как раньше; если такого плана нет — в конец.
  class ReportsDoc
    API = "https://docs.googleapis.com/v1/documents/".freeze

    def initialize(config)
      @id = config.private_setting("reports_doc", "id") or raise Error, "Нет reports_doc.id в private/config.yml"
      @google = Google.new(config.path(config.private_setting("sheet", "key_file") || "private/google-key.json"))
      @backups = config.path("private/backups")
    end

    def include?(text) = paragraphs.map(&:last).join.include?(text)

    # Куда встанет отчёт за месяц: [индекс, описание места]
    def place_for(year, month)
      next_month = Date.new(year, month, 1).next_month
      plan = /\AПлан на день 0?1\.#{format('%02d', next_month.month)}\b/
      found = paragraphs.reverse.find { |_, text| text.match?(plan) }
      found ? [found.first, "перед «#{found.last.strip}»"] : [paragraphs.last.first + paragraphs.last.last.size - 1, "в конец"]
    end

    # Вставляет отчёт с пустыми строками до следующего плана; возвращает путь к локальной копии документа
    def insert(text, index)
      backup = Backup.new(@google, @backups).save(@id)
      @google.post("#{API}#{@id}:batchUpdate", { requests: [{ insertText: { location: { index: }, text: "#{text}\n\n\n" } }] })
      @paragraphs = nil
      backup
    end

    private

    # [[начальный индекс, текст абзаца], ...]
    def paragraphs
      @paragraphs ||= @google.get("#{API}#{@id}").dig("body", "content").filter_map do |element|
        runs = element.dig("paragraph", "elements") or next
        [element["startIndex"], runs.map { _1.dig("textRun", "content").to_s }.join]
      end
    end
  end
end
