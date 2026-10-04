require "cgi"
require "csv"
require "date"
require "digest"
require "erb"
require "fileutils"
require "json"
require "net/http"
require "open3"
require "optparse"
require "time"
require "yaml"

Encoding.default_external = Encoding::UTF_8

module Diary
  class Error < StandardError; end

  ROOT = File.expand_path("..", __dir__)
end

require_relative "diary/duration"
require_relative "diary/config"
require_relative "diary/work_log"
require_relative "diary/days"
require_relative "diary/tasks"
require_relative "diary/tracker_export"
require_relative "diary/git_activity"
require_relative "diary/day_report"
require_relative "diary/progress"
require_relative "diary/journal"
require_relative "diary/legacy_records"
require_relative "diary/telegram_chat"
require_relative "diary/google_sheets"
require_relative "diary/timesheet"
require_relative "diary/salary"
require_relative "diary/app"
require_relative "diary/cli"
