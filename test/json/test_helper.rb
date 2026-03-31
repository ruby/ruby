$LOAD_PATH.unshift(File.expand_path('../../../ext', __FILE__), File.expand_path('../../../lib', __FILE__))

if ENV["JSON_COVERAGE"]
  # This test helper is loaded inside Ruby's own test suite, so we try to not mess it up.
  require 'coverage'

  branches_supported = Coverage.respond_to?(:supported?) && Coverage.supported?(:branches)

  # Coverage module must be started before SimpleCov to work around the cyclic require order.
  # Track both branches and lines, or else SimpleCov misleadingly reports 0/0 = 100% for non-branching files.
  Coverage.start(lines:    true,
                 branches: branches_supported)

  require 'simplecov'
  SimpleCov.start do
    # Enabling both coverage types to let SimpleCov know to output them together in reports
    enable_coverage :line
    enable_coverage :branch if branches_supported

    # Can't always trust SimpleCov to find files implicitly
    track_files 'lib/**/*.rb'

    add_filter 'lib/json/truffle_ruby' unless RUBY_ENGINE == 'truffleruby'
  end
end

require 'json'
require 'test/unit'

if ENV["JSON_COMPACT"]
  if GC.respond_to?(:verify_compaction_references)
    # This method was added in Ruby 3.0.0. Calling it this way asks the GC to
    # move objects around, helping to find object movement bugs.
    begin
      GC.verify_compaction_references(expand_heap: true, toward: :empty)
    rescue NotImplementedError, ArgumentError
      # Some platforms don't support compaction
    end
  end

  if GC.respond_to?(:auto_compact=)
    begin
      GC.auto_compact = true
    rescue NotImplementedError
      # Some platforms don't support compaction
    end
  end
end

unless defined?(Test::Unit::CoreAssertions)
  require "core_assertions"
  Test::Unit::TestCase.include Test::Unit::CoreAssertions
end
