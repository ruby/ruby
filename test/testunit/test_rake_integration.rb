require 'minitest/autorun'
require 'tmpdir'
require_relative '../ruby/envutil'

class RakeIntegration < MiniTest::Unit::TestCase
  include Test::Unit::Assertions
  RAKE_LOADER = File.expand_path(
    File.join(
    File.dirname(__FILE__),
    '..',
    '..',
    'lib',
    'rake',
    'rake_test_loader.rb'))

  def test_with_rake_runner
    Dir.mktmpdir do |dir|
      filename = File.join dir, 'testing.rb'
      File.open(filename, 'wb') do |f|
        f.write <<-eotest
require 'test/unit'
raise 'loaded twice' if defined?(FooTest)
class FooTest; end
        eotest
      end

      assert_ruby_status(%w{ -w } + [RAKE_LOADER, filename])
    end
  end
end
