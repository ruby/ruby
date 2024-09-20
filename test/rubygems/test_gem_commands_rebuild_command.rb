# frozen_string_literal: true

require_relative "helper"
require "rubygems/commands/build_command"
require "rubygems/commands/rebuild_command"
require "rubygems/package"

class TestGemCommandsRebuildCommand < Gem::TestCase
  def setup
    super

    readme_file = File.join(@tempdir, "README.md")

    begin
      umask_orig = File.umask(2)
      File.open readme_file, "w" do |f|
        f.write "My awesome gem"
      end
    ensure
      File.umask(umask_orig)
    end

    @gem_name = "rebuild_test_gem"
    @gem_version = "1.0.0"
    @gem = util_spec @gem_name do |s|
      s.version = @gem_version
      s.license = "AGPL-3.0"
      s.files = ["README.md"]
    end
  end

  def util_test_build_gem(gem, args)
    @ui = Gem::MockGemUi.new

    cmd = Gem::Commands::BuildCommand.new

    cmd.options[:args] = args
    cmd.options[:build_path] = @tempdir
    use_ui @ui do
      cmd.execute
    end
    gem_file = "#{@gem_name}-#{@gem_version}.gem"
    output = @ui.output.split "\n"
    assert_equal "  Successfully built RubyGem", output.shift
    assert_equal "  Name: #{@gem_name}", output.shift
    assert_equal "  Version: #{@gem_version}", output.shift
    assert_equal "  File: #{gem_file}", output.shift
    assert_equal [], output

    gem_file = File.join(@tempdir, gem_file)
    assert File.exist?(gem_file)

    spec = Gem::Package.new(gem_file).spec

    assert_equal @gem_name, spec.name
    assert_equal "this is a summary", spec.summary
    gem_file
  end

  def util_test_rebuild_gem(gem, args, original_gem_file, gemspec_file, timestamp)
    @ui = Gem::MockGemUi.new

    cmd = Gem::Commands::RebuildCommand.new

    cmd.options[:args] = args
    cmd.options[:original_gem_file] = original_gem_file
    cmd.options[:build_path] = @tempdir
    cmd.options[:gemspec_file] = gemspec_file
    use_ui @ui do
      cmd.execute
    end
    gem_file = "#{@gem_name}-#{@gem_version}.gem"
    output = @ui.output.split "\n"

    assert_equal "  Successfully built RubyGem", output.shift
    assert_equal "  Name: #{@gem_name}", output.shift
    assert_equal "  Version: #{@gem_version}", output.shift
    assert_equal "  File: #{gem_file}", output.shift
    assert_empty output.shift
    assert_match(/^Built at: .+ \(#{timestamp}\)/, output.shift)
    original_line = output.shift
    original = original_line.split(" ")[-1]
    assert_match(/^Original build saved to:   /, original_line)
    reproduced_line = output.shift
    reproduced = reproduced_line.split(" ")[-1]
    assert_match(/^Reproduced build saved to: /, reproduced_line)
    assert_equal "Working directory: #{@tempdir}", output.shift
    assert_equal "", output.shift
    assert_equal "Hash comparison:", output.shift
    output.shift # "  #{old_hash}\t#{old_file}"
    output.shift # "  #{new_hash}\t#{new_file}"
    assert_empty output.shift
    assert_equal "SUCCESS - original and rebuild hashes matched", output.shift
    assert_equal [], output

    assert File.exist?(original)
    assert File.exist?(reproduced)

    old_spec = Gem::Package.new(original).spec
    new_spec = Gem::Package.new(reproduced).spec

    assert_equal @gem_name, old_spec.name
    assert_equal "this is a summary", old_spec.summary

    assert_equal old_spec.name, new_spec.name
    assert_equal old_spec.summary, new_spec.summary

    [reproduced, original]
  end

  def test_build_is_reproducible
    # Back up SOURCE_DATE_EPOCH to restore later.
    epoch = ENV["SOURCE_DATE_EPOCH"]

    gemspec_file = File.join(@tempdir, @gem.spec_name)

    # Initial Build

    # Set SOURCE_DATE_EPOCH to 2001-02-03 04:05:06 -0500.
    ENV["SOURCE_DATE_EPOCH"] = timestamp = Time.new(2001, 2, 3, 4, 5, 6).to_i.to_s
    File.write(gemspec_file, @gem.to_ruby)
    gem_file = util_test_build_gem @gem, [gemspec_file]

    build_contents = File.read(gem_file)

    gem_file_dir = File.dirname(gem_file)
    gem_file_name = File.basename(gem_file)
    original_gem_file = File.join(gem_file_dir, "original-" + gem_file_name)
    File.rename(gem_file, original_gem_file)

    # Rebuild

    # Set SOURCE_DATE_EPOCH to a different value, meaning we are
    # also testing that `gem rebuild` overrides the value.
    ENV["SOURCE_DATE_EPOCH"] = Time.new(2007, 8, 9, 10, 11, 12).to_s

    rebuild_gem_file, saved_gem_file =
      util_test_rebuild_gem(@gem, [@gem_name, @gem_version], original_gem_file, gemspec_file, timestamp)

    rebuild_contents = File.read(rebuild_gem_file)

    assert_equal build_contents, rebuild_contents
  ensure
    ENV["SOURCE_DATE_EPOCH"] = epoch
    if rebuild_gem_file
      File.unlink(rebuild_gem_file)
      dir = File.dirname(rebuild_gem_file)
      Dir.rmdir(dir)
      File.unlink(saved_gem_file)
      Dir.rmdir(File.dirname(saved_gem_file))
      Dir.rmdir(File.dirname(dir))
    end
  end
end
