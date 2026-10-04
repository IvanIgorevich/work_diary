require "tmpdir"
require_relative "../lib/diary"

FIXTURES = File.expand_path("fixtures", __dir__)

module SpecHelpers
  def config = Diary::Config.new(Diary::ROOT)

  def entry(date, activity, seconds, start: nil, finish: nil, source: "tracker")
    Diary::Entry.new(date: Date.parse(date), start:, finish:, seconds:, activity:, source:)
  end
end

RSpec.configure do |c|
  c.include SpecHelpers
  c.disable_monkey_patching!
end
