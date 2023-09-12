# frozen_string_literal: true
require 'test/unit'

class TestRequireLib < Test::Unit::TestCase
  libdir = __dir__ + '/../../lib'

  # .rb files at lib
  scripts = Dir.glob('*.rb', base: libdir).map {|f| f.chomp('.rb')}

  # .rb files in subdirectories of lib without same name script
  dirs = Dir.glob('*/', base: libdir).map {|d| d.chomp('/')}
  dirs -= scripts
  scripts.concat(Dir.glob(dirs.map {|d| d + '/*.rb'}, base: libdir).map {|f| f.chomp('.rb')})

  # skip some problems
  scripts -= %w[bundler bundled_gems rubygems mkmf]

  scripts.each do |lib|
    define_method "test_thread_size:#{lib}" do
      assert_separately(['-W0'], "#{<<~"begin;"}\n#{<<~"end;"}")
      begin;
        n = Thread.list.size
        require #{lib.dump}
        assert_equal n, Thread.list.size
      end;
    end
  end
end
