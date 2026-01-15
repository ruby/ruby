# frozen_string_literal: true

require_relative "helper"
require "rubygems/user_interaction"

class TestGemConsoleUI < Gem::TestCase
  def test_output_can_be_captured_by_test_unit
    output = capture_output do
      ui = Gem::ConsoleUI.new

      ui.alert_error "test error"
      ui.alert_warning "test warning"
      ui.alert "test alert"
    end

    assert_equal "INFO:  test alert\n", output.first
    assert_equal "ERROR:  test error\n" + "WARNING:  test warning\n", output.last
  end
end
