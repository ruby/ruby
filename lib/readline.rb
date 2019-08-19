begin
  require 'readline.so'
rescue LoadError
  require 'reline'
  Readline = Reline
end
