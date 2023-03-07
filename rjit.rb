module RubyVM::RJIT
  # Return true if RJIT is enabled.
  def self.enabled?
    Primitive.cexpr! 'RBOOL(mjit_enabled)'
  end

  # Stop generating JITed code.
  def self.pause(wait: true)
    Primitive.cexpr! 'mjit_pause(RTEST(wait))'
  end

  # Start generating JITed code again after pause.
  def self.resume
    Primitive.cexpr! 'mjit_resume()'
  end

  if Primitive.mjit_stats_enabled_p
    at_exit do
      Primitive.mjit_stop_stats
      print_stats
    end
  end
end

if RubyVM::RJIT.enabled?
  begin
    require 'fiddle'
    require 'fiddle/import'
  rescue LoadError
    return # miniruby doesn't support RJIT
  end

  require 'ruby_vm/mjit/c_type'
  require 'ruby_vm/mjit/compiler'
  require 'ruby_vm/mjit/hooks'
  require 'ruby_vm/mjit/stats'
end
