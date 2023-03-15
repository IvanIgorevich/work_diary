if Gem.win_platform?
  Encoding.default_external = Encoding.find(Encoding.locale_charmap)
  Encoding.default_internal = __ENCODING__

  [STDIN, STDOUT].each do |io|
    io.set_encoding(Encoding.default_external, Encoding.default_internal)
  end
end

def save_work_diary
  puts Time.now
  puts "Work diary"
  puts "Save until row == \"end\", next row is 'Enter'"

  current_path = File.dirname(__FILE__)
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
  puts "Recorded in #{time_string}"
end

save_work_diary
