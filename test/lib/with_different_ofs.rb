# frozen_string_literal: true
module DifferentOFS
  module WithDifferentOFS
    def setup
      super
      verbose, $VERBOSE = $VERBOSE, nil
      @ofs, $, = $,, "-"
      $VERBOSE = verbose
    end
    def teardown
      verbose, $VERBOSE = $VERBOSE, nil
      $, = @ofs
      $VERBOSE = verbose
      super
    end
  end

  def self.extended(klass)
    super(klass)
    klass.const_set(:DifferentOFS, Class.new(klass).class_eval {include WithDifferentOFS}).name
  end
end
