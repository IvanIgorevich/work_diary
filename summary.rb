# frozen_string_literal: true

require 'date'
require 'active_support/all'

# Set encoding for Windows platform
if Gem.win_platform?
  Encoding.default_external = Encoding.find(Encoding.locale_charmap)
  Encoding.default_internal = __ENCODING__
  [STDIN, STDOUT].each { |io| io.set_encoding(Encoding.default_external, Encoding.default_internal) }
end

# Method to read a file and extract tasks and time
def parse_tasks(file_content)
  tasks = {}

  # Debug output
  puts "Parsing file content:\n#{file_content}"

  file_content.scan(/(\d{4}-\d{2}-\d{2}):\s*\n([\s\S]*?)\n-+/).each do |date, block|
    block.scan(/#(\d+),.*total (\d+h \d+m)/).each do |task_id, time|
      tasks[task_id] ||= []
      tasks[task_id] << time
    end
  end
  tasks
end

# Method to convert time like "2h 10m" to minutes
def time_to_minutes(time_str)
  hours, minutes = time_str.scan(/(\d+)h (\d+)m/).flatten.map(&:to_i)
  hours * 60 + minutes
end

# Method to get all files in a given date range
def files_in_range(start_date, end_date, directory = 'records')
  files = Dir.glob(File.join(directory, '*.txt')).select do |file|
    file_date = Date.parse(File.basename(file, '.txt'))
    (start_date..end_date).cover?(file_date)
  end

  # Debug output of found files
  puts "Found files for analysis: #{files.size}"
  files.each { |file| puts "Analyzing file: #{file}" }

  files
end

# Method to analyze all tasks in a date range
def analyze_tasks(start_date, end_date, directory = 'records')
  all_tasks = {}

  # Extend the end date by 5 days
  extended_end_date = end_date + 5.days

  # Search for files in the range
  puts "Analyzing files from #{start_date} to #{extended_end_date}"
  files_in_range(start_date, extended_end_date, directory).each do |file|
    file_content = File.read(file)
    tasks = parse_tasks(file_content)

    tasks.each do |task_id, times|
      latest_time = times.max_by { |time| time_to_minutes(time) }
      all_tasks[task_id] = latest_time
    end
  end

  all_tasks
end

# Method to sort tasks by time
def sort_tasks_by_time(tasks)
  tasks.sort_by { |_, time| -time_to_minutes(time) }
end

# Main method to create the report
def create_summary_report(start_date, end_date)
  puts "Creating report for the period from #{start_date} to #{end_date}"
  tasks = analyze_tasks(start_date, end_date)
  sorted_tasks = sort_tasks_by_time(tasks)

  # Create a file with the results
  report_file_name = "#{start_date}__#{end_date}.txt"
  File.open(report_file_name, 'w:UTF-8') do |file|
    if sorted_tasks.empty?
      file.puts "No tasks in the specified range."
    else
      sorted_tasks.each do |task_id, time|
        file.puts "Task ##{task_id}: #{time}"
      end
    end
  end

  puts "Report created: #{report_file_name}"
end

# Main code
begin
  if ARGV.length < 2
    puts "Please enter two dates in the format 'YYYY-MM-DD'"
    exit
  end

  start_date_str = ARGV[0]
  end_date_str = ARGV[1]
  start_date = Date.parse(start_date_str)
  end_date = Date.parse(end_date_str)

  puts "Checking entered dates: start #{start_date}, end #{end_date}"

  # Ensure the first date is less than or equal to the second
  if start_date > end_date
    puts "Error: start date #{start_date} is after end date #{end_date}. Please correct the order of arguments."
    exit
  end

  create_summary_report(start_date, end_date)

rescue ArgumentError => e
  puts "Date format error: #{e.message}"
end
