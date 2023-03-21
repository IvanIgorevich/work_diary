require 'date'
require 'active_support/all'

if Gem.win_platform?
  Encoding.default_external = Encoding.find(Encoding.locale_charmap)
  Encoding.default_internal = __ENCODING__

  [STDIN, STDOUT].each do |io|
    io.set_encoding(Encoding.default_external, Encoding.default_internal)
  end
end

# def beginning_of_week(date, start_day = :monday)
#   date = Date.parse(date) if date.is_a?(String)
#   days_into_week = date.wday - Date.const_get(start_day.titleize).to_i
#   days_into_week += 7 if days_into_week < 0
#   date - days_into_week
# end

def save_work_diary(directory)
  puts Time.now
  puts "Work diary"
  puts "Save until row == \"end\", next row is 'Enter'"

  current_path = File.dirname(__FILE__)
  if directory == 'w'
    weekly_reports_path = File.join(current_path, "weekly_reports")
    Dir.mkdir(weekly_reports_path) unless Dir.exist?(weekly_reports_path)

    time = Time.now.to_date
    start_of_week = time.beginning_of_week(:monday)
    end_of_week = start_of_week + 6.days
    file_name = start_of_week.strftime("weekly_report_%Y-%m-%d")

    file_path = File.join(weekly_reports_path, file_name)
    File.open(file_path, "a:UTF-8") do |file|
      all_lines = []
      while true do
        line = STDIN.gets.encode("UTF-8").chomp
        break if line == "end"
        all_lines << line
      end

      file.puts("\n\r#{start_of_week.strftime("%Y-%m-%d")} - #{end_of_week.strftime("%Y-%m-%d")}\n\r")
      all_lines.each do |item|
        file.puts(item)
      end
      file.puts("------------------------------")
    end
    puts "Saved in weekly_reports/#{file_name}"
  else
    records_path = File.join(current_path, "records")
    Dir.mkdir(records_path) unless Dir.exist?(records_path)

    line = nil
    all_lines = []

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
  puts "Recorded in #{Date.today.strftime("%H:%M")}"
end

save_work_diary(ARGV[0])
