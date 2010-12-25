module DifferentOFS
  def setup
    super
    @ofs, $, = $,, "-"
  end
  def teardown
    $, = @ofs
    super
  end

  module WithDifferentOFS
    def with_diffrent_ofs
    end
  end
  def self.included(klass)
    super(klass)
    klass.const_set(:DifferentOFS, Class.new(klass).class_eval {include WithDifferentOFS}).name
  end
end
