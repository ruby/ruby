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
      FileUtils.touch(filename, mtime: Time.now)

      filename = File.join(foo_bar.full_gem_path, file)
      FileUtils.mkdir_p File.dirname filename
      FileUtils.touch(filename, mtime: Time.now - 86_400)
    end

    use_ui @stub_ui do
      @cmd.execute
    end

    lines = @stub_ui.output.split("\n")
    assert_equal("#{foo_bar.name}-#{foo_bar.version}", lines[0].split.first)
    assert_equal("#{bar_baz.name}-#{bar_baz.version}", lines[1].split.first)
  end

  def test_execute_with_glob_metacharacters_in_gem_path
    gemhome2 = File.join(@tempdir, "gemhome[2]")
    Gem.use_paths gemhome2

    foo = util_spec "foo" do |gem|
      gem.files = %w[lib/foo.rb]
    end
    install_specs foo

    filename = File.join(gemhome2, "gems", foo.full_name, "lib", "foo.rb")
    FileUtils.mkdir_p File.dirname filename
    FileUtils.touch filename

    use_ui @stub_ui do
      @cmd.execute
    end

    listed_gems = @stub_ui.output.split("\n").map {|line| line.split.first }
    assert_includes listed_gems, "#{foo.name}-#{foo.version}"
  end
end
