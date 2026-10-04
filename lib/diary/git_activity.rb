module Diary
  # Над какими задачами шла работа в день: ветка, открытая к началу дня, переключения веток (reflog)
  # и коммиты. Номер задачи берётся из имени ветки (feature/7386-...) или из «#7386» в коммите.
  class GitActivity
    def initialize(repos:, tasks:, since:)
      @repos = repos
      @tasks = tasks
      @since = since
    end

    # ["#7240", "#7474"] — в порядке, в котором задачи появлялись в течение дня
    def tasks_on(date)
      day_start = midnight(date)
      day_end = midnight(date + 1)
      active = checkouts.select { |time, _| time < day_start }.max_by(&:first)&.last
      during = events.select { |time, _| time >= day_start && time < day_end }.map(&:last)
      ([active] + during).compact.map { "##{@tasks.report_task(_1)}" }.uniq
    end

    private

    def events = @events ||= (checkouts + commits).sort_by(&:first)

    def checkouts
      @checkouts ||= @repos.flat_map do |repo|
        git(repo, "log", "-g", "--date=iso-strict", "--format=%gd%x09%gs", "HEAD").lines.filter_map do |line|
          selector, subject = line.chomp.split("\t", 2)
          branch = subject.to_s[/\Acheckout: moving from \S+ to (\S+)\z/, 1] or next
          [Time.iso8601(selector[/\{(.+)\}/, 1]), branch[%r{(?:\A|/)(\d{3,})}, 1]]
        end
      end
    end

    def commits
      @repos.flat_map do |repo|
        author = git(repo, "config", "user.email").strip
        git(repo, "log", "--all", "--author=#{author}", "--since=#{@since}", "--format=%aI%x09%s").lines.filter_map do |line|
          time, subject = line.chomp.split("\t", 2)
          task = subject.to_s[/#(\d+)/, 1] or next
          [Time.iso8601(time), task]
        end
      end
    end

    def git(repo, *args)
      out, status = Open3.capture2("git", "-C", repo, *args, err: File::NULL)
      status.success? ? out : ""
    end

    def midnight(date) = Time.new(date.year, date.month, date.day)
  end
end
