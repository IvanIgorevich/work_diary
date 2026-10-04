module Diary
  # Длительности храню в секундах, показываю как в трекере и в отчётах.
  module Duration
    module_function

    # "5:30:00", "05:30", "-0:11:20" → секунды
    def parse(text)
      sign = text.start_with?("-") ? -1 : 1
      hours, minutes, seconds = text.delete_prefix("-").split(":").map(&:to_i)
      sign * ((hours * 60 + minutes) * 60 + seconds.to_i)
    end

    # Формат старых записей: "5h 54m", "39m", "6h" → секунды
    def parse_legacy(text)
      (text[/(\d+)h/, 1].to_i * 60 + text[/(\d+)m/, 1].to_i) * 60
    end

    # 20428 → "5:40:28"
    def hms(seconds)
      hours, rest = seconds.abs.divmod(3600)
      format("%s%d:%02d:%02d", sign(seconds), hours, *rest.divmod(60))
    end

    # 20428 → "05:40", как в «Итоге на день»
    def hm(seconds)
      format("%s%02d:%02d", sign(seconds), *(seconds.abs / 60.0).round.divmod(60))
    end

    # Отклонение со знаком: "+1:20:25", "-0:11:20"
    def signed(seconds)
      seconds.negative? ? hms(seconds) : "+#{hms(seconds)}"
    end

    def sign(seconds) = seconds.negative? ? "-" : ""
  end
end
