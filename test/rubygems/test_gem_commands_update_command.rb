######################################################################
# This file is imported from the rubygems project.
# DO NOT make modifications in this repo. They _will_ be reverted!
# File a patch instead and assign it to Ryan Davis or Eric Hodel.
######################################################################

require "test/rubygems/gemutilities"
require 'rubygems/commands/update_command'

class TestGemCommandsUpdateCommand < RubyGemTestCase

  def setup
    super

    @cmd = Gem::Commands::UpdateCommand.new

    @cmd.options[:generate_rdoc] = false
    @cmd.options[:generate_ri]   = false

    util_setup_fake_fetcher

    @a1_path = File.join @gemhome, 'cache', @a1.file_name
    @a2_path = File.join @gemhome, 'cache', @a2.file_name

    util_setup_spec_fetcher @a1, @a2

    @fetcher.data["#{@gem_repo}gems/#{@a1.file_name}"] =
      read_binary @a1_path
    @fetcher.data["#{@gem_repo}gems/#{@a2.file_name}"] =
      read_binary @a2_path
  end

  def test_execute
    util_clear_gems

    Gem::Installer.new(@a1_path).install

    @cmd.options[:args] = []
    @cmd.options[:generate_rdoc] = true
    @cmd.options[:generate_ri]   = true

    use_ui @ui do
      @cmd.execute
    end

    out = @ui.output.split "\n"
    assert_equal "Updating installed gems", out.shift
    assert_equal "Updating #{@a2.name}", out.shift
    assert_equal "Successfully installed #{@a2.full_name}", out.shift
    assert_equal "Gems updated: #{@a2.name}", out.shift
    assert_equal "Installing ri documentation for a-2...", out.shift
    assert_equal "Installing RDoc documentation for a-2...", out.shift

    assert_empty out
  end

  # before:
  #   a1 -> c1.2
  # after:
  #   a2 -> b2 # new dependency
  #   a2 -> c2

  def test_execute_dependencies
    @a1.add_dependency 'c', '1.2'

    @c2 = quick_gem 'c', '2' do |s|
      s.files = %w[lib/code.rb]
      s.require_paths = %w[lib]
    end

    @a2.add_dependency 'c', '2'
    @a2.add_dependency 'b', '2'

    @b2_path = File.join @gemhome, 'cache', @b2.file_name
    @c1_2_path = File.join @gemhome, 'cache', @c1_2.file_name
    @c2_path = File.join @gemhome, 'cache', @c2.file_name

    @source_index = Gem::SourceIndex.new
    @source_index.add_spec @a1
    @source_index.add_spec @a2
    @source_index.add_spec @b2
    @source_index.add_spec @c1_2
    @source_index.add_spec @c2

    util_build_gem @a1
    util_build_gem @a2
    util_build_gem @c2

    @fetcher.data["#{@gem_repo}gems/#{@a1.file_name}"] = read_binary @a1_path
    @fetcher.data["#{@gem_repo}gems/#{@a2.file_name}"] = read_binary @a2_path
    @fetcher.data["#{@gem_repo}gems/#{@b2.file_name}"] = read_binary @b2_path
    @fetcher.data["#{@gem_repo}gems/#{@c1_2.file_name}"] =
      read_binary @c1_2_path
    @fetcher.data["#{@gem_repo}gems/#{@c2.file_name}"] = read_binary @c2_path

    util_setup_spec_fetcher @a1, @a2, @b2, @c1_2, @c2
    util_clear_gems

    Gem::Installer.new(@c1_2_path).install
    Gem::Installer.new(@a1_path).install

    @cmd.options[:args] = []

    use_ui @ui do
      @cmd.execute
    end

    out = @ui.output.split "\n"
    assert_equal "Updating installed gems", out.shift
    assert_equal "Updating #{@a2.name}", out.shift
    assert_equal "Successfully installed #{@c2.full_name}", out.shift
    assert_equal "Successfully installed #{@b2.full_name}", out.shift
    assert_equal "Successfully installed #{@a2.full_name}", out.shift
    assert_equal "Gems updated: #{@c2.name}, #{@b2.name}, #{@a2.name}",
                 out.shift

    assert_empty out
  end

  def test_execute_named
    util_clear_gems

    Gem::Installer.new(@a1_path).install

    @cmd.options[:args] = [@a1.name]

    use_ui @ui do
      @cmd.execute
    end

    out = @ui.output.split "\n"
    assert_equal "Updating installed gems", out.shift
    assert_equal "Updating #{@a2.name}", out.shift
    assert_equal "Successfully installed #{@a2.full_name}", out.shift
    assert_equal "Gems updated: #{@a2.name}", out.shift

    assert_empty out
  end

  def test_execute_named_up_to_date
    util_clear_gems

    Gem::Installer.new(@a2_path).install

    @cmd.options[:args] = [@a2.name]

    use_ui @ui do
      @cmd.execute
    end

    out = @ui.output.split "\n"
    assert_equal "Updating installed gems", out.shift
    assert_equal "Nothing to update", out.shift

    assert_empty out
  end

  def test_execute_up_to_date
    util_clear_gems

    Gem::Installer.new(@a2_path).install

    @cmd.options[:args] = []

    use_ui @ui do
      @cmd.execute
    end

    out = @ui.output.split "\n"
    assert_equal "Updating installed gems", out.shift
    assert_equal "Nothing to update", out.shift

    assert_empty out
  end
end
