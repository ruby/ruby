module My
  def warn(msg)
  end

  def my
    require "bundler/inline"

    gemfile do
      source "https://rubygems.org"
    end

    require "csv"
  end

  extend self
end

My.my
