############################################################
# This file is imported from a different project.
# DO NOT make modifications in this repo.
# File a patch instead and assign it to Ryan Davis
############################################################

require 'mini/test'
require 'test/unit/deprecate'

module Test; end
module Test::Unit # patch up bastards that that extend improperly.
  if defined? Assertions then
    warn "ARGH! someone defined Test::Unit::Assertions rather than requiring"
    CRAP_ASSERTIONS = Assertions
    remove_const :Assertions

    # this will break on junit and rubinius... *sigh*
    ObjectSpace.each_object(Module) do |offender|
      offender.send :include, ::Mini::Assertions if offender < CRAP_ASSERTIONS
    end rescue nil

    Test::Unit::TestCase.send :include, CRAP_ASSERTIONS
  end

  Assertions = ::Mini::Assertions

  module Assertions
    def self.included mod
      mod.send :include, Test::Unit::CRAP_ASSERTIONS
    end if defined? Test::Unit::CRAP_ASSERTIONS
  end
end

module Test::Unit
  module Assertions # deprecations
    tu_deprecate :assert_nothing_thrown, :assert_nothing_raised # 2009-06-01
    tu_deprecate :assert_raises,         :assert_raise          # 2010-06-01
    tu_deprecate :assert_not_equal,      :refute_equal          # 2009-06-01
    tu_deprecate :assert_no_match,       :refute_match          # 2009-06-01
    tu_deprecate :assert_not_nil,        :refute_nil            # 2009-06-01
    tu_deprecate :assert_not_same,       :refute_same           # 2009-06-01

    def assert_nothing_raised _ = :ignored                      # 2009-06-01
      self.class.tu_deprecation_warning :assert_nothing_raised
      self._assertions += 1
      yield
    rescue => e
      raise Mini::Assertion, exception_details(e, "Exception raised:")
    end

    def build_message(user_message, template_message, *args)    # 2009-06-01
      self.class.tu_deprecation_warning :build_message
      user_message ||= ''
      user_message += ' ' unless user_message.empty?
      msg = template_message.split(/<\?>/).zip(args.map { |o| o.inspect })
      user_message + msg.join
    end
  end
end
