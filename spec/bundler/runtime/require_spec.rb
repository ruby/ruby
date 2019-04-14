# frozen_string_literal: true

RSpec.describe "Bundler.require" do
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

    build_lib "five", "1.0.0", :no_default => true do |s|
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

    build_lib "nine", "1.0.0" do |s|
      s.write "lib/nine.rb", "puts 'nine'"
    end

    build_lib "ten", "1.0.0" do |s|
      s.write "lib/ten.rb", "puts 'ten'"
    end

    gemfile <<-G
      path "#{lib_path}" do
        gem "one", :group => :bar, :require => %w[baz qux]
        gem "two"
        gem "three", :group => :not
        gem "four", :require => false
        gem "five"
        gem "six", :group => "string"
        gem "seven", :group => :not
        gem "eight", :require => true, :group => :require_true
        env "BUNDLER_TEST" => "nine" do
          gem "nine", :require => true
        end
        gem "ten", :install_if => lambda { ENV["BUNDLER_TEST"] == "ten" }
      end
    G
  end

  it "requires the gems" do
    # default group
    run "Bundler.require"
    expect(out).to eq("two")

    # specific group
    run "Bundler.require(:bar)"
    expect(out).to eq("baz\nqux")

    # default and specific group
    run "Bundler.require(:default, :bar)"
    expect(out).to eq("baz\nqux\ntwo")

    # specific group given as a string
    run "Bundler.require('bar')"
    expect(out).to eq("baz\nqux")

    # specific group declared as a string
    run "Bundler.require(:string)"
    expect(out).to eq("six")

    # required in resolver order instead of gemfile order
    run("Bundler.require(:not)")
    expect(out.split("\n").sort).to eq(%w[seven three])

    # test require: true
    run "Bundler.require(:require_true)"
    expect(out).to eq("eight")
  end

  it "allows requiring gems with non standard names explicitly" do
    run "Bundler.require ; require 'mofive'"
    expect(out).to eq("two\nfive")
  end

  it "allows requiring gems which are scoped by env" do
    ENV["BUNDLER_TEST"] = "nine"
    run "Bundler.require"
    expect(out).to eq("two\nnine")
  end

  it "allows requiring gems which are scoped by install_if" do
    ENV["BUNDLER_TEST"] = "ten"
    run "Bundler.require"
    expect(out).to eq("two\nten")
  end

  it "raises an exception if a require is specified but the file does not exist" do
    gemfile <<-G
      path "#{lib_path}" do
        gem "two", :require => 'fail'
      end
    G

    load_error_run <<-R, "fail"
      Bundler.require
    R

    expect(err_without_deprecations).to eq("ZOMG LOAD ERROR")
  end

  it "displays a helpful message if the required gem throws an error" do
    build_lib "faulty", "1.0.0" do |s|
      s.write "lib/faulty.rb", "raise RuntimeError.new(\"Gem Internal Error Message\")"
    end

    gemfile <<-G
      path "#{lib_path}" do
        gem "faulty"
      end
    G

    run "Bundler.require"
    expect(last_command.stderr).to match("error while trying to load the gem 'faulty'")
    expect(last_command.stderr).to match("Gem Internal Error Message")
  end

  it "doesn't swallow the error when the library has an unrelated error" do
    build_lib "loadfuuu", "1.0.0" do |s|
      s.write "lib/loadfuuu.rb", "raise LoadError.new(\"cannot load such file -- load-bar\")"
    end

    gemfile <<-G
      path "#{lib_path}" do
        gem "loadfuuu"
      end
    G

    cmd = <<-RUBY
      begin
        Bundler.require
      rescue LoadError => e
        $stderr.puts "ZOMG LOAD ERROR: \#{e.message}"
      end
    RUBY
    run(cmd)

    expect(err_without_deprecations).to eq("ZOMG LOAD ERROR: cannot load such file -- load-bar")
  end

  describe "with namespaced gems" do
    before :each do
      build_lib "jquery-rails", "1.0.0" do |s|
        s.write "lib/jquery/rails.rb", "puts 'jquery/rails'"
      end
      lib_path("jquery-rails-1.0.0/lib/jquery-rails.rb").rmtree
    end

    it "requires gem names that are namespaced" do
      gemfile <<-G
        path '#{lib_path}' do
          gem 'jquery-rails'
        end
      G

      run "Bundler.require"
      expect(out).to eq("jquery/rails")
    end

    it "silently passes if the require fails" do
      build_lib "bcrypt-ruby", "1.0.0", :no_default => true do |s|
        s.write "lib/brcrypt.rb", "BCrypt = '1.0.0'"
      end
      gemfile <<-G
        path "#{lib_path}" do
          gem "bcrypt-ruby"
        end
      G

      cmd = <<-RUBY
        require 'bundler'
        Bundler.require
      RUBY
      ruby(cmd)

      expect(last_command.stderr).to be_empty
    end

    it "does not mangle explicitly given requires" do
      gemfile <<-G
        path "#{lib_path}" do
          gem 'jquery-rails', :require => 'jquery-rails'
        end
      G

      load_error_run <<-R, "jquery-rails"
        Bundler.require
      R
      expect(err_without_deprecations).to eq("ZOMG LOAD ERROR")
    end

    it "handles the case where regex fails" do
      build_lib "load-fuuu", "1.0.0" do |s|
        s.write "lib/load-fuuu.rb", "raise LoadError.new(\"Could not open library 'libfuuu-1.0': libfuuu-1.0: cannot open shared object file: No such file or directory.\")"
      end

      gemfile <<-G
        path "#{lib_path}" do
          gem "load-fuuu"
        end
      G

      cmd = <<-RUBY
        begin
          Bundler.require
        rescue LoadError => e
          $stderr.puts "ZOMG LOAD ERROR" if e.message.include?("Could not open library 'libfuuu-1.0'")
        end
      RUBY
      run(cmd)

      expect(err_without_deprecations).to eq("ZOMG LOAD ERROR")
    end

    it "doesn't swallow the error when the library has an unrelated error" do
      build_lib "load-fuuu", "1.0.0" do |s|
        s.write "lib/load/fuuu.rb", "raise LoadError.new(\"cannot load such file -- load-bar\")"
      end
      lib_path("load-fuuu-1.0.0/lib/load-fuuu.rb").rmtree

      gemfile <<-G
        path "#{lib_path}" do
          gem "load-fuuu"
        end
      G

      cmd = <<-RUBY
        begin
          Bundler.require
        rescue LoadError => e
          $stderr.puts "ZOMG LOAD ERROR: \#{e.message}"
        end
      RUBY
      run(cmd)

      expect(err_without_deprecations).to eq("ZOMG LOAD ERROR: cannot load such file -- load-bar")
    end
  end

  describe "using bundle exec" do
    it "requires the locked gems" do
      bundle "exec ruby -e 'Bundler.require'"
      expect(out).to eq("two")

      bundle "exec ruby -e 'Bundler.require(:bar)'"
      expect(out).to eq("baz\nqux")

      bundle "exec ruby -e 'Bundler.require(:default, :bar)'"
      expect(out).to eq("baz\nqux\ntwo")
    end
  end

  describe "order" do
    before(:each) do
      build_lib "one", "1.0.0" do |s|
        s.write "lib/one.rb", <<-ONE
          if defined?(Two)
            Two.two
          else
            puts "two_not_loaded"
          end
          puts 'one'
        ONE
      end

      build_lib "two", "1.0.0" do |s|
        s.write "lib/two.rb", <<-TWO
          module Two
            def self.two
              puts 'module_two'
            end
          end
          puts 'two'
        TWO
      end
    end

    it "works when the gems are in the Gemfile in the correct order" do
      gemfile <<-G
        path "#{lib_path}" do
          gem "two"
          gem "one"
        end
      G

      run "Bundler.require"
      expect(out).to eq("two\nmodule_two\none")
    end

    describe "a gem with different requires for different envs" do
      before(:each) do
        build_gem "multi_gem", :to_bundle => true do |s|
          s.write "lib/one.rb", "puts 'ONE'"
          s.write "lib/two.rb", "puts 'TWO'"
        end

        install_gemfile <<-G
          gem "multi_gem", :require => "one", :group => :one
          gem "multi_gem", :require => "two", :group => :two
        G
      end

      it "requires both with Bundler.require(both)" do
        run "Bundler.require(:one, :two)"
        expect(out).to eq("ONE\nTWO")
      end

      it "requires one with Bundler.require(:one)" do
        run "Bundler.require(:one)"
        expect(out).to eq("ONE")
      end

      it "requires :two with Bundler.require(:two)" do
        run "Bundler.require(:two)"
        expect(out).to eq("TWO")
      end
    end

    it "fails when the gems are in the Gemfile in the wrong order" do
      gemfile <<-G
        path "#{lib_path}" do
          gem "one"
          gem "two"
        end
      G

      run "Bundler.require"
      expect(out).to eq("two_not_loaded\none\ntwo")
    end

    describe "with busted gems" do
      it "should be busted" do
        build_gem "busted_require", :to_bundle => true do |s|
          s.write "lib/busted_require.rb", "require 'no_such_file_omg'"
        end

        install_gemfile <<-G
          gem "busted_require"
        G

        load_error_run <<-R, "no_such_file_omg"
          Bundler.require
        R
        expect(err_without_deprecations).to eq("ZOMG LOAD ERROR")
      end
    end
  end

  it "does not load rubygems gemspecs that are used" do
    install_gemfile! <<-G
      source "file://#{gem_repo1}"
      gem "rack"
    G

    run! <<-R
      path = File.join(Gem.dir, "specifications", "rack-1.0.0.gemspec")
      contents = File.read(path)
      contents = contents.lines.to_a.insert(-2, "\n  raise 'broken gemspec'\n").join
      File.open(path, "w") do |f|
        f.write contents
      end
    R

    run! <<-R
      Bundler.require
      puts "WIN"
    R

    expect(out).to eq("WIN")
  end

  it "does not load git gemspecs that are used" do
    build_git "foo"

    install_gemfile! <<-G
      gem "foo", :git => "#{lib_path("foo-1.0")}"
    G

    run! <<-R
      path = Gem.loaded_specs["foo"].loaded_from
      contents = File.read(path)
      contents = contents.lines.to_a.insert(-2, "\n  raise 'broken gemspec'\n").join
      File.open(path, "w") do |f|
        f.write contents
      end
    R

    run! <<-R
      Bundler.require
      puts "WIN"
    R

    expect(out).to eq("WIN")
  end
end

RSpec.describe "Bundler.require with platform specific dependencies" do
  it "does not require the gems that are pinned to other platforms" do
    install_gemfile <<-G
      source "file://#{gem_repo1}"

      platforms :#{not_local_tag} do
        gem "fail", :require => "omgomg"
      end

      gem "rack", "1.0.0"
    G

    run "Bundler.require"
    expect(last_command.stderr).to be_empty
  end

  it "requires gems pinned to multiple platforms, including the current one" do
    install_gemfile <<-G
      source "file://#{gem_repo1}"

      platforms :#{not_local_tag}, :#{local_tag} do
        gem "rack", :require => "rack"
      end
    G

    run "Bundler.require; puts RACK"

    expect(out).to eq("1.0.0")
    expect(last_command.stderr).to be_empty
  end
end
