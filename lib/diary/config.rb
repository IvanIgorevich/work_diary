module Diary
  # config.yml — общие настройки (в git), private/config.yml — доступы (вне git).
  class Config
    attr_reader :root

    def initialize(root)
      @root = root
      @data = YAML.load_file(path("config.yml"))
      @private = File.exist?(path("private/config.yml")) ? YAML.load_file(path("private/config.yml")) : {}
    end

    def path(*parts) = File.join(root, *parts)

    def private_setting(*keys) = @private.dig(*keys)

    # Цель на месяц в секундах
    def norm_seconds(year, month)
      hours = @data.fetch("norm_overrides", nil).to_h.fetch(format("%04d-%02d", year, month), @data.fetch("norm_hours"))
      (hours * 3600).round
    end

    def export_globs = tracker.fetch("exports").map { File.expand_path(_1, root) }
    def work_groups = tracker.fetch("work_groups")
    def plan_letter = Regexp.new(tracker.fetch("plan_letter"))
    def activities = tracker.fetch("activities")

    def project = @data.dig("plan", "project")
    def default_items = @data.dig("plan", "default_items")

    def git_repos = @data.dig("git", "repos").map { File.expand_path(_1) }

    def telegram_name = @data.dig("telegram", "from_name")
    def month_report = @data.fetch("month_report")

    private

    def tracker = @data.fetch("tracker")
  end
end
