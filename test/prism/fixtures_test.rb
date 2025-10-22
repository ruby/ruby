# frozen_string_literal: true

return if RUBY_VERSION < "3.2.0"

require_relative "test_helper"

module Prism
  class FixturesTest < TestCase
    except = []

    if RUBY_VERSION < "3.3.0"
      # Ruby < 3.3.0 cannot parse heredocs where there are leading whitespace
      # characters in the heredoc start.
      # Example: <<~'   EOF' or <<-'  EOF'
      # https://bugs.ruby-lang.org/issues/19539
      except << "heredocs_leading_whitespace.txt"
      except << "whitequark/ruby_bug_19539.txt"

      # https://bugs.ruby-lang.org/issues/19025
      except << "whitequark/numparam_ruby_bug_19025.txt"
      # https://bugs.ruby-lang.org/issues/18878
      except << "whitequark/ruby_bug_18878.txt"
      # https://bugs.ruby-lang.org/issues/19281
      except << "whitequark/ruby_bug_19281.txt"
    end

    if RUBY_VERSION < "3.4.0"
      except << "3.4/circular_parameters.txt"
    end

    # Valid only on Ruby 3.3
    except << "3.3-3.3/block_args_in_array_assignment.txt"
    except << "3.3-3.3/it_with_ordinary_parameter.txt"
    except << "3.3-3.3/keyword_args_in_array_assignment.txt"
    except << "3.3-3.3/return_in_sclass.txt"

    # Leaving these out until they are supported by parse.y.
    except << "3.5/leading_logical.txt"
    except << "3.5/endless_methods_command_call.txt"
    # https://bugs.ruby-lang.org/issues/21168#note-5
    except << "command_method_call_2.txt"

    Fixture.each(except: except) do |fixture|
      define_method(fixture.test_name) { assert_valid_syntax(fixture.read) }
    end
  end
end
