# frozen_string_literal: true

RSpec.describe "bundle console", readline: true do
  before :each do
    build_repo2 do
      # A minimal fake pry console
      build_gem "pry" do |s|
        s.write "lib/pry.rb", <<-RUBY
          class Pry
            class << self
              def toplevel_binding
                unless defined?(@toplevel_binding) && @toplevel_binding
                  TOPLEVEL_BINDING.eval %{
                    def self.__pry__; binding; end
                    Pry.instance_variable_set(:@toplevel_binding, __pry__)
                    class << self; undef __pry__; end
                  }
                end
                @toplevel_binding.eval('private')
                @toplevel_binding
              end

              def __pry__
                while line = gets
                  begin
                    puts eval(line, toplevel_binding).inspect.sub(/^"(.*)"$/, '=> \\1')
                  rescue Exception => e
                    puts "\#{e.class}: \#{e.message}"
                    puts e.backtrace.first
                  end
                end
              end
              alias start __pry__
            end
          end
        RUBY
      end
    end

    install_gemfile <<-G
      source "https://gem.repo2"
      gem "myrack"
      gem "activesupport", :group => :test
      gem "myrack_middleware", :group => :development
    G
  end

  it "starts IRB with the default group loaded" do
    bundle "console" do |input, _, _|
      input.puts("puts MYRACK")
      input.puts("exit")
    end
    expect(out).to include("0.9.1")
  end

  it "uses IRB as default console" do
    bundle "console" do |input, _, _|
      input.puts("__FILE__")
      input.puts("exit")
    end
    expect(out).to include("(irb)")
  end

  it "starts another REPL if configured as such" do
    install_gemfile <<-G
      source "https://gem.repo2"
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
      input.puts("__FILE__")
      input.puts("exit")
    end
    expect(out).to include("(irb)")
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
        input.puts("puts MYRACK")
        input.puts("exit")
      end
      expect(out).to include("0.9.1")
    end

    it "doesn't load other groups" do
      bundle "console test" do |input, _, _|
        input.puts("puts MYRACK_MIDDLEWARE")
        input.puts("exit")
      end
      expect(out).to include("NameError")
    end
  end

  it "performs an automatic bundle install" do
    gemfile <<-G
      source "https://gem.repo2"
      gem "myrack"
      gem "activesupport", :group => :test
      gem "myrack_middleware", :group => :development
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
