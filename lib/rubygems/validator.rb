#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require 'find'

require 'rubygems/digest/md5'
require 'rubygems/format'
require 'rubygems/installer'

##
# Validator performs various gem file and gem database validation

class Gem::Validator

  include Gem::UserInteraction

  ##
  # Given a gem file's contents, validates against its own MD5 checksum
  # gem_data:: [String] Contents of the gem file

  def verify_gem(gem_data)
    raise Gem::VerificationError, 'empty gem file' if gem_data.size == 0

    unless gem_data =~ /MD5SUM/ then
      return # Don't worry about it...this sucks.  Need to fix MD5 stuff for
      # new format
      # FIXME
    end

    sum_data = gem_data.gsub(/MD5SUM = "([a-z0-9]+)"/,
                             "MD5SUM = \"#{"F" * 32}\"")

    unless Gem::MD5.hexdigest(sum_data) == $1.to_s then
      raise Gem::VerificationError, 'invalid checksum for gem file'
    end
  end

  ##
  # Given the path to a gem file, validates against its own MD5 checksum
  #
  # gem_path:: [String] Path to gem file

  def verify_gem_file(gem_path)
    open gem_path, Gem.binary_mode do |file|
      gem_data = file.read
      verify_gem gem_data
    end
  rescue Errno::ENOENT
    raise Gem::VerificationError, "missing gem file #{gem_path}"
  end

  private

  def find_files_for_gem(gem_directory)
    installed_files = []
    Find.find(gem_directory) {|file_name|
      fn = file_name.slice((gem_directory.size)..(file_name.size-1)).sub(/^\//, "")
      if(!(fn =~ /CVS/ || File.directory?(fn) || fn == "")) then
        installed_files << fn
      end

    }
    installed_files
  end

  public

  ErrorData = Struct.new :path, :problem

  ##
  # Checks the gem directory for the following potential
  # inconsistencies/problems:
  #
  # * Checksum gem itself
  # * For each file in each gem, check consistency of installed versions
  # * Check for files that aren't part of the gem but are in the gems directory
  # * 1 cache - 1 spec - 1 directory.
  #
  # returns a hash of ErrorData objects, keyed on the problem gem's name.

  def alien
    errors = {}

    Gem::SourceIndex.from_installed_gems.each do |gem_name, gem_spec|
      errors[gem_name] ||= []

      gem_path = File.join(Gem.dir, "cache", gem_spec.full_name) + ".gem"
      spec_path = File.join(Gem.dir, "specifications", gem_spec.full_name) + ".gemspec"
      gem_directory = File.join(Gem.dir, "gems", gem_spec.full_name)

      installed_files = find_files_for_gem(gem_directory)

      unless File.exist? spec_path then
        errors[gem_name] << ErrorData.new(spec_path, "Spec file doesn't exist for installed gem")
      end

      begin
        verify_gem_file(gem_path)

        open gem_path, Gem.binary_mode do |file|
          format = Gem::Format.from_file_by_path(gem_path)
          format.file_entries.each do |entry, data|
            # Found this file.  Delete it from list
            installed_files.delete remove_leading_dot_dir(entry['path'])

            next unless data # HACK `gem check -a mkrf`

            open File.join(gem_directory, entry['path']), Gem.binary_mode do |f|
              unless Gem::MD5.hexdigest(f.read).to_s ==
                Gem::MD5.hexdigest(data).to_s then
                errors[gem_name] << ErrorData.new(entry['path'], "installed file doesn't match original from gem")
              end
            end
          end
        end
      rescue Gem::VerificationError => e
        errors[gem_name] << ErrorData.new(gem_path, e.message)
      end

      # Clean out directories that weren't explicitly included in the gemspec
      # FIXME: This still allows arbitrary incorrect directories.
      installed_files.delete_if {|potential_directory|
        File.directory?(File.join(gem_directory, potential_directory))
      }
      if(installed_files.size > 0) then
        errors[gem_name] << ErrorData.new(gem_path, "Unmanaged files in gem: #{installed_files.inspect}")
      end
    end

    errors
  end

  if RUBY_VERSION < '1.9' then
    class TestRunner
      def initialize(suite, ui)
        @suite = suite
        @ui = ui
      end

      def self.run(suite, ui)
        require 'test/unit/ui/testrunnermediator'
        return new(suite, ui).start
      end

      def start
        @mediator = Test::Unit::UI::TestRunnerMediator.new(@suite)
        @mediator.add_listener(Test::Unit::TestResult::FAULT, &method(:add_fault))
        return @mediator.run_suite
      end

      def add_fault(fault)
        if Gem.configuration.verbose then
          @ui.say fault.long_display
        end
      end
    end

    autoload :TestRunner, 'test/unit/ui/testrunnerutilities'
  end

  ##
  # Runs unit tests for a given gem specification

  def unit_test(gem_spec)
    start_dir = Dir.pwd
    Dir.chdir(gem_spec.full_gem_path)
    $: << File.join(Gem.dir, "gems", gem_spec.full_name)
    # XXX: why do we need this gem_spec when we've already got 'spec'?
    test_files = gem_spec.test_files

    if test_files.empty? then
      say "There are no unit tests to run for #{gem_spec.full_name}"
      return nil
    end

    gem gem_spec.name, "= #{gem_spec.version.version}"

    test_files.each do |f| require f end

    if RUBY_VERSION < '1.9' then
      suite = Test::Unit::TestSuite.new("#{gem_spec.name}-#{gem_spec.version}")

      ObjectSpace.each_object(Class) do |klass|
        suite << klass.suite if (klass < Test::Unit::TestCase)
      end

      result = TestRunner.run suite, ui

      alert_error result.to_s unless result.passed?
    else
      result = MiniTest::Unit.new
      result.run
    end

    result
  ensure
    Dir.chdir(start_dir)
  end

  private
  def remove_leading_dot_dir(path)
    path.sub(/^\.\//, "")
  end

end

