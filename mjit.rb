module RubyVM::MJIT
  # Return true if MJIT is enabled.
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
end

if RubyVM::MJIT.enabled?
  begin
    require 'fiddle'
    require 'fiddle/import'
  rescue LoadError
    return # miniruby doesn't support MJIT
  end

  # forward declaration for ruby_vm/mjit/compiler
  RubyVM::MJIT::C = Object.new # :nodoc:

  require 'ruby_vm/mjit/c_type'
  require 'ruby_vm/mjit/instruction'
  require 'ruby_vm/mjit/compiler'
  require 'ruby_vm/mjit/hooks'

  module RubyVM::MJIT
    private_constant(*constants)
  end
end
