############################################################
# This file is imported from a different project.
# DO NOT make modifications in this repo.
# File a patch instead and assign it to Ryan Davis
############################################################

require 'mini/test'

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
  module Assertions
    def assert_nothing_raised(*exp)
      msg = (Module === exp.last) ? "" : exp.pop
      noexc = exp.select {|e| not (Module === e and Exception >= e)}
      unless noexc.empty?
        noexc = *noexc if noexc.size == 1
        raise TypeError, "Should expect a class of exception, #{noexc.inspect}"
      end
      self._assertions += 1
      begin
        yield
      rescue Exception => e
        exp.include?(e.class) or raise
        raise(Mini::Assertion, exception_details(e, "#{msg}#{msg.empty? ? '' : ' '}Exception raised:"))
      end
    end

    def build_message(user_message, template_message, *args)
      user_message ||= ''
      user_message += ' ' unless user_message.empty?
      msg = template_message.split(/<\?>/).zip(args.map { |o| o.inspect })
      user_message + msg.join
    end

    alias assert_nothing_thrown assert_nothing_raised
    alias assert_raise          assert_raises
    alias assert_not_equal      refute_equal
    alias assert_no_match       refute_match
    alias assert_not_nil        refute_nil
    alias assert_not_same       refute_same

    private
    def _wrap_assertion
      yield
    end
  end
end
