# frozen_string_literal: false
require 'test/unit'

class TestRequireLib < Test::Unit::TestCase
  TEST_RATIO = ENV["TEST_REQUIRE_THREAD_RATIO"]&.tap {|s|break s.to_f} || 0.05 # testing all files needs too long time...

  Dir.glob(File.expand_path('../../lib/**/*.rb', __dir__)).each do |lib|
    # skip some problems
    next if %r!/lib/(?:bundler|rubygems)\b! =~ lib
    next if %r!/lib/(?:debug|mkmf)\.rb\z! =~ lib
    next if %r!/lib/irb/ext/tracer\.rb\z! =~ lib
    # skip many files that almost use no threads
    next if TEST_RATIO < rand(0.0..1.0)
    define_method "test_thread_size:#{lib}" do
      assert_separately(['--disable-gems', '-W0'], "#{<<~"begin;"}\n#{<<~"end;"}")
      begin;
        n = Thread.list.size
        begin
          require #{lib.dump}
        rescue Exception
          skip $!
        end
        assert_equal n, Thread.list.size
      end;
    end
  end
end
