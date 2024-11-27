load File.dirname(__FILE__) + '/default.mspec'

class MSpecScript
  test_bundled_gems = get(:stdlibs).to_a & get(:bundled_gems).to_a
  unless ENV["BUNDLED_GEMS"].nil? || ENV["BUNDLED_GEMS"].empty?
    test_bundled_gems = ENV["BUNDLED_GEMS"].split(",").map do |gem|
      test_bundled_gems.find{|test_gem| test_gem.include?(gem) }
    end.compact
    exit if test_bundled_gems.empty?
  end
  set :library, test_bundled_gems
  set :files, get(:library)
end
