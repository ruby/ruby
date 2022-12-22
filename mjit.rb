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

  RubyVM::MJIT::C = Object.new # forward declaration for ruby_vm/mjit/compiler
  require 'ruby_vm/mjit/c_type'
  require 'ruby_vm/mjit/instruction'
  require 'ruby_vm/mjit/compiler'

  module RubyVM::MJIT
    private_constant(*constants)
  end
end
