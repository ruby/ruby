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
