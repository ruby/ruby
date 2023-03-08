module RubyVM::RJIT
  # Return true if RJIT is enabled.
  def self.enabled?
    Primitive.cexpr! 'RBOOL(rjit_enabled)'
  end

  # Stop generating JITed code.
  def self.pause
    # TODO: implement this
  end

  # Start generating JITed code again after pause.
  def self.resume
    # TODO: implement this
  end

  if Primitive.rjit_stats_enabled_p
    at_exit do
      Primitive.rjit_stop_stats
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

  require 'ruby_vm/rjit/c_type'
  require 'ruby_vm/rjit/compiler'
  require 'ruby_vm/rjit/hooks'
  require 'ruby_vm/rjit/stats'
end
