# frozen_string_literal: true

require_relative "helper"
require "rubygems/commands/info_command"

class TestGemCommandsInfoCommand < Gem::TestCase
  def setup
    super

    @cmd = Gem::Commands::InfoCommand.new
  end

  def gem(name, version = "1.0")
    spec = quick_gem name do |gem|
      gem.summary = "test gem"
      gem.homepage = "https://github.com/rubygems/rubygems"
      gem.files = %W[lib/#{name}.rb Rakefile]
      gem.authors = ["Colby", "Jack"]
      gem.license = "MIT"
      gem.version = version
    end
    write_file File.join(*%W[gems #{spec.full_name} lib #{name}.rb])
    write_file File.join(*%W[gems #{spec.full_name} Rakefile])
    spec
  end

  def test_execute
    @gem = gem "foo", "1.0.0"

    @cmd.handle_options %w[foo]

    use_ui @ui do
      @cmd.execute
    end

    assert_include(@ui.output, "#{@gem.name} (#{@gem.version})\n")
    assert_include(@ui.output, "Authors: #{@gem.authors.join(", ")}\n")
    assert_include(@ui.output, "Homepage: #{@gem.homepage}\n")
    assert_include(@ui.output, "License: #{@gem.license}\n")
    assert_include(@ui.output, "Installed at: #{@gem.base_dir}\n")
    assert_include(@ui.output, "#{@gem.summary}\n")
    assert_match "", @ui.error
  end

  def test_execute_with_version_flag
    spec_fetcher do |fetcher|
      fetcher.spec "coolgem", "1.0"
      fetcher.spec "coolgem", "2.0"
    end

    @cmd.handle_options %w[coolgem --remote --version 1.0]

    use_ui @ui do
      @cmd.execute
    end

    expected = <<-EOF

*** REMOTE GEMS ***

coolgem (1.0)
    Author: A User
    Homepage: http://example.com

    this is a summary
    EOF

    assert_equal expected, @ui.output
  end
end
