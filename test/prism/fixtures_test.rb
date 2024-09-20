# frozen_string_literal: true

return if RUBY_VERSION < "3.2.0"

require_relative "test_helper"

module Prism
  class FixturesTest < TestCase
    except = []

    # Ruby < 3.3.0 cannot parse heredocs where there are leading whitespace
    # characters in the heredoc start.
    # Example: <<~'   EOF' or <<-'  EOF'
    # https://bugs.ruby-lang.org/issues/19539
    except << "heredocs_leading_whitespace.txt" if RUBY_VERSION < "3.3.0"

    Fixture.each(except: except) do |fixture|
      define_method(fixture.test_name) { assert_valid_syntax(fixture.read) }
    end
  end
end
