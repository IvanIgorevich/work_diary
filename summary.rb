# frozen_string_literal: true

require 'date'
require 'active_support/all'

# Проверка платформы для кодировки
if Gem.win_platform?
  Encoding.default_external = Encoding.find(Encoding.locale_charmap)
  Encoding.default_internal = __ENCODING__
  [STDIN, STDOUT].each { |io| io.set_encoding(Encoding.default_external, Encoding.default_internal) }
end

# Метод для чтения файла и извлечения задач и времени
def parse_tasks(file_content)
  tasks = {}

  # Добавим вывод отладочной информации
  puts "Парсинг содержимого файла:\n#{file_content}"

  file_content.scan(/(\d{4}-\d{2}-\d{2}):\s*\n([\s\S]*?)\n-+/).each do |date, block|
    block.scan(/#(\d+),.*total (\d+h \d+m)/).each do |task_id, time|
      tasks[task_id] ||= []
      tasks[task_id] << time
    end
  end
  tasks
end

# Метод для преобразования времени вида "2h 10m" в минуты
def time_to_minutes(time_str)
  hours, minutes = time_str.scan(/(\d+)h (\d+)m/).flatten.map(&:to_i)
  hours * 60 + minutes
end

# Метод для получения всех файлов в заданном диапазоне
def files_in_range(start_date, end_date, directory = 'records')
  files = Dir.glob(File.join(directory, '*.txt')).select do |file|
    file_date = Date.parse(File.basename(file, '.txt'))
    (start_date..end_date).cover?(file_date)
  end

  # Добавляем вывод найденных файлов для отладки
  puts "Найдено файлов для анализа: #{files.size}"
  files.each { |file| puts "Анализируем файл: #{file}" }

  files
end

# Метод для анализа всех задач в диапазоне дат
def analyze_tasks(start_date, end_date, directory = 'records')
  all_tasks = {}

  # Расширяем конечную дату на 5 дней
  extended_end_date = end_date + 5.days

  # Ищем файлы в диапазоне
  puts "Анализируем файлы с #{start_date} по #{extended_end_date}"
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

# Метод для сортировки задач по времени
def sort_tasks_by_time(tasks)
  tasks.sort_by { |_, time| -time_to_minutes(time) }
end

# Основной метод для создания отчета
def create_summary_report(start_date, end_date)
  puts "Создаем отчет за период с #{start_date} по #{end_date}"
  tasks = analyze_tasks(start_date, end_date)
  sorted_tasks = sort_tasks_by_time(tasks)

  # Создаем файл с результатами
  report_file_name = "#{start_date}__#{end_date}.txt"
  File.open(report_file_name, 'w:UTF-8') do |file|
    if sorted_tasks.empty?
      file.puts "Нет задач в указанном диапазоне."
    else
      sorted_tasks.each do |task_id, time|
        file.puts "Task ##{task_id}: #{time}"
      end
    end
  end

  puts "Отчет создан: #{report_file_name}"
end

# Основной код
begin
  if ARGV.length < 2
    puts "Введите две даты в формате 'DD MM YYYY'"
    exit
  end

  start_date_str = ARGV[0]
  end_date_str = ARGV[1]
  start_date = Date.parse(start_date_str)
  end_date = Date.parse(end_date_str)

  puts "Проверка введенных дат: начало #{start_date}, конец #{end_date}"

  # Проверяем, что первая дата должна быть меньше или равна второй
  if start_date > end_date
    puts "Ошибка: дата начала #{start_date} больше даты окончания #{end_date}. Исправьте порядок аргументов."
    exit
  end

  create_summary_report(start_date, end_date)

rescue ArgumentError => e
  puts "Ошибка в формате даты: #{e.message}"
end
