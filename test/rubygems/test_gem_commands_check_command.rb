# frozen_string_literal: true
require 'rubygems/test_case'
require 'rubygems/commands/check_command'

class TestGemCommandsCheckCommand < Gem::TestCase
  def setup
    super

    @cmd = Gem::Commands::CheckCommand.new
  end

  def gem(name)
    spec = quick_gem name do |gem|
      gem.files = %W[lib/#{name}.rb Rakefile]
    end

    write_file File.join(*%W[gems #{spec.full_name} lib #{name}.rb])
    write_file File.join(*%W[gems #{spec.full_name} Rakefile])

    spec
  end

  def test_initialize
    assert_equal "check", @cmd.command
    assert_equal "gem check", @cmd.program_name
    assert_match(/Check/, @cmd.summary)
  end

  def test_handle_options
    @cmd.handle_options %w[--no-alien --no-gems --doctor --dry-run]

    assert @cmd.options[:doctor]
    refute @cmd.options[:alien]
    assert @cmd.options[:dry_run]
    refute @cmd.options[:gems]
  end

  def test_handle_options_defaults
    @cmd.handle_options []

    assert @cmd.options[:alien]
    assert @cmd.options[:gems]
    refute @cmd.options[:doctor]
    refute @cmd.options[:dry_run]
  end

  def test_doctor
    gem 'a'
    b = gem 'b'

    FileUtils.rm b.spec_file

    assert_path_exists b.gem_dir
    refute_path_exists b.spec_file

    Gem.use_paths @gemhome

    capture_io do
      use_ui @ui do
        @cmd.doctor
      end
    end

    refute_path_exists b.gem_dir
    refute_path_exists b.spec_file
  end
end
