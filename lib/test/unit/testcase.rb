############################################################
# This file is imported from a different project.
# DO NOT make modifications in this repo.
# File a patch instead and assign it to Ryan Davis
############################################################

require 'mini/test'
require 'test/unit/deprecate'

warn "require 'test/unit/testcase' has been deprecated" unless
  caller.first =~ /test.unit.rb/

module Test; end
module Test::Unit # was ::Mini::Test, but rails' horrid code forced my hand
  if defined? TestCase then
    warn "ARGH! someone defined Test::Unit::TestCase rather than requiring"
    remove_const :TestCase
  end

  AssertionFailedError = ::Mini::Assertion

  class TestCase < ::Mini::Test::TestCase
    tu_deprecate :method_name, :name # 2009-06-01

    def self.test_order              # 2009-06-01
      :sorted
    end
  end
end

require 'test/unit/assertions' # brings in deprecated methods
