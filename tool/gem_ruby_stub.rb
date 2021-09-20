module Gem
  def self.ruby
    ENV['RUBY'] || RbConfig.ruby
  end
end
