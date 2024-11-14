require "bundled_gems"

RSpec.describe "bundled_gems.rb" do
  ENV["TEST_BUNDLED_GEMS"] = "true"

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

  it "Show warning dash gem like net/smtp" do
    script <<-RUBY
      gemfile do
        source "https://rubygems.org"
      end

      begin
        require "net/smtp"
      rescue LoadError
      end
    RUBY

    expect(err).to include(/net\/smtp was loaded from (.*) from Ruby 3.1.0/)
    expect(err).to include("You can add net-smtp")
  end

  it "Show warning when warn is not the standard one in the current scope" do
    script <<-RUBY
      module My
        def warn(msg)
        end

        def my
          gemfile do
            source "https://rubygems.org"
          end

          require "ostruct"
        end

        extend self
      end

      My.my
    RUBY

    expect(err).to include(/ostruct was loaded from (.*) from Ruby 3.5.0/)
  end
end
