require "date"
require "active_support/all"

# Set encoding for Windows platform
if Gem.win_platform?
  Encoding.default_external = Encoding.find(Encoding.locale_charmap)
  Encoding.default_internal = __ENCODING__

  [STDIN, STDOUT].each do |io|
    io.set_encoding(Encoding.default_external, Encoding.default_internal)
  end
end

# Method to save the work diary
def save_work_diary(directory)
  puts Time.now
  puts "Work diary"
  puts "Save until row == \"end\", next row is 'Enter'"

  case directory
  when 'w'
    save_weekly_report
  when 'm'
    save_monthly_report
  else
    save_daily_record
  end
end

# Method to save weekly report
def save_weekly_report
  current_path = File.dirname(__FILE__)
  weekly_reports_path = File.join(current_path, "weekly_reports")
  Dir.mkdir(weekly_reports_path) unless Dir.exist?(weekly_reports_path)

  time = Time.now.to_date
  start_of_week = time.beginning_of_week(:monday)
  end_of_week = start_of_week + 6.days
  file_name = start_of_week.strftime("weekly_report_%Y-%m-%d")

  file_path = File.join(weekly_reports_path, file_name)
  save_report(file_path, start_of_week, end_of_week)
end

# Method to save monthly report
def save_monthly_report
  current_path = File.dirname(__FILE__)
  monthly_reports_path = File.join(current_path, "monthly_reports")
  Dir.mkdir(monthly_reports_path) unless Dir.exist?(monthly_reports_path)

  time = Time.now.to_date - 1.month
  start_of_month = time.beginning_of_month
  end_of_month = time.end_of_month
  file_name = (start_of_month + 1.month).strftime("monthly_report_%Y-%m-%d")

  file_path = File.join(monthly_reports_path, file_name)
  save_report(file_path, start_of_month, end_of_month)
end

# Method to save daily record
def save_daily_record
  current_path = File.dirname(__FILE__)
  records_path = File.join(current_path, "records")
  Dir.mkdir(records_path) unless Dir.exist?(records_path)

  all_lines = []
  line = nil

  while line != "end" do
    line = STDIN.gets.encode("UTF-8").chomp
    all_lines << line
  end

  all_lines.pop

  time = Time.now
  file_name = time.strftime("%Y-%m-%d")
  time_string = time.strftime("%H:%M")
  separator = "------------------------------"

  file_path = File.join(records_path, "#{file_name}.txt")
  File.open(file_path, "a:UTF-8") do |file|
    file.puts("\n\r#{time_string}\n\r")
    all_lines.each do |item|
      file.puts(item)
    end
    file.puts(separator)
  end

  puts "Saved in records/#{file_name}.txt"
end

# Method to save the report (common for weekly and monthly)
def save_report(file_path, start_date, end_date)
  File.open(file_path, "a:UTF-8") do |file|
    all_lines = []
    while true do
      line = STDIN.gets.encode("UTF-8").chomp
      break if line == "end"
      all_lines << line
    end

    file.puts("\n\r#{start_date.strftime("%Y-%m-%d")} - #{end_date.strftime("%Y-%m-%d")}\n\r")
    all_lines.each do |item|
      file.puts(item)
    end
    file.puts("------------------------------")
  end

  puts "Saved in #{file_path}"
end

# Call the save_work_diary method with the command line argument
save_work_diary(ARGV[0])
