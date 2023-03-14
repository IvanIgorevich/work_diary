if (Gem.win_platform?)
  Encoding.default_external = Encoding.find(Encoding.locale_charmap)
  Encoding.default_internal = __ENCODING__

  [STDIN, STDOUT].each do |io|
    io.set_encoding(Encoding.default_external, Encoding.default_internal)
  end
end

puts Time.now
puts "Work diary"
puts "Save until row == \"end\", next row is '\n'"

current_path = File.dirname(__FILE__)

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

file = File.new(current_path + "/" + file_name + ".txt", "a:UTF-8")
file.print("\n\r" + time_string + "\n\r")

all_lines.each do |item|
  file.puts(item)
end

file.puts(separator)
file.close

puts "Saved in #{file_name}.txt"
puts "Recorded in #{time_string}"
