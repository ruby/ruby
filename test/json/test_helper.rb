case ENV['JSON']
when 'pure'
  $LOAD_PATH.unshift(File.expand_path('../../../lib', __FILE__))
  $stderr.puts("Testing JSON::Pure")
  require 'json/pure'
when 'ext'
  $stderr.puts("Testing JSON::Ext")
  $LOAD_PATH.unshift(File.expand_path('../../../ext', __FILE__), File.expand_path('../../../lib', __FILE__))
  require 'json/ext'
else
  $LOAD_PATH.unshift(File.expand_path('../../../ext', __FILE__), File.expand_path('../../../lib', __FILE__))
  $stderr.puts("Testing JSON")
  require 'json'
end

require 'test/unit'
begin
  require 'byebug'
rescue LoadError
end

if GC.respond_to?(:verify_compaction_references)
  # This method was added in Ruby 3.0.0. Calling it this way asks the GC to
  # move objects around, helping to find object movement bugs.
  begin
    GC.verify_compaction_references(double_heap: true, toward: :empty)
  rescue NotImplementedError
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

unless defined?(Test::Unit::CoreAssertions)
  require "core_assertions"
  Test::Unit::TestCase.include Test::Unit::CoreAssertions
end
