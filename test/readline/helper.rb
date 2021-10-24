begin
  require "readline.so"
  ReadlineSo = Readline
rescue LoadError
end

def use_ext_readline # Use ext/readline as Readline
  Object.send(:remove_const, :Readline) if Object.const_defined?(:Readline)
  Object.const_set(:Readline, ReadlineSo)
end

begin
  require "reline"
rescue LoadError
  Object.class_eval {remove_const :Reline} if defined?(Reline)
else
  def use_lib_reline # Use lib/reline as Readline
    Reline.send(:remove_const, 'IOGate') if Reline.const_defined?('IOGate')
    Reline.const_set('IOGate', Reline::GeneralIO)
    Reline.send(:core).config.instance_variable_set(:@test_mode, true)
    Reline.send(:core).config.reset
    Object.send(:remove_const, :Readline) if Object.const_defined?(:Readline)
    Object.const_set(:Readline, Reline)
  end

  def finish_using_lib_reline
    Reline.instance_variable_set(:@core, nil)
  end
end
