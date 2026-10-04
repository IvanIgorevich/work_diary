module Diary
  # HTML-экспорт чата из Telegram Desktop. Из него берутся только мои «План/Итог на день» —
  # без фото, без сообщений коллег.
  class TelegramChat
    REPORT = /\A(План|Итог) на день (\d{1,2})\.(\d{2})/
    STAMP = /title="(\d{2})\.(\d{2})\.(\d{4}) (\d{2}:\d{2}:\d{2}) UTC([+-]\d{2}:\d{2})"/

    def initialize(dir)
      @dir = dir
    end

    def reports(from_name)
      sender = nil
      messages.filter_map do |html|
        name = html[%r{<div class="from_name">\s*(.*?)\s*(?:<span|</div>)}m, 1]
        sender = CGI.unescapeHTML(name) if name
        next unless sender == from_name

        stamp = STAMP.match(html) or next
        body = html[%r{<div class="text">(.*?)</div>}m, 1] or next
        text = CGI.unescapeHTML(body.gsub(%r{<br\s*/?>}, "\n").gsub(/<[^>]+>/, "")).strip
        report = REPORT.match(text) or next
        sent_at = Time.iso8601("#{stamp[3]}-#{stamp[2]}-#{stamp[1]}T#{stamp[4]}#{stamp[5]}")
        date = report_date(report[2].to_i, report[3].to_i, sent_at) or next
        { "date" => date.to_s, "kind" => report[1] == "План" ? "plan" : "result",
          "sent_at" => sent_at.iso8601, "text" => text }
      end
    end

    private

    def messages
      files = Dir[File.join(@dir, "messages*.html")].sort_by { _1[/messages(\d*)\.html\z/, 1].to_i }
      files.flat_map { File.read(_1, encoding: "UTF-8").split(/(?=<div class="message (?:default|service))/).drop(1) }
    end

    # В тексте нет года: берётся год отправки, а если дата ушла в будущее — предыдущий.
    def report_date(day, month, sent_at)
      date = Date.new(sent_at.year, month, day)
      date > sent_at.to_date + 7 ? date.prev_year : date
    rescue Date::Error
      nil
    end
  end
end
