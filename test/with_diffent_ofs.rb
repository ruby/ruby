module DifferentOFS
  def setup
    super
    @ofs, $, = $,, "-"
  end
  def teardown
    $, = @ofs
    super
  end

  mod = Module.new do
    def with_diffrent_ofs
      const_set(:DifferentOFS, Class.new(self).class_eval {include DifferentOFS}).name
    end
  end
  class << self; self; end.class_eval do
    define_method(:included) do |klass|
      super(klass)
      klass.extend(mod)
    end
  end
end
