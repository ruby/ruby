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
  Reline.send(:remove_const, 'IOGate') if Reline.const_defined?('IOGate')
  Reline.const_set('IOGate', Reline::GeneralIO)
  Reline.send(:core).config.instance_variable_set(:@test_mode, true)
  Reline.send(:core).config.reset
  Object.send(:remove_const, :Readline) if Object.const_defined?(:Readline)
  Object.const_set(:Readline, Reline)
end
