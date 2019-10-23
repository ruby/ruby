begin
  require 'readline.so'
rescue LoadError
  require 'reline' unless defined? Reline
  Readline = Reline
end
