# frozen_string_literal: true

RSpec.describe "bundler/inline#gemfile" do
  def script(code, options = {})
    options[:artifice] ||= "compact_index"
    options[:env] ||= { "BUNDLER_SPEC_GEM_REPO" => gem_repo1.to_s }
    ruby("require 'bundler/inline'\n\n" + code, options)
  end

  before :each do
    build_lib "one", "1.0.0" do |s|
      s.write "lib/baz.rb", "puts 'baz'"
      s.write "lib/qux.rb", "puts 'qux'"
    end

    build_lib "two", "1.0.0" do |s|
      s.write "lib/two.rb", "puts 'two'"
      s.add_dependency "three", "= 1.0.0"
    end

    build_lib "three", "1.0.0" do |s|
      s.write "lib/three.rb", "puts 'three'"
      s.add_dependency "seven", "= 1.0.0"
    end

    build_lib "four", "1.0.0" do |s|
      s.write "lib/four.rb", "puts 'four'"
    end

    build_lib "five", "1.0.0", no_default: true do |s|
      s.write "lib/mofive.rb", "puts 'five'"
    end

    build_lib "six", "1.0.0" do |s|
      s.write "lib/six.rb", "puts 'six'"
    end

    build_lib "seven", "1.0.0" do |s|
      s.write "lib/seven.rb", "puts 'seven'"
    end

    build_lib "eight", "1.0.0" do |s|
      s.write "lib/eight.rb", "puts 'eight'"
    end
  end

  it "requires the gems" do
    script <<-RUBY
      gemfile do
        source "https://gem.repo1"
        path "#{lib_path}" do
          gem "two"
        end
      end
    RUBY

    expect(out).to eq("two")

    script <<-RUBY, raise_on_error: false
      gemfile do
        source "https://gem.repo1"
        path "#{lib_path}" do
          gem "eleven"
        end
      end

      puts "success"
    RUBY

    expect(err).to include "Could not find gem 'eleven'"
    expect(out).not_to include "success"

    script <<-RUBY
      gemfile(true) do
        source "https://gem.repo1"
        gem "myrack"
      end
    RUBY

    expect(out).to include("Myrack's post install message")

    script <<-RUBY, artifice: "endpoint"
      gemfile(true) do
        source "https://notaserver.test"
        gem "activesupport", :require => true
      end
    RUBY

    expect(out).to include("Installing activesupport")
    err_lines = err.split("\n")
    err_lines.reject! {|line| line =~ /\.rb:\d+: warning: / }
    expect(err_lines).to be_empty
  end

  it "lets me use my own ui object" do
    script <<-RUBY, artifice: "endpoint"
      require 'bundler'
      class MyBundlerUI < Bundler::UI::Shell
        def confirm(msg, newline = nil)
          puts "CONFIRMED!"
        end
      end
      my_ui = MyBundlerUI.new
      my_ui.level = "confirm"
      gemfile(true, :ui => my_ui) do
        source "https://notaserver.test"
        gem "activesupport", :require => true
      end
    RUBY

    expect(out).to eq("CONFIRMED!\nCONFIRMED!")
  end

  it "has an option for quiet installation" do
    script <<-RUBY, artifice: "endpoint"
      require 'bundler/inline'

      gemfile(true, :quiet => true) do
        source "https://notaserver.test"
        gem "activesupport", :require => true
      end
    RUBY

    expect(out).to be_empty
  end

  it "raises an exception if passed unknown arguments" do
    script <<-RUBY, raise_on_error: false
      gemfile(true, :arglebargle => true) do
        path "#{lib_path}"
        gem "two"
      end

      puts "success"
    RUBY
    expect(err).to include "Unknown options: arglebargle"
    expect(out).not_to include "success"
  end

  it "does not mutate the option argument" do
    script <<-RUBY
      require 'bundler'
      options = { :ui => Bundler::UI::Shell.new }
      gemfile(false, options) do
        source "https://gem.repo1"
        path "#{lib_path}" do
          gem "two"
        end
      end
      puts "OKAY" if options.key?(:ui)
    RUBY

    expect(out).to match("OKAY")
  end

  it "installs quietly if necessary when the install option is not set" do
    script <<-RUBY
      gemfile do
        source "https://gem.repo1"
        gem "myrack"
      end

      puts MYRACK
    RUBY

    expect(out).to eq("1.0.0")
    expect(err).to be_empty
  end

  it "installs subdependencies quietly if necessary when the install option is not set" do
    build_repo4 do
      build_gem "myrack" do |s|
        s.add_dependency "myrackdep"
      end

      build_gem "myrackdep", "1.0.0"
    end

    script <<-RUBY, env: { "BUNDLER_SPEC_GEM_REPO" => gem_repo4.to_s }
      gemfile do
        source "https://gem.repo4"
        gem "myrack"
      end

      require "myrackdep"
      puts MYRACKDEP
    RUBY

    expect(out).to eq("1.0.0")
    expect(err).to be_empty
  end

  it "installs subdependencies quietly if necessary when the install option is not set, and multiple sources used" do
    build_repo4 do
      build_gem "myrack" do |s|
        s.add_dependency "myrackdep"
      end

      build_gem "myrackdep", "1.0.0"
    end

    script <<-RUBY, artifice: "compact_index_extra_api"
      gemfile do
        source "https://test.repo"
        source "https://test.repo/extra" do
          gem "myrack"
        end
      end

      require "myrackdep"
      puts MYRACKDEP
    RUBY

    expect(out).to eq("1.0.0")
    expect(err).to be_empty
  end

  it "installs quietly from git if necessary when the install option is not set" do
    build_git "foo", "1.0.0"
    baz_ref = build_git("baz", "2.0.0").ref_for("HEAD")
    script <<-RUBY
      gemfile do
        source "https://gem.repo1"
        gem "foo", :git => #{lib_path("foo-1.0.0").to_s.dump}
        gem "baz", :git => #{lib_path("baz-2.0.0").to_s.dump}, :ref => #{baz_ref.dump}
      end

      puts FOO
      puts BAZ
    RUBY

    expect(out).to eq("1.0.0\n2.0.0")
    expect(err).to be_empty
  end

  it "allows calling gemfile twice" do
    script <<-RUBY
      gemfile do
        path "#{lib_path}" do
          source "https://gem.repo1"
          gem "two"
        end
      end

      gemfile do
        path "#{lib_path}" do
          source "https://gem.repo1"
          gem "four"
        end
      end
    RUBY

    expect(out).to eq("two\nfour")
    expect(err).to be_empty
  end

  it "doesn't reinstall already installed gems" do
    system_gems "myrack-1.0.0"

    script <<-RUBY
      require 'bundler'
      ui = Bundler::UI::Shell.new
      ui.level = "confirm"

      gemfile(true, ui: ui) do
        source "https://gem.repo1"
        gem "activesupport"
        gem "myrack"
      end
    RUBY

    expect(out).to include("Installing activesupport")
    expect(out).not_to include("Installing myrack")
    expect(err).to be_empty
  end

  it "installs gems in later gemfile calls" do
    system_gems "myrack-1.0.0"

    script <<-RUBY
      require 'bundler'
      ui = Bundler::UI::Shell.new
      ui.level = "confirm"
      gemfile(true, ui: ui) do
        source "https://gem.repo1"
        gem "myrack"
      end

      gemfile(true, ui: ui) do
        source "https://gem.repo1"
        gem "activesupport"
      end
    RUBY

    expect(out).to include("Installing activesupport")
    expect(out).not_to include("Installing myrack")
    expect(err).to be_empty
  end

  it "doesn't reinstall already installed gems in later gemfile calls" do
    system_gems "myrack-1.0.0"

    script <<-RUBY
      require 'bundler'
      ui = Bundler::UI::Shell.new
      ui.level = "confirm"
      gemfile(true, ui: ui) do
        source "https://gem.repo1"
        gem "activesupport"
      end

      gemfile(true, ui: ui) do
        source "https://gem.repo1"
        gem "myrack"
      end
    RUBY

    expect(out).to include("Installing activesupport")
    expect(out).not_to include("Installing myrack")
    expect(err).to be_empty
  end

  it "installs gems with native extensions in later gemfile calls" do
    system_gems "myrack-1.0.0"

    build_git "foo" do |s|
      s.add_dependency "rake"
      s.extensions << "Rakefile"
      s.write "Rakefile", <<-RUBY
        task :default do
          path = File.expand_path("lib", __dir__)
          FileUtils.mkdir_p(path)
          File.open("\#{path}/foo.rb", "w") do |f|
            f.puts "FOO = 'YES'"
          end
        end
      RUBY
    end

    script <<-RUBY
      require 'bundler'
      ui = Bundler::UI::Shell.new
      ui.level = "confirm"
      gemfile(true, ui: ui) do
        source "https://gem.repo1"
        gem "myrack"
      end

      gemfile(true, ui: ui) do
        source "https://gem.repo1"
        gem "foo", :git => "#{lib_path("foo-1.0")}"
      end

      require 'foo'
      puts FOO
      puts $:.grep(/ext/)
    RUBY

    expect(out).to include("YES")
    expect(out).to include(Pathname.glob(default_bundle_path("bundler/gems/extensions/**/foo-1.0-*")).first.to_s)
    expect(err).to be_empty
  end

  it "installs inline gems when a Gemfile.lock is present" do
    gemfile <<-G
      source "https://notaserver.test"
      gem "rake"
    G

    lockfile <<-G
      GEM
        remote: https://rubygems.org/
        specs:
          rake (11.3.0)

      PLATFORMS
        ruby

      DEPENDENCIES
        rake

      BUNDLED WITH
         #{Bundler::VERSION}
    G

    script <<-RUBY
      gemfile do
        source "https://gem.repo1"
        gem "myrack"
      end

      puts MYRACK
    RUBY

    expect(err).to be_empty
  end

  it "does not leak Gemfile.lock versions to the installation output" do
    gemfile <<-G
      source "https://notaserver.test"
      gem "rake"
    G

    lockfile <<-G
      GEM
        remote: https://rubygems.org/
        specs:
          rake (11.3.0)

      PLATFORMS
        ruby

      DEPENDENCIES
        rake

      BUNDLED WITH
         #{Bundler::VERSION}
    G

    script <<-RUBY
      gemfile(true) do
        source "https://gem.repo1"
        gem "rake", "#{rake_version}"
      end
    RUBY

    expect(out).to include("Installing rake #{rake_version}")
    expect(out).not_to include("was 11.3.0")
    expect(err).to be_empty
  end

  it "installs inline gems when frozen is set" do
    script <<-RUBY, env: { "BUNDLE_FROZEN" => "true", "BUNDLER_SPEC_GEM_REPO" => gem_repo1.to_s }
      gemfile do
        source "https://gem.repo1"
        gem "myrack"
      end

      puts MYRACK
    RUBY

    expect(last_command.stderr).to be_empty
  end

  it "installs inline gems when deployment is set" do
    script <<-RUBY, env: { "BUNDLE_DEPLOYMENT" => "true", "BUNDLER_SPEC_GEM_REPO" => gem_repo1.to_s }
      gemfile do
        source "https://gem.repo1"
        gem "myrack"
      end

      puts MYRACK
    RUBY

    expect(last_command.stderr).to be_empty
  end

  it "installs inline gems when BUNDLE_GEMFILE is set to an empty string" do
    ENV["BUNDLE_GEMFILE"] = ""

    script <<-RUBY
      gemfile do
        source "https://gem.repo1"
        gem "myrack"
      end

      puts MYRACK
    RUBY

    expect(err).to be_empty
  end

  it "installs inline gems when BUNDLE_BIN is set" do
    ENV["BUNDLE_BIN"] = "/usr/local/bundle/bin"

    script <<-RUBY
      gemfile do
        source "https://gem.repo1"
        gem "myrack" # has the myrackup executable
      end

      puts MYRACK
    RUBY
    expect(last_command).to be_success
    expect(out).to eq "1.0.0"
  end

  context "when BUNDLE_PATH is set" do
    it "installs inline gems to the system path regardless" do
      script <<-RUBY, env: { "BUNDLE_PATH" => "./vendor/inline", "BUNDLER_SPEC_GEM_REPO" => gem_repo1.to_s }
        gemfile(true) do
          source "https://gem.repo1"
          gem "myrack"
        end
      RUBY
      expect(last_command).to be_success
      expect(system_gem_path("gems/myrack-1.0.0")).to exist
    end
  end

  it "skips platform warnings" do
    bundle "config set --local force_ruby_platform true"

    script <<-RUBY
      gemfile(true) do
        source "https://gem.repo1"
        gem "myrack", platform: :jruby
      end
    RUBY

    expect(err).to be_empty
  end

  it "still installs if the application has `bundle package` no_install config set" do
    bundle "config set --local no_install true"

    script <<-RUBY
      gemfile do
        source "https://gem.repo1"
        gem "myrack"
      end
    RUBY

    expect(last_command).to be_success
    expect(system_gem_path("gems/myrack-1.0.0")).to exist
  end

  it "preserves previous BUNDLE_GEMFILE value" do
    ENV["BUNDLE_GEMFILE"] = ""
    script <<-RUBY
      gemfile do
        source "https://gem.repo1"
        gem "myrack"
      end

      puts "BUNDLE_GEMFILE is empty" if ENV["BUNDLE_GEMFILE"].empty?
      system("#{Gem.ruby} -w -e '42'") # this should see original value of BUNDLE_GEMFILE
      exit $?.exitstatus
    RUBY

    expect(last_command).to be_success
    expect(out).to include("BUNDLE_GEMFILE is empty")
  end

  it "resets BUNDLE_GEMFILE to the empty string if it wasn't set previously" do
    ENV["BUNDLE_GEMFILE"] = nil
    script <<-RUBY
      gemfile do
        source "https://gem.repo1"
        gem "myrack"
      end

      puts "BUNDLE_GEMFILE is empty" if ENV["BUNDLE_GEMFILE"].empty?
      system("#{Gem.ruby} -w -e '42'") # this should see original value of BUNDLE_GEMFILE
      exit $?.exitstatus
    RUBY

    expect(last_command).to be_success
    expect(out).to include("BUNDLE_GEMFILE is empty")
  end

  it "does not error out if library requires optional dependencies" do
    Dir.mkdir tmp("path_without_gemfile")

    foo_code = <<~RUBY
      begin
        gem "bar"
      rescue LoadError
      end

      puts "WIN"
    RUBY

    build_lib "foo", "1.0.0" do |s|
      s.write "lib/foo.rb", foo_code
    end

    script <<-RUBY, dir: tmp("path_without_gemfile"), env: { "BUNDLER_SPEC_GEM_REPO" => gem_repo2.to_s }
      gemfile do
        source "https://gem.repo2"
        path "#{lib_path}" do
          gem "foo", require: false
        end
      end

      require "foo"
    RUBY

    expect(out).to eq("WIN")
    expect(err).to be_empty
  end

  it "does not load default timeout" do
    default_timeout_version = ruby "gem 'timeout', '< 999999'; require 'timeout'; puts Timeout::VERSION", raise_on_error: false
    skip "timeout isn't a default gem" if default_timeout_version.empty?

    # This only works on RubyGems 3.5.0 or higher
    ruby "require 'rubygems/timeout'", raise_on_error: false
    skip "rubygems under test does not yet vendor timeout" unless last_command.success?

    build_repo4 do
      build_gem "timeout", "999"
    end

    script <<-RUBY, env: { "BUNDLER_SPEC_GEM_REPO" => gem_repo4.to_s }
      require "bundler/inline"

      gemfile(true) do
        source "https://gem.repo4"

        gem "timeout"
      end
    RUBY

    expect(out).to include("Installing timeout 999")
  end

  it "does not upcase ENV" do
    script <<-RUBY
      require 'bundler/inline'

      ENV['Test_Variable'] = 'value string'
      puts("before: \#{ENV.each_key.select { |key| key.match?(/test_variable/i) }}")

      gemfile do
        source "https://gem.repo1"
      end

      puts("after: \#{ENV.each_key.select { |key| key.match?(/test_variable/i) }}")
    RUBY

    expect(out).to include("before: [\"Test_Variable\"]")
    expect(out).to include("after: [\"Test_Variable\"]")
  end

  it "does not create a lockfile" do
    script <<-RUBY
      require 'bundler/inline'

      gemfile do
        source "https://gem.repo1"
      end

      puts Dir.glob("Gemfile.lock")
    RUBY

    expect(out).to be_empty
  end

  it "does not reset ENV" do
    script <<-RUBY
      require 'bundler/inline'

      gemfile do
        source "https://gem.repo1"

        ENV['FOO'] = 'bar'
      end

      puts ENV['FOO']
    RUBY

    expect(out).to eq("bar")
  end

  it "does not load specified version of psych and stringio", :ruby_repo do
    build_repo4 do
      build_gem "psych", "999"
      build_gem "stringio", "999"
    end

    script <<-RUBY, env: { "BUNDLER_SPEC_GEM_REPO" => gem_repo4.to_s }
      require "bundler/inline"

      gemfile(true) do
        source "https://gem.repo4"

        gem "psych"
        gem "stringio"
      end
    RUBY

    expect(out).to include("Installing psych 999")
    expect(out).to include("Installing stringio 999")
    expect(out).to include("The psych gem was resolved to 999")
    expect(out).to include("The stringio gem was resolved to 999")
  end

  it "leaves a lockfile in the same directory as the inline script alone" do
    install_gemfile <<~G
      source "https://gem.repo1"
      gem "foo"
    G

    original_lockfile = lockfile

    script <<-RUBY, env: { "BUNDLER_SPEC_GEM_REPO" => gem_repo1.to_s }
      require "bundler/inline"

      gemfile(true) do
        source "https://gem.repo1"

        gem "myrack"
      end
    RUBY

    expect(lockfile).to eq(original_lockfile)
  end
end
