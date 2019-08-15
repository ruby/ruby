begin
  require "readline.so"
  ReadlineSo = Readline
rescue LoadError
end
require "reline"

def use_ext_readline # Use ext/readline as Readline
  Object.send(:remove_const, :Readline) if Object.const_defined?(:Readline)
  Object.const_set(:Readline, ReadlineSo)
end

def use_lib_reline # Use lib/reline as Readline
  Reline.send(:test_mode)
  Object.send(:remove_const, :Readline) if Object.const_defined?(:Readline)
  Object.const_set(:Readline, Reline)
end
