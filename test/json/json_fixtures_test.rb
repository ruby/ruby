# frozen_string_literal: true
require_relative 'test_helper'

class JSONFixturesTest < Test::Unit::TestCase
  fixtures = File.join(File.dirname(__FILE__), 'fixtures/{fail,pass}*.json')
  passed, failed = Dir[fixtures].partition { |f| f['pass'] }

  passed.each do |f|
    name = File.basename(f).gsub(".", "_")
    class_eval <<-RUBY, __FILE__, __LINE__+1
    def test_#{name}
      assert JSON.parse(File.read(#{f.inspect})), "Did not pass for fixture '#{File.basename(f)}': \#{File.read(#{f.inspect})}"
    end
    RUBY
  end

  failed.each do |f|
    name = File.basename(f).gsub(".", "_")
    class_eval <<-RUBY, __FILE__, __LINE__+1
      def test_#{name}
        source = File.read(#{f.inspect})
        assert_raise(JSON::ParserError, JSON::NestingError,
        "Did not fail for fixture '#{name}': \#{source.inspect}") do
          JSON.parse(source)
        end
      end
    RUBY
  end
end
