# frozen_string_literal: true

require_relative "helper"
require "rubygems/commands/stale_command"

class TestGemCommandsStaleCommand < Gem::TestCase
  def setup
    super
    @stub_ui = Gem::MockGemUi.new
    @cmd = Gem::Commands::StaleCommand.new
  end

  def test_execute_sorts
    files = %w[lib/foo_bar.rb Rakefile]
    foo_bar = util_spec "foo_bar" do |gem|
      gem.files = files
    end
    install_specs foo_bar

    bar_baz = util_spec "bar_baz" do |gem|
      gem.files = files
    end
    install_specs bar_baz

    files.each do |file|
      filename = File.join(bar_baz.full_gem_path, file)
      FileUtils.mkdir_p File.dirname filename
      FileUtils.touch(filename, :mtime => Time.now)

      filename = File.join(foo_bar.full_gem_path, file)
      FileUtils.mkdir_p File.dirname filename
      FileUtils.touch(filename, :mtime => Time.now - 86_400)
    end

    use_ui @stub_ui do
      @cmd.execute
    end

    lines = @stub_ui.output.split("\n")
    assert_equal("#{foo_bar.name}-#{foo_bar.version}", lines[0].split.first)
    assert_equal("#{bar_baz.name}-#{bar_baz.version}", lines[1].split.first)
  end
end
