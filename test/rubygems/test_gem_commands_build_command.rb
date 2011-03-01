######################################################################
# This file is imported from the rubygems project.
# DO NOT make modifications in this repo. They _will_ be reverted!
# File a patch instead and assign it to Ryan Davis or Eric Hodel.
######################################################################

require 'rubygems/test_case'
require 'rubygems/commands/build_command'
require 'rubygems/format'

class TestGemCommandsBuildCommand < Gem::TestCase

  def setup
    super

    @gem = quick_spec 'some_gem' do |s|
      s.rubyforge_project = 'example'
    end

    @cmd = Gem::Commands::BuildCommand.new
  end

  def test_execute
    gemspec_file = File.join(@tempdir, @gem.spec_name)

    File.open gemspec_file, 'w' do |gs|
      gs.write @gem.to_ruby
    end

    util_test_build_gem @gem, gemspec_file
  end

  def test_execute_yaml
    gemspec_file = File.join(@tempdir, @gem.spec_name)

    File.open gemspec_file, 'w' do |gs|
      gs.write @gem.to_yaml
    end

    util_test_build_gem @gem, gemspec_file
  end

  def test_execute_bad_gem
    @cmd.options[:args] = %w[some_gem]
    use_ui @ui do
      @cmd.execute
    end

    assert_equal '', @ui.output
    assert_equal "ERROR:  Gemspec file not found: some_gem\n", @ui.error
  end

  def util_test_build_gem(gem, gemspec_file)
    @cmd.options[:args] = [gemspec_file]

    use_ui @ui do
      Dir.chdir @tempdir do
        @cmd.execute
      end
    end

    output = @ui.output.split "\n"
    assert_equal "  Successfully built RubyGem", output.shift
    assert_equal "  Name: some_gem", output.shift
    assert_equal "  Version: 2", output.shift
    assert_equal "  File: some_gem-2.gem", output.shift
    assert_equal [], output
    assert_equal '', @ui.error

    gem_file = File.join @tempdir, gem.file_name
    assert File.exist?(gem_file)

    spec = Gem::Format.from_file_by_path(gem_file).spec

    assert_equal "some_gem", spec.name
    assert_equal "this is a summary", spec.summary
  end

end

