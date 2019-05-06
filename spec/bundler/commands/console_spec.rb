# frozen_string_literal: true

RSpec.describe "bundle console", :bundler => "< 3" do
  before :each do
    install_gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"
      gem "rack"
      gem "activesupport", :group => :test
      gem "rack_middleware", :group => :development
    G
  end

  it "starts IRB with the default group loaded" do
    bundle "console" do |input, _, _|
      input.puts("puts RACK")
      input.puts("exit")
    end
    expect(out).to include("0.9.1")
  end

  it "uses IRB as default console" do
    bundle "console" do |input, _, _|
      input.puts("__method__")
      input.puts("exit")
    end
    expect(out).to include(":irb_binding")
  end

  it "starts another REPL if configured as such" do
    install_gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"
      gem "pry"
    G
    bundle "config set console pry"

    bundle "console" do |input, _, _|
      input.puts("__method__")
      input.puts("exit")
    end
    expect(out).to include(":__pry__")
  end

  it "falls back to IRB if the other REPL isn't available" do
    bundle "config set console pry"
    # make sure pry isn't there

    bundle "console" do |input, _, _|
      input.puts("__method__")
      input.puts("exit")
    end
    expect(out).to include(":irb_binding")
  end

  it "doesn't load any other groups" do
    bundle "console" do |input, _, _|
      input.puts("puts ACTIVESUPPORT")
      input.puts("exit")
    end
    expect(out).to include("NameError")
  end

  describe "when given a group" do
    it "loads the given group" do
      bundle "console test" do |input, _, _|
        input.puts("puts ACTIVESUPPORT")
        input.puts("exit")
      end
      expect(out).to include("2.3.5")
    end

    it "loads the default group" do
      bundle "console test" do |input, _, _|
        input.puts("puts RACK")
        input.puts("exit")
      end
      expect(out).to include("0.9.1")
    end

    it "doesn't load other groups" do
      bundle "console test" do |input, _, _|
        input.puts("puts RACK_MIDDLEWARE")
        input.puts("exit")
      end
      expect(out).to include("NameError")
    end
  end

  it "performs an automatic bundle install" do
    gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"
      gem "rack"
      gem "activesupport", :group => :test
      gem "rack_middleware", :group => :development
      gem "foo"
    G

    bundle "config set auto_install 1"
    bundle :console do |input, _, _|
      input.puts("puts 'hello'")
      input.puts("exit")
    end
    expect(out).to include("Installing foo 1.0")
    expect(out).to include("hello")
    expect(the_bundle).to include_gems "foo 1.0"
  end
end
