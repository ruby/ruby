# frozen_string_literal: false
# fallback to console window size
def IO.default_console_size
  lines = ENV["LINES"].to_i
  columns = ENV["COLUMNS"].to_i
  [
    lines.positive? ? lines : 25,
    columns.positive? ? columns : 80,
  ]
end

begin
  require 'io/console'
rescue LoadError
  class << IO
    alias console_size default_console_size
  end
else
  # returns console window size
  def IO.console_size
    console.winsize
  rescue NoMethodError
    default_console_size
  end
end
