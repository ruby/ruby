class Servant
  def self.create
    new
  end

  def initialize
    STDERR.puts "Servant created."
    @task = []
  end

  def push(value)
    @task.push(value)
  end

  def pop
    @task.pop
  end
end
