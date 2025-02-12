module RubyVM::RJIT
  # Return true if \RJIT is enabled.
  def self.enabled?
    Primitive.cexpr! 'RBOOL(rb_rjit_enabled)'
  end

  # Start JIT compilation after \--rjit-disable.
  def self.enable
    Primitive.cstmt! %{
      rb_rjit_call_p = true;
      return Qnil;
    }
  end

  if Primitive.rjit_stats_enabled_p
    at_exit do
      Primitive.rjit_stop_stats
      print_stats
    end
  end
  if Primitive.rjit_trace_exits_enabled_p
    at_exit do
      Primitive.rjit_stop_stats
      dump_trace_exits
    end
  end
end

if RubyVM::RJIT.enabled?
  fiddle_paths = nil
  begin
    require 'fiddle'
    require 'fiddle/import'
  rescue LoadError
    return if fiddle_paths
    # Find fiddle from artifacts of bundled gems for make test-all
    fiddle_paths = %W[#{__dir__}/.bundle/gems/fiddle-*/lib .bundle/extensions/*/*/fiddle-*].map do |dir|
      Dir.glob(dir).first
    end.compact
    if fiddle_paths.empty?
      return # miniruby doesn't support RJIT
    else
      $LOAD_PATH.unshift(*fiddle_paths)
      retry
    end
  end

  require 'ruby_vm/rjit/c_type'
  require 'ruby_vm/rjit/compiler'
  require 'ruby_vm/rjit/hooks'
  require 'ruby_vm/rjit/stats'
end
