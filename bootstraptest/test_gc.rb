assert_normal_exit %q{
a = []
ms = "a".."k"
("A".."Z").each do |mod|
  mod = eval("module #{mod}; self; end")
  ms.each do |meth|
    iseq = RubyVM::InstructionSequence.compile("module #{mod}; def #{meth}; end; end")
    GC.stress = true
    iseq.eval
    GC.stress = false
  end
  o = Object.new.extend(mod)
  ms.each do |meth|
    o.send(meth)
  end
end
}, '[ruby-dev:39453]'

assert_normal_exit %q{
a = []
ms = "a".."k"
("A".."Z").each do |mod|
  mod = eval("module #{mod}; self; end")
  ms.each do |meth|
    GC.stress = true
    mod.module_eval {define_method(meth) {}}
    GC.stress = false
  end
  o = Object.new.extend(mod)
  ms.each do |meth|
    o.send(meth)
  end
end
}, '[ruby-dev:39453]'

assert_normal_exit %q{
  # A class whose instances start with a complex shape: as.extended must be
  # initialized before the fields object allocation can trigger a GC.
  ivars = 1024.times.map { |i| "@iv_#{i} = #{i}\n" }.join
  klass = Class.new
  klass.class_eval "def initialize() #{ivars} end"
  GC.stress = true
  klass.allocate
  GC.stress = false
}, 'complex T_OBJECT marked before as.extended is set'
