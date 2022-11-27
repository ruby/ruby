module RubyVM::MJIT
  def self.enabled?
    Primitive.cexpr! 'RBOOL(mjit_enabled)'
  end

  def self.pause(wait: true)
    Primitive.cexpr! 'mjit_pause(RTEST(wait))'
  end

  def self.resume
    Primitive.cexpr! 'mjit_resume()'
  end
end

if RubyVM::MJIT.enabled?
  begin
    require 'fiddle'
    require 'fiddle/import'
  rescue LoadError
    return # miniruby doesn't support MJIT
  end

  require "mjit/c_type"
  require "mjit/instruction"
  require "mjit/compiler"

  module RubyVM::MJIT
    private_constant *constants
  end
end
