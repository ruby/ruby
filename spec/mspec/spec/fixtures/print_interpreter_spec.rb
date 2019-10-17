unless defined?(RSpec)
  puts ENV["RUBY_EXE"]
  puts ruby_cmd(nil).split.first
end
