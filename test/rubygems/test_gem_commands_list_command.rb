# frozen_string_literal: true

require_relative "helper"
require "rubygems/commands/list_command"

class TestGemCommandsListCommand < Gem::TestCase
  def setup
    super

    @cmd = Gem::Commands::ListCommand.new
  end

  def test_execute_installed
    spec_fetcher do |fetcher|
      fetcher.spec "c", 1
    end

    @fetcher.data["#{@gem_repo}Marshal.#{Gem.marshal_version}"] = proc do
      raise Gem::RemoteFetcher::FetchError
    end

    @cmd.handle_options %w[c --installed]

    assert_raise Gem::MockGemUi::SystemExitException do
      use_ui @ui do
        @cmd.execute
      end
    end

    assert_equal "true\n", @ui.output
    assert_equal "", @ui.error
  end

  def test_execute_normal_gem_shadowing_default_gem
    c1_default = new_default_spec "c", 1
    install_default_gems c1_default

    c1 = util_spec("c", 1) {|s| s.date = "2024-01-01" }
    install_gem c1

    Gem::Specification.reset

    @cmd.handle_options %w[c]

    use_ui @ui do
      @cmd.execute
    end

    expected = <<-EOF

*** LOCAL GEMS ***

c (1)
EOF

    assert_equal expected, @ui.output
  end
end
