require "bundled_gems"

RSpec.describe "bundled_gems.rb" do
  def script(code, options = {})
    options[:artifice] ||= "compact_index"
    ruby("require 'bundler/inline'\n\n" + code, options)
  end

  it "Show warning require and LoadError" do
    script <<-RUBY
      gemfile do
        source "https://rubygems.org"
      end

      begin
        require "csv"
      rescue LoadError
      end
      require "ostruct"
    RUBY

    expect(err).to include(/csv was loaded from (.*) from Ruby 3.4.0/)
    expect(err).to include(/ostruct was loaded from (.*) from Ruby 3.5.0/)
  end
end
