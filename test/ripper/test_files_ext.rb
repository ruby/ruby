require_relative 'assert_parse_files.rb'
class TestRipper::Generic
  %w[ext].each do |dir|
    define_method("test_parse_files:#{dir}") do
      assert_parse_files(dir)
    end
  end
end
