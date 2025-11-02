require "rspec/autorun"
require_relative "../diary"

RSpec.describe "find_previous_total_time" do
  let(:records_path) { File.join(File.dirname(__FILE__), "records") }

  let(:test_file_path) { File.join(records_path, "2025-10-30.txt") }

  before do
    Dir.mkdir(records_path) unless Dir.exist?(records_path)

    File.open(test_file_path, "w:UTF-8") do |file|
      file.puts("10:00")

      file.puts("2025-10-30:")

      file.puts("1) #4976, this day 5h, total 9h 33m")

      file.puts("2) #4977, this day 30m, total 1h 30m")

      file.puts("3) #4978, this day 2h 15m, total 5h 45m")

      file.puts("4) #4979, this day 45m, start")

      file.puts("5) #4980, this day 3h, start")

      file.puts("------------------------------")
    end
  end

  after do
    File.delete(test_file_path) if File.exist?(test_file_path)
  end

  context "when task has hours only in 'this day'" do
    let(:task_number) { "4976" }

    it do
      expect(find_previous_total_time(task_number)).to eq(573)
    end
  end

  context "when task has minutes only in 'this day'" do
    let(:task_number) { "4977" }

    it do
      expect(find_previous_total_time(task_number)).to eq(90)
    end
  end

  context "when task has both hours and minutes in 'this day'" do
    let(:task_number) { "4978" }

    it do
      expect(find_previous_total_time(task_number)).to eq(345)
    end
  end

  context "when task has minutes only and marked as start" do
    let(:task_number) { "4979" }

    it do
      expect(find_previous_total_time(task_number)).to eq(0)
    end
  end

  context "when task has hours only and marked as start" do
    let(:task_number) { "4980" }

    it do
      expect(find_previous_total_time(task_number)).to eq(0)
    end
  end

  context "when task does not exist" do
    let(:task_number) { "9999" }

    it do
      expect(find_previous_total_time(task_number)).to eq(nil)
    end
  end
end

RSpec.describe "time_to_minutes" do
  context "when time string has hours and minutes" do
    it { expect(time_to_minutes("5h 30m")).to eq(330) }
  end

  context "when time string has hours only" do
    it { expect(time_to_minutes("5h")).to eq(300) }
  end

  context "when time string has minutes only" do
    it { expect(time_to_minutes("30m")).to eq(30) }
  end

  context "when time string is 'start'" do
    it { expect(time_to_minutes("start")).to eq(0) }
  end

  context "when time string is zero minutes" do
    it { expect(time_to_minutes("0m")).to eq(0) }
  end
end

RSpec.describe "format_time" do
  context "when hours and minutes are both greater than zero" do
    it { expect(format_time(5, 30)).to eq("5h 30m") }
  end

  context "when only hours are greater than zero" do
    it { expect(format_time(5, 0)).to eq("5h") }
  end

  context "when only minutes are greater than zero" do
    it { expect(format_time(0, 30)).to eq("30m") }
  end

  context "when both hours and minutes are zero" do
    it { expect(format_time(0, 0)).to eq("0m") }
  end
end

