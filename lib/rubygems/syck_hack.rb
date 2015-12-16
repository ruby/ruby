# frozen_string_literal: false
# :stopdoc:

# Hack to handle syck's DefaultKey bug
#
# This file is always loaded AFTER either syck or psych are already
# loaded. It then looks at what constants are available and creates
# a consistent view on all rubys.
#
# All this is so that there is always a YAML::Syck::DefaultKey
# class no matter if the full yaml library has loaded or not.
#

module YAML # :nodoc:
  # In newer 1.9.2, there is a Syck toplevel constant instead of it
  # being underneath YAML. If so, reference it back under YAML as
  # well.
  if defined? ::Syck
    # for tests that change YAML::ENGINE
    # 1.8 does not support the second argument to const_defined?
    remove_const :Syck rescue nil

    Syck = ::Syck

  # JRuby's "Syck" is called "Yecht"
  elsif defined? YAML::Yecht
    Syck = YAML::Yecht

  # Otherwise, if there is no YAML::Syck, then we've got just psych
  # loaded, so lets define a stub for DefaultKey.
  elsif !defined? YAML::Syck
    module Syck
      class DefaultKey # :nodoc:
      end
    end
  end

  # Now that we've got something that is always here, define #to_s
  # so when code tries to use this, it at least just shows up like it
  # should.
  module Syck
    class DefaultKey
      remove_method :to_s rescue nil

      def to_s
        '='
      end
    end
  end

  SyntaxError = Error unless defined? SyntaxError
end

# Sometime in the 1.9 dev cycle, the Syck constant was moved from under YAML
# to be a toplevel constant. So gemspecs created under these versions of Syck
# will have references to Syck::DefaultKey.
#
# So we need to be sure that we reference Syck at the toplevel too so that
# we can always load these kind of gemspecs.
#
if !defined?(Syck)
  Syck = YAML::Syck
end

# Now that we've got Syck setup in all the right places, store
# a reference to the DefaultKey class inside Gem. We do this so that
# if later on YAML, etc are redefined, we've still got a consistent
# place to find the DefaultKey class for comparison.

module Gem
  # for tests that change YAML::ENGINE
  remove_const :SyckDefaultKey if const_defined? :SyckDefaultKey

  SyckDefaultKey = YAML::Syck::DefaultKey
end

# :startdoc:
