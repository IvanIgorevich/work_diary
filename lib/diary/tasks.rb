module Diary
  # data/tasks.yml — подзадачи и задача, которую указываю в отчётах вместо них.
  class Tasks
    def initialize(path)
      data = File.exist?(path) ? YAML.load_file(path) || {} : {}
      @parents = data.fetch("parents", nil).to_h.to_h { |task, parent| [task.to_s, parent.to_s] }
    end

    def report_task(number) = @parents.fetch(number.to_s, number.to_s)
  end
end
