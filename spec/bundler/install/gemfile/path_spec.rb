# frozen_string_literal: true

RSpec.describe "bundle install with explicit source paths" do
  it "fetches gems with a global path source", :bundler => "< 3" do
    build_lib "foo"

    install_gemfile <<-G
      path "#{lib_path("foo-1.0")}"
      gem 'foo'
    G

    expect(the_bundle).to include_gems("foo 1.0")
  end

  it "fetches gems" do
    build_lib "foo"

    install_gemfile <<-G
      path "#{lib_path("foo-1.0")}" do
        gem 'foo'
      end
    G

    expect(the_bundle).to include_gems("foo 1.0")
  end

  it "supports pinned paths" do
    build_lib "foo"

    install_gemfile <<-G
      gem 'foo', :path => "#{lib_path("foo-1.0")}"
    G

    expect(the_bundle).to include_gems("foo 1.0")
  end

  it "supports relative paths" do
    build_lib "foo"

    relative_path = lib_path("foo-1.0").relative_path_from(Pathname.new(Dir.pwd))

    install_gemfile <<-G
      gem 'foo', :path => "#{relative_path}"
    G

    expect(the_bundle).to include_gems("foo 1.0")
  end

  it "expands paths" do
    build_lib "foo"

    relative_path = lib_path("foo-1.0").relative_path_from(Pathname.new("~").expand_path)

    install_gemfile <<-G
      gem 'foo', :path => "~/#{relative_path}"
    G

    expect(the_bundle).to include_gems("foo 1.0")
  end

  it "expands paths raise error with not existing user's home dir" do
    build_lib "foo"
    username = "some_unexisting_user"
    relative_path = lib_path("foo-1.0").relative_path_from(Pathname.new("/home/#{username}").expand_path)

    install_gemfile <<-G
      gem 'foo', :path => "~#{username}/#{relative_path}"
    G
    expect(err).to match("There was an error while trying to use the path `~#{username}/#{relative_path}`.")
    expect(err).to match("user #{username} doesn't exist")
  end

  it "expands paths relative to Bundler.root" do
    build_lib "foo", :path => bundled_app("foo-1.0")

    install_gemfile <<-G
      gem 'foo', :path => "./foo-1.0"
    G

    bundled_app("subdir").mkpath
    Dir.chdir(bundled_app("subdir")) do
      expect(the_bundle).to include_gems("foo 1.0")
    end
  end

  it "sorts paths consistently on install and update when they start with ./" do
    build_lib "demo", :path => lib_path("demo")
    build_lib "aaa", :path => lib_path("demo/aaa")

    gemfile = <<-G
      gemspec
      gem "aaa", :path => "./aaa"
    G

    File.open(lib_path("demo/Gemfile"), "w") {|f| f.puts gemfile }

    lockfile = <<~L
      PATH
        remote: .
        specs:
          demo (1.0)

      PATH
        remote: aaa
        specs:
          aaa (1.0)

      GEM
        specs:

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        aaa!
        demo!

      BUNDLED WITH
         #{Bundler::VERSION}
    L

    Dir.chdir(lib_path("demo")) do
      bundle :install
      expect(lib_path("demo/Gemfile.lock")).to have_lockfile(lockfile)
      bundle :update, :all => true
      expect(lib_path("demo/Gemfile.lock")).to have_lockfile(lockfile)
    end
  end

  it "expands paths when comparing locked paths to Gemfile paths" do
    build_lib "foo", :path => bundled_app("foo-1.0")

    install_gemfile <<-G
      gem 'foo', :path => File.expand_path("../foo-1.0", __FILE__)
    G

    bundle! :install, forgotten_command_line_options(:frozen => true)
    expect(exitstatus).to eq(0) if exitstatus
  end

  it "installs dependencies from the path even if a newer gem is available elsewhere" do
    system_gems "rack-1.0.0"

    build_lib "rack", "1.0", :path => lib_path("nested/bar") do |s|
      s.write "lib/rack.rb", "puts 'WIN OVERRIDE'"
    end

    build_lib "foo", :path => lib_path("nested") do |s|
      s.add_dependency "rack", "= 1.0"
    end

    install_gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"
      gem "foo", :path => "#{lib_path("nested")}"
    G

    run "require 'rack'"
    expect(out).to eq("WIN OVERRIDE")
  end

  it "works" do
    build_gem "foo", "1.0.0", :to_system => true do |s|
      s.write "lib/foo.rb", "puts 'FAIL'"
    end

    build_lib "omg", "1.0", :path => lib_path("omg") do |s|
      s.add_dependency "foo"
    end

    build_lib "foo", "1.0.0", :path => lib_path("omg/foo")

    install_gemfile <<-G
      gem "omg", :path => "#{lib_path("omg")}"
    G

    expect(the_bundle).to include_gems "foo 1.0"
  end

  it "works with only_update_to_newer_versions" do
    build_lib "omg", "2.0", :path => lib_path("omg")

    install_gemfile <<-G
      gem "omg", :path => "#{lib_path("omg")}"
    G

    build_lib "omg", "1.0", :path => lib_path("omg")

    bundle! :install, :env => { "BUNDLE_BUNDLE_ONLY_UPDATE_TO_NEWER_VERSIONS" => "true" }

    expect(the_bundle).to include_gems "omg 1.0"
  end

  it "prefers gemspecs closer to the path root" do
    build_lib "premailer", "1.0.0", :path => lib_path("premailer") do |s|
      s.write "gemfiles/ruby187.gemspec", <<-G
        Gem::Specification.new do |s|
          s.name    = 'premailer'
          s.version = '1.0.0'
          s.summary = 'Hi'
          s.authors = 'Me'
        end
      G
    end

    install_gemfile <<-G
      gem "premailer", :path => "#{lib_path("premailer")}"
    G

    # Installation of the 'gemfiles' gemspec would fail since it will be unable
    # to require 'premailer.rb'
    expect(the_bundle).to include_gems "premailer 1.0.0"
  end

  it "warns on invalid specs" do
    build_lib "foo"

    gemspec = lib_path("foo-1.0").join("foo.gemspec").to_s
    File.open(gemspec, "w") do |f|
      f.write <<-G
        Gem::Specification.new do |s|
          s.name = "foo"
        end
      G
    end

    install_gemfile <<-G
      gem "foo", :path => "#{lib_path("foo-1.0")}"
    G

    expect(err).to_not include("ERROR REPORT")
    expect(err).to_not include("Your Gemfile has no gem server sources.")
    expect(err).to match(/is not valid. Please fix this gemspec./)
    expect(err).to match(/The validation error was 'missing value for attribute version'/)
    expect(err).to match(/You have one or more invalid gemspecs that need to be fixed/)
  end

  it "supports gemspec syntax" do
    build_lib "foo", "1.0", :path => lib_path("foo") do |s|
      s.add_dependency "rack", "1.0"
    end

    gemfile = <<-G
      source "#{file_uri_for(gem_repo1)}"
      gemspec
    G

    File.open(lib_path("foo/Gemfile"), "w") {|f| f.puts gemfile }

    Dir.chdir(lib_path("foo")) do
      bundle "install"
      expect(the_bundle).to include_gems "foo 1.0"
      expect(the_bundle).to include_gems "rack 1.0"
    end
  end

  it "supports gemspec syntax with an alternative path" do
    build_lib "foo", "1.0", :path => lib_path("foo") do |s|
      s.add_dependency "rack", "1.0"
    end

    install_gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"
      gemspec :path => "#{lib_path("foo")}"
    G

    expect(the_bundle).to include_gems "foo 1.0"
    expect(the_bundle).to include_gems "rack 1.0"
  end

  it "doesn't automatically unlock dependencies when using the gemspec syntax" do
    build_lib "foo", "1.0", :path => lib_path("foo") do |s|
      s.add_dependency "rack", ">= 1.0"
    end

    Dir.chdir lib_path("foo")

    install_gemfile lib_path("foo/Gemfile"), <<-G
      source "#{file_uri_for(gem_repo1)}"
      gemspec
    G

    build_gem "rack", "1.0.1", :to_system => true

    bundle "install"

    expect(the_bundle).to include_gems "foo 1.0"
    expect(the_bundle).to include_gems "rack 1.0"
  end

  it "doesn't automatically unlock dependencies when using the gemspec syntax and the gem has development dependencies" do
    build_lib "foo", "1.0", :path => lib_path("foo") do |s|
      s.add_dependency "rack", ">= 1.0"
      s.add_development_dependency "activesupport"
    end

    Dir.chdir lib_path("foo")

    install_gemfile lib_path("foo/Gemfile"), <<-G
      source "#{file_uri_for(gem_repo1)}"
      gemspec
    G

    build_gem "rack", "1.0.1", :to_system => true

    bundle "install"

    expect(the_bundle).to include_gems "foo 1.0"
    expect(the_bundle).to include_gems "rack 1.0"
  end

  it "raises if there are multiple gemspecs" do
    build_lib "foo", "1.0", :path => lib_path("foo") do |s|
      s.write "bar.gemspec", build_spec("bar", "1.0").first.to_ruby
    end

    install_gemfile <<-G
      gemspec :path => "#{lib_path("foo")}"
    G

    expect(exitstatus).to eq(15) if exitstatus
    expect(err).to match(/There are multiple gemspecs/)
  end

  it "allows :name to be specified to resolve ambiguity" do
    build_lib "foo", "1.0", :path => lib_path("foo") do |s|
      s.write "bar.gemspec"
    end

    install_gemfile <<-G
      gemspec :path => "#{lib_path("foo")}", :name => "foo"
    G

    expect(the_bundle).to include_gems "foo 1.0"
  end

  it "sets up executables" do
    build_lib "foo" do |s|
      s.executables = "foobar"
    end

    install_gemfile <<-G
      path "#{lib_path("foo-1.0")}" do
        gem 'foo'
      end
    G
    expect(the_bundle).to include_gems "foo 1.0"

    bundle "exec foobar"
    expect(out).to eq("1.0")
  end

  it "handles directories in bin/" do
    build_lib "foo"
    lib_path("foo-1.0").join("foo.gemspec").rmtree
    lib_path("foo-1.0").join("bin/performance").mkpath

    install_gemfile <<-G
      gem 'foo', '1.0', :path => "#{lib_path("foo-1.0")}"
    G
    expect(err).to be_empty
  end

  it "removes the .gem file after installing" do
    build_lib "foo"

    install_gemfile <<-G
      gem 'foo', :path => "#{lib_path("foo-1.0")}"
    G

    expect(lib_path("foo-1.0").join("foo-1.0.gem")).not_to exist
  end

  describe "block syntax" do
    it "pulls all gems from a path block" do
      build_lib "omg"
      build_lib "hi2u"

      install_gemfile <<-G
        path "#{lib_path}" do
          gem "omg"
          gem "hi2u"
        end
      G

      expect(the_bundle).to include_gems "omg 1.0", "hi2u 1.0"
    end
  end

  it "keeps source pinning" do
    build_lib "foo", "1.0", :path => lib_path("foo")
    build_lib "omg", "1.0", :path => lib_path("omg")
    build_lib "foo", "1.0", :path => lib_path("omg/foo") do |s|
      s.write "lib/foo.rb", "puts 'FAIL'"
    end

    install_gemfile <<-G
      gem "foo", :path => "#{lib_path("foo")}"
      gem "omg", :path => "#{lib_path("omg")}"
    G

    expect(the_bundle).to include_gems "foo 1.0"
  end

  it "works when the path does not have a gemspec" do
    build_lib "foo", :gemspec => false

    gemfile <<-G
      gem "foo", "1.0", :path => "#{lib_path("foo-1.0")}"
    G

    expect(the_bundle).to include_gems "foo 1.0"

    expect(the_bundle).to include_gems "foo 1.0"
  end

  it "works when the path does not have a gemspec but there is a lockfile" do
    lockfile <<~L
      PATH
        remote: vendor/bar
        specs:

      GEM
        remote: http://rubygems.org
    L

    in_app_root { FileUtils.mkdir_p("vendor/bar") }

    install_gemfile <<-G
      gem "bar", "1.0.0", path: "vendor/bar", require: "bar/nyard"
    G
    expect(exitstatus).to eq(0) if exitstatus
  end

  context "existing lockfile" do
    it "rubygems gems don't re-resolve without changes" do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem 'rack-obama', '1.0'
        gem 'net-ssh', '1.0'
      G

      bundle :check, :env => { "DEBUG" => "1" }
      expect(out).to match(/using resolution from the lockfile/)
      expect(the_bundle).to include_gems "rack-obama 1.0", "net-ssh 1.0"
    end

    it "source path gems w/deps don't re-resolve without changes" do
      build_lib "rack-obama", "1.0", :path => lib_path("omg") do |s|
        s.add_dependency "yard"
      end

      build_lib "net-ssh", "1.0", :path => lib_path("omg") do |s|
        s.add_dependency "yard"
      end

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem 'rack-obama', :path => "#{lib_path("omg")}"
        gem 'net-ssh', :path => "#{lib_path("omg")}"
      G

      bundle :check, :env => { "DEBUG" => "1" }
      expect(out).to match(/using resolution from the lockfile/)
      expect(the_bundle).to include_gems "rack-obama 1.0", "net-ssh 1.0"
    end
  end

  it "installs executable stubs" do
    build_lib "foo" do |s|
      s.executables = ["foo"]
    end

    install_gemfile <<-G
      gem "foo", :path => "#{lib_path("foo-1.0")}"
    G

    bundle "exec foo"
    expect(out).to eq("1.0")
  end

  describe "when the gem version in the path is updated" do
    before :each do
      build_lib "foo", "1.0", :path => lib_path("foo") do |s|
        s.add_dependency "bar"
      end
      build_lib "bar", "1.0", :path => lib_path("foo/bar")

      install_gemfile <<-G
        gem "foo", :path => "#{lib_path("foo")}"
      G
    end

    it "unlocks all gems when the top level gem is updated" do
      build_lib "foo", "2.0", :path => lib_path("foo") do |s|
        s.add_dependency "bar"
      end

      bundle "install"

      expect(the_bundle).to include_gems "foo 2.0", "bar 1.0"
    end

    it "unlocks all gems when a child dependency gem is updated" do
      build_lib "bar", "2.0", :path => lib_path("foo/bar")

      bundle "install"

      expect(the_bundle).to include_gems "foo 1.0", "bar 2.0"
    end
  end

  describe "when dependencies in the path are updated" do
    before :each do
      build_lib "foo", "1.0", :path => lib_path("foo")

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "foo", :path => "#{lib_path("foo")}"
      G
    end

    it "gets dependencies that are updated in the path" do
      build_lib "foo", "1.0", :path => lib_path("foo") do |s|
        s.add_dependency "rack"
      end

      bundle "install"

      expect(the_bundle).to include_gems "rack 1.0.0"
    end

    it "keeps using the same version if it's compatible" do
      build_lib "foo", "1.0", :path => lib_path("foo") do |s|
        s.add_dependency "rack", "0.9.1"
      end

      bundle "install"

      expect(the_bundle).to include_gems "rack 0.9.1"

      lockfile_should_be <<-G
        PATH
          remote: #{lib_path("foo")}
          specs:
            foo (1.0)
              rack (= 0.9.1)

        GEM
          remote: #{file_uri_for(gem_repo1)}/
          specs:
            rack (0.9.1)

        PLATFORMS
          #{lockfile_platforms}

        DEPENDENCIES
          foo!

        BUNDLED WITH
           #{Bundler::VERSION}
      G

      build_lib "foo", "1.0", :path => lib_path("foo") do |s|
        s.add_dependency "rack"
      end

      bundle "install"

      lockfile_should_be <<-G
        PATH
          remote: #{lib_path("foo")}
          specs:
            foo (1.0)
              rack

        GEM
          remote: #{file_uri_for(gem_repo1)}/
          specs:
            rack (0.9.1)

        PLATFORMS
          #{lockfile_platforms}

        DEPENDENCIES
          foo!

        BUNDLED WITH
           #{Bundler::VERSION}
      G

      expect(the_bundle).to include_gems "rack 0.9.1"
    end
  end

  describe "switching sources" do
    it "doesn't switch pinned git sources to rubygems when pinning the parent gem to a path source" do
      build_gem "foo", "1.0", :to_system => true do |s|
        s.write "lib/foo.rb", "raise 'fail'"
      end
      build_lib "foo", "1.0", :path => lib_path("bar/foo")
      build_git "bar", "1.0", :path => lib_path("bar") do |s|
        s.add_dependency "foo"
      end

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "bar", :git => "#{lib_path("bar")}"
      G

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "bar", :path => "#{lib_path("bar")}"
      G

      expect(the_bundle).to include_gems "foo 1.0", "bar 1.0"
    end

    it "switches the source when the gem existed in rubygems and the path was already being used for another gem" do
      build_lib "foo", "1.0", :path => lib_path("foo")
      build_gem "bar", "1.0", :to_system => true do |s|
        s.write "lib/bar.rb", "raise 'fail'"
      end

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "bar"
        path "#{lib_path("foo")}" do
          gem "foo"
        end
      G

      build_lib "bar", "1.0", :path => lib_path("foo/bar")

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        path "#{lib_path("foo")}" do
          gem "foo"
          gem "bar"
        end
      G

      expect(the_bundle).to include_gems "bar 1.0"
    end
  end

  describe "when there are both a gemspec and remote gems" do
    it "doesn't query rubygems for local gemspec name" do
      build_lib "private_lib", "2.2", :path => lib_path("private_lib")
      gemfile = <<-G
        source "http://localgemserver.test"
        gemspec
        gem 'rack'
      G
      File.open(lib_path("private_lib/Gemfile"), "w") {|f| f.puts gemfile }

      Dir.chdir(lib_path("private_lib")) do
        bundle :install, :env => { "DEBUG" => "1" }, :artifice => "endpoint"
        expect(out).to match(%r{^HTTP GET http://localgemserver\.test/api/v1/dependencies\?gems=rack$})
        expect(out).not_to match(/^HTTP GET.*private_lib/)
        expect(the_bundle).to include_gems "private_lib 2.2"
        expect(the_bundle).to include_gems "rack 1.0"
      end
    end
  end

  describe "gem install hooks" do
    it "runs pre-install hooks" do
      build_git "foo"
      gemfile <<-G
        gem "foo", :git => "#{lib_path("foo-1.0")}"
      G

      File.open(lib_path("install_hooks.rb"), "w") do |h|
        h.write <<-H
          Gem.pre_install_hooks << lambda do |inst|
            STDERR.puts "Ran pre-install hook: \#{inst.spec.full_name}"
          end
        H
      end

      bundle :install,
        :requires => [lib_path("install_hooks.rb")]
      expect(err_without_deprecations).to eq("Ran pre-install hook: foo-1.0")
    end

    it "runs post-install hooks" do
      build_git "foo"
      gemfile <<-G
        gem "foo", :git => "#{lib_path("foo-1.0")}"
      G

      File.open(lib_path("install_hooks.rb"), "w") do |h|
        h.write <<-H
          Gem.post_install_hooks << lambda do |inst|
            STDERR.puts "Ran post-install hook: \#{inst.spec.full_name}"
          end
        H
      end

      bundle :install,
        :requires => [lib_path("install_hooks.rb")]
      expect(err_without_deprecations).to eq("Ran post-install hook: foo-1.0")
    end

    it "complains if the install hook fails" do
      build_git "foo"
      gemfile <<-G
        gem "foo", :git => "#{lib_path("foo-1.0")}"
      G

      File.open(lib_path("install_hooks.rb"), "w") do |h|
        h.write <<-H
          Gem.pre_install_hooks << lambda do |inst|
            false
          end
        H
      end

      bundle :install,
        :requires => [lib_path("install_hooks.rb")]
      expect(err).to include("failed for foo-1.0")
    end

    it "loads plugins from the path gem" do
      foo_file = home("foo_plugin_loaded")
      bar_file = home("bar_plugin_loaded")
      expect(foo_file).not_to be_file
      expect(bar_file).not_to be_file

      build_lib "foo" do |s|
        s.write("lib/rubygems_plugin.rb", "FileUtils.touch('#{foo_file}')")
      end

      build_git "bar" do |s|
        s.write("lib/rubygems_plugin.rb", "FileUtils.touch('#{bar_file}')")
      end

      install_gemfile! <<-G
        gem "foo", :path => "#{lib_path("foo-1.0")}"
        gem "bar", :path => "#{lib_path("bar-1.0")}"
      G

      expect(foo_file).to be_file
      expect(bar_file).to be_file
    end
  end
end
