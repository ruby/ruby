require_relative 'assert_parse_files.rb'
class TestRipper::Generic
  %w[test].each do |dir|
    define_method("test_parse_files:#{dir}") do
      assert_parse_files(dir, "*.rb")
    end
  end
end
