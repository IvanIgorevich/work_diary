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

  puts "Enter date (YYYY-MM-DD):"
  date_input = STDIN.gets.chomp
  # Validate date format
  begin
    date = Date.parse(date_input)
  rescue ArgumentError
    puts "Invalid date format. Please use YYYY-MM-DD."
    return
  end

  date_line = "#{date.strftime("%Y-%m-%d")}:"

  time = Time.now
  file_name = time.strftime("%Y-%m-%d")
  time_string = time.strftime("%H:%M")
  separator = "------------------------------"

  file_path = File.join(records_path, "#{file_name}.txt")
  File.open(file_path, "a:UTF-8") do |file|
    file.puts("\n\r#{time_string}\n\r")
    file.puts(date_line)

    task_number = nil
    task_count = 1

    while true
      puts "#{ordinal(task_count)} task:"
      task_input = STDIN.gets.chomp
      break if task_input.downcase == "end"

      # Parse the task input
      # Expecting format: "task_number hh:mm"
      task_match = task_input.match(/^(\d+)\s+(\d{1,2}):(\d{2})$/)
      if task_match
        task_number = task_match[1]
        hours_input = task_match[2].to_i
        minutes_input = task_match[3].to_i

        # Format task time according to the rules
        task_time = format_time(hours_input, minutes_input)

        # Convert current task time to minutes
        task_minutes = hours_input * 60 + minutes_input

        # Search for previous total time
        previous_total_minutes = find_previous_total_time(task_number)

        if previous_total_minutes.nil?
          # First time ever, write 'start'
          file.puts("#{task_count}) ##{task_number}, this day #{task_time}, start")
        else
          # Accumulate total time
          total_minutes = previous_total_minutes + task_minutes
          new_total_time = format_time(total_minutes / 60, total_minutes % 60)

          file.puts("#{task_count}) ##{task_number}, this day #{task_time}, total #{new_total_time}")
        end

        task_count += 1
      else
        puts "Invalid input format. Please enter task number and time in format '1234 hh:mm'"
      end
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

# Helper method to convert ordinal numbers
def ordinal(number)
  suffixes = [
    "First",
    "Second",
    "Third",
    "Fourth",
    "Fifth",
    "Sixth",
    "Seventh",
    "Eighth",
    "Ninth",
    "Tenth"
  ]

  suffixes[number - 1] || "#{number}th"
end

# Helper method to find previous total time in minutes for a task
def find_previous_total_time(task_number)
  # Get the date six months ago
  start_date = Date.today - 180
  end_date = Date.today

  # Get all the files in the date range
  base_dir = File.dirname(__FILE__)
  candidate_dirs = [
    File.join(base_dir, "records"),
    File.join(base_dir, "spec", "records")
  ]

  files = candidate_dirs.select { |d| Dir.exist?(d) }.flat_map do |dir|
    Dir.glob(File.join(dir, "*.txt"))
  end

  files.select! do |file|
    file_date = begin
      Date.parse(File.basename(file, ".txt"))
    rescue ArgumentError
      nil
    end

    file_date && (start_date..end_date).cover?(file_date)
  end

  # Sort files by date
  files.sort_by! { |file| File.basename(file, ".txt") }

  previous_total_minutes = nil

  files.each do |file|
    file_content = File.read(file)

    # Find all task entries
    pattern = %r{
      # task number
      \#(\d+),
      .*this\ day\s+
      # this day time: '5h 30m' | '30m' | '5h'
      ((?:\d+h)?\s?\d+m|\d+h),
      .*
      # either 'total <time>' or 'start'
      (?:
        total\s+((?:\d+h)?\s?\d+m|\d+h)
        |
        (start)
      )
    }x

    file_content.scan(pattern).each do |
      found_task_number, this_day_time, total_time, start_marker
    |
      next unless found_task_number == task_number

      if start_marker == "start"
        # If 'start' is found and no previous total, set total to this day's time
        previous_total_minutes ||= 0
      elsif total_time
        # Update previous_total_minutes with the latest total time
        previous_total_minutes = time_to_minutes(total_time)
      else
        # If no total time but 'this day' time exists, add it to previous_total_minutes
        previous_total_minutes ||= 0
        previous_total_minutes += time_to_minutes(this_day_time)
      end
    end
  end

  previous_total_minutes
end

# Helper method to convert time string to minutes
def time_to_minutes(time_str)
  return 0 if time_str == "start"

  hours = 0
  minutes = 0

  if time_str =~ /(\d+)h/
    hours = $1.to_i
  end

  if time_str =~ /(\d+)m/
    minutes = $1.to_i
  end

  hours * 60 + minutes
end

# Helper method to format time according to the rules
def format_time(hours, minutes)
  parts = []
  parts << "#{hours}h" if hours > 0
  parts << "#{minutes}m" if minutes > 0
  parts << "0m" if hours == 0 && minutes == 0
  parts.join(" ")
end

# Call the save_work_diary method with the command line argument
save_work_diary(ARGV[0]) if __FILE__ == $0
