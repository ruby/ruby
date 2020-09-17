# frozen_string_literal: true

RSpec.describe "bundle platform" do
  context "without flags" do
    let(:bundle_platform_platforms_string) do
      local_platforms.reverse.map {|pl| "* #{pl}" }.join("\n")
    end

    it "returns all the output" do
      gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"

        #{ruby_version_correct}

        gem "foo"
      G

      bundle "platform"
      expect(out).to eq(<<-G.chomp)
Your platform is: #{RUBY_PLATFORM}

Your app has gems that work on these platforms:
#{bundle_platform_platforms_string}

Your Gemfile specifies a Ruby version requirement:
* ruby #{RUBY_VERSION}

Your current platform satisfies the Ruby version requirement.
G
    end

    it "returns all the output including the patchlevel" do
      gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"

        #{ruby_version_correct_patchlevel}

        gem "foo"
      G

      bundle "platform"
      expect(out).to eq(<<-G.chomp)
Your platform is: #{RUBY_PLATFORM}

Your app has gems that work on these platforms:
#{bundle_platform_platforms_string}

Your Gemfile specifies a Ruby version requirement:
* ruby #{RUBY_VERSION}p#{RUBY_PATCHLEVEL}

Your current platform satisfies the Ruby version requirement.
G
    end

    it "doesn't print ruby version requirement if it isn't specified" do
      gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"

        gem "foo"
      G

      bundle "platform"
      expect(out).to eq(<<-G.chomp)
Your platform is: #{RUBY_PLATFORM}

Your app has gems that work on these platforms:
#{bundle_platform_platforms_string}

Your Gemfile does not specify a Ruby version requirement.
G
    end

    it "doesn't match the ruby version requirement" do
      gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"

        #{ruby_version_incorrect}

        gem "foo"
      G

      bundle "platform"
      expect(out).to eq(<<-G.chomp)
Your platform is: #{RUBY_PLATFORM}

Your app has gems that work on these platforms:
#{bundle_platform_platforms_string}

Your Gemfile specifies a Ruby version requirement:
* ruby #{not_local_ruby_version}

Your Ruby version is #{RUBY_VERSION}, but your Gemfile specified #{not_local_ruby_version}
G
    end
  end

  context "--ruby" do
    it "returns ruby version when explicit" do
      gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        ruby "1.9.3", :engine => 'ruby', :engine_version => '1.9.3'

        gem "foo"
      G

      bundle "platform --ruby"

      expect(out).to eq("ruby 1.9.3")
    end

    it "defaults to MRI" do
      gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        ruby "1.9.3"

        gem "foo"
      G

      bundle "platform --ruby"

      expect(out).to eq("ruby 1.9.3")
    end

    it "handles jruby" do
      gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        ruby "1.8.7", :engine => 'jruby', :engine_version => '1.6.5'

        gem "foo"
      G

      bundle "platform --ruby"

      expect(out).to eq("ruby 1.8.7 (jruby 1.6.5)")
    end

    it "handles rbx" do
      gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        ruby "1.8.7", :engine => 'rbx', :engine_version => '1.2.4'

        gem "foo"
      G

      bundle "platform --ruby"

      expect(out).to eq("ruby 1.8.7 (rbx 1.2.4)")
    end

    it "handles truffleruby" do
      gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        ruby "2.5.1", :engine => 'truffleruby', :engine_version => '1.0.0-rc6'

        gem "foo"
      G

      bundle "platform --ruby"

      expect(out).to eq("ruby 2.5.1 (truffleruby 1.0.0-rc6)")
    end

    it "raises an error if engine is used but engine version is not" do
      gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        ruby "1.8.7", :engine => 'rbx'

        gem "foo"
      G

      bundle "platform"

      expect(exitstatus).not_to eq(0) if exitstatus
    end

    it "raises an error if engine_version is used but engine is not" do
      gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        ruby "1.8.7", :engine_version => '1.2.4'

        gem "foo"
      G

      bundle "platform"

      expect(exitstatus).not_to eq(0) if exitstatus
    end

    it "raises an error if engine version doesn't match ruby version for MRI" do
      gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        ruby "1.8.7", :engine => 'ruby', :engine_version => '1.2.4'

        gem "foo"
      G

      bundle "platform"

      expect(exitstatus).not_to eq(0) if exitstatus
    end

    it "should print if no ruby version is specified" do
      gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"

        gem "foo"
      G

      bundle "platform --ruby"

      expect(out).to eq("No ruby version specified")
    end

    it "handles when there is a locked requirement" do
      gemfile <<-G
        ruby "< 1.8.7"
      G

      lockfile <<-L
        GEM
          specs:

        PLATFORMS
          ruby

        DEPENDENCIES

        RUBY VERSION
           ruby 1.0.0p127

        BUNDLED WITH
           #{Bundler::VERSION}
      L

      bundle! "platform --ruby"
      expect(out).to eq("ruby 1.0.0p127")
    end

    it "handles when there is a requirement in the gemfile" do
      gemfile <<-G
        ruby ">= 1.8.7"
      G

      bundle! "platform --ruby"
      expect(out).to eq("ruby 1.8.7")
    end

    it "handles when there are multiple requirements in the gemfile" do
      gemfile <<-G
        ruby ">= 1.8.7", "< 2.0.0"
      G

      bundle! "platform --ruby"
      expect(out).to eq("ruby 1.8.7")
    end
  end

  let(:ruby_version_correct) { "ruby \"#{RUBY_VERSION}\", :engine => \"#{local_ruby_engine}\", :engine_version => \"#{local_engine_version}\"" }
  let(:ruby_version_correct_engineless) { "ruby \"#{RUBY_VERSION}\"" }
  let(:ruby_version_correct_patchlevel) { "#{ruby_version_correct}, :patchlevel => '#{RUBY_PATCHLEVEL}'" }
  let(:ruby_version_incorrect) { "ruby \"#{not_local_ruby_version}\", :engine => \"#{local_ruby_engine}\", :engine_version => \"#{not_local_ruby_version}\"" }
  let(:engine_incorrect) { "ruby \"#{RUBY_VERSION}\", :engine => \"#{not_local_tag}\", :engine_version => \"#{RUBY_VERSION}\"" }
  let(:engine_version_incorrect) { "ruby \"#{RUBY_VERSION}\", :engine => \"#{local_ruby_engine}\", :engine_version => \"#{not_local_engine_version}\"" }
  let(:patchlevel_incorrect) { "#{ruby_version_correct}, :patchlevel => '#{not_local_patchlevel}'" }
  let(:patchlevel_fixnum) { "#{ruby_version_correct}, :patchlevel => #{RUBY_PATCHLEVEL}1" }

  def should_be_ruby_version_incorrect
    expect(exitstatus).to eq(18) if exitstatus
    expect(err).to be_include("Your Ruby version is #{RUBY_VERSION}, but your Gemfile specified #{not_local_ruby_version}")
  end

  def should_be_engine_incorrect
    expect(exitstatus).to eq(18) if exitstatus
    expect(err).to be_include("Your Ruby engine is #{local_ruby_engine}, but your Gemfile specified #{not_local_tag}")
  end

  def should_be_engine_version_incorrect
    expect(exitstatus).to eq(18) if exitstatus
    expect(err).to be_include("Your #{local_ruby_engine} version is #{local_engine_version}, but your Gemfile specified #{local_ruby_engine} #{not_local_engine_version}")
  end

  def should_be_patchlevel_incorrect
    expect(exitstatus).to eq(18) if exitstatus
    expect(err).to be_include("Your Ruby patchlevel is #{RUBY_PATCHLEVEL}, but your Gemfile specified #{not_local_patchlevel}")
  end

  def should_be_patchlevel_fixnum
    expect(exitstatus).to eq(18) if exitstatus
    expect(err).to be_include("The Ruby patchlevel in your Gemfile must be a string")
  end

  context "bundle install" do
    it "installs fine when the ruby version matches" do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack"

        #{ruby_version_correct}
      G

      expect(bundled_app("Gemfile.lock")).to exist
    end

    it "installs fine with any engine" do
      simulate_ruby_engine "jruby" do
        install_gemfile <<-G
          source "#{file_uri_for(gem_repo1)}"
          gem "rack"

          #{ruby_version_correct_engineless}
        G

        expect(bundled_app("Gemfile.lock")).to exist
      end
    end

    it "installs fine when the patchlevel matches" do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack"

        #{ruby_version_correct_patchlevel}
      G

      expect(bundled_app("Gemfile.lock")).to exist
    end

    it "doesn't install when the ruby version doesn't match" do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack"

        #{ruby_version_incorrect}
      G

      expect(bundled_app("Gemfile.lock")).not_to exist
      should_be_ruby_version_incorrect
    end

    it "doesn't install when engine doesn't match" do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack"

        #{engine_incorrect}
      G

      expect(bundled_app("Gemfile.lock")).not_to exist
      should_be_engine_incorrect
    end

    it "doesn't install when engine version doesn't match" do
      simulate_ruby_engine "jruby" do
        install_gemfile <<-G
          source "#{file_uri_for(gem_repo1)}"
          gem "rack"

          #{engine_version_incorrect}
        G

        expect(bundled_app("Gemfile.lock")).not_to exist
        should_be_engine_version_incorrect
      end
    end

    it "doesn't install when patchlevel doesn't match" do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack"

        #{patchlevel_incorrect}
      G

      expect(bundled_app("Gemfile.lock")).not_to exist
      should_be_patchlevel_incorrect
    end
  end

  context "bundle check" do
    it "checks fine when the ruby version matches" do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack"
      G

      gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack"

        #{ruby_version_correct}
      G

      bundle :check
      expect(exitstatus).to eq(0) if exitstatus
      expect(out).to eq("Resolving dependencies...\nThe Gemfile's dependencies are satisfied")
    end

    it "checks fine with any engine" do
      simulate_ruby_engine "jruby" do
        install_gemfile <<-G
          source "#{file_uri_for(gem_repo1)}"
          gem "rack"
        G

        gemfile <<-G
          source "#{file_uri_for(gem_repo1)}"
          gem "rack"

          #{ruby_version_correct_engineless}
        G

        bundle :check
        expect(exitstatus).to eq(0) if exitstatus
        expect(out).to eq("Resolving dependencies...\nThe Gemfile's dependencies are satisfied")
      end
    end

    it "fails when ruby version doesn't match" do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack"
      G

      gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack"

        #{ruby_version_incorrect}
      G

      bundle :check
      should_be_ruby_version_incorrect
    end

    it "fails when engine doesn't match" do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack"
      G

      gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack"

        #{engine_incorrect}
      G

      bundle :check
      should_be_engine_incorrect
    end

    it "fails when engine version doesn't match" do
      simulate_ruby_engine "ruby" do
        install_gemfile <<-G
          source "#{file_uri_for(gem_repo1)}"
          gem "rack"
        G

        gemfile <<-G
          source "#{file_uri_for(gem_repo1)}"
          gem "rack"

          #{engine_version_incorrect}
        G

        bundle :check
        should_be_engine_version_incorrect
      end
    end

    it "fails when patchlevel doesn't match" do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack"
      G

      gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack"

        #{patchlevel_incorrect}
      G

      bundle :check
      should_be_patchlevel_incorrect
    end
  end

  context "bundle update" do
    before do
      build_repo2

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"
        gem "activesupport"
        gem "rack-obama"
      G
    end

    it "updates successfully when the ruby version matches" do
      gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"
        gem "activesupport"
        gem "rack-obama"

        #{ruby_version_correct}
      G
      update_repo2 do
        build_gem "activesupport", "3.0"
      end

      bundle "update", :all => true
      expect(the_bundle).to include_gems "rack 1.2", "rack-obama 1.0", "activesupport 3.0"
    end

    it "updates fine with any engine" do
      simulate_ruby_engine "jruby" do
        gemfile <<-G
          source "#{file_uri_for(gem_repo2)}"
          gem "activesupport"
          gem "rack-obama"

          #{ruby_version_correct_engineless}
        G
        update_repo2 do
          build_gem "activesupport", "3.0"
        end

        bundle "update", :all => true
        expect(the_bundle).to include_gems "rack 1.2", "rack-obama 1.0", "activesupport 3.0"
      end
    end

    it "fails when ruby version doesn't match" do
      gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"
        gem "activesupport"
        gem "rack-obama"

        #{ruby_version_incorrect}
      G
      update_repo2 do
        build_gem "activesupport", "3.0"
      end

      bundle :update, :all => true
      should_be_ruby_version_incorrect
    end

    it "fails when ruby engine doesn't match" do
      gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"
        gem "activesupport"
        gem "rack-obama"

        #{engine_incorrect}
      G
      update_repo2 do
        build_gem "activesupport", "3.0"
      end

      bundle :update, :all => true
      should_be_engine_incorrect
    end

    it "fails when ruby engine version doesn't match" do
      simulate_ruby_engine "jruby" do
        gemfile <<-G
          source "#{file_uri_for(gem_repo2)}"
          gem "activesupport"
          gem "rack-obama"

          #{engine_version_incorrect}
        G
        update_repo2 do
          build_gem "activesupport", "3.0"
        end

        bundle :update, :all => true
        should_be_engine_version_incorrect
      end
    end

    it "fails when patchlevel doesn't match" do
      gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack"

        #{patchlevel_incorrect}
      G
      update_repo2 do
        build_gem "activesupport", "3.0"
      end

      bundle :update, :all => true
      should_be_patchlevel_incorrect
    end
  end

  context "bundle info" do
    before do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rails"
      G
    end

    it "prints path if ruby version is correct" do
      install_gemfile! <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rails"

        #{ruby_version_correct}
      G

      bundle "info rails --path"
      expect(out).to eq(default_bundle_path("gems", "rails-2.3.2").to_s)
    end

    it "prints path if ruby version is correct for any engine" do
      simulate_ruby_engine "jruby" do
        install_gemfile! <<-G
          source "#{file_uri_for(gem_repo1)}"
          gem "rails"

          #{ruby_version_correct_engineless}
        G

        bundle "info rails --path"
        expect(out).to eq(default_bundle_path("gems", "rails-2.3.2").to_s)
      end
    end

    it "fails if ruby version doesn't match", :bundler => "< 3" do
      gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rails"

        #{ruby_version_incorrect}
      G

      bundle "show rails"
      should_be_ruby_version_incorrect
    end

    it "fails if engine doesn't match", :bundler => "< 3" do
      gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rails"

        #{engine_incorrect}
      G

      bundle "show rails"
      should_be_engine_incorrect
    end

    it "fails if engine version doesn't match", :bundler => "< 3" do
      simulate_ruby_engine "jruby" do
        gemfile <<-G
          source "#{file_uri_for(gem_repo1)}"
          gem "rails"

          #{engine_version_incorrect}
        G

        bundle "show rails"
        should_be_engine_version_incorrect
      end
    end

    it "fails when patchlevel doesn't match", :bundler => "< 3" do
      gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack"

        #{patchlevel_incorrect}
      G
      update_repo2 do
        build_gem "activesupport", "3.0"
      end

      bundle "show rails"
      should_be_patchlevel_incorrect
    end
  end

  context "bundle cache" do
    before do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem 'rack'
      G
    end

    it "copies the .gem file to vendor/cache when ruby version matches" do
      gemfile <<-G
        gem 'rack'

        #{ruby_version_correct}
      G

      bundle :cache
      expect(bundled_app("vendor/cache/rack-1.0.0.gem")).to exist
    end

    it "copies the .gem file to vendor/cache when ruby version matches for any engine" do
      simulate_ruby_engine "jruby" do
        install_gemfile! <<-G
          source "#{file_uri_for(gem_repo1)}"
          gem 'rack'

          #{ruby_version_correct_engineless}
        G

        bundle! :cache
        expect(bundled_app("vendor/cache/rack-1.0.0.gem")).to exist
      end
    end

    it "fails if the ruby version doesn't match" do
      gemfile <<-G
        gem 'rack'

        #{ruby_version_incorrect}
      G

      bundle :cache
      should_be_ruby_version_incorrect
    end

    it "fails if the engine doesn't match" do
      gemfile <<-G
        gem 'rack'

        #{engine_incorrect}
      G

      bundle :cache
      should_be_engine_incorrect
    end

    it "fails if the engine version doesn't match" do
      simulate_ruby_engine "jruby" do
        gemfile <<-G
          gem 'rack'

          #{engine_version_incorrect}
        G

        bundle :cache
        should_be_engine_version_incorrect
      end
    end

    it "fails when patchlevel doesn't match" do
      gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack"

        #{patchlevel_incorrect}
      G

      bundle :cache
      should_be_patchlevel_incorrect
    end
  end

  context "bundle pack" do
    before do
      install_gemfile! <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem 'rack'
      G
    end

    it "copies the .gem file to vendor/cache when ruby version matches" do
      gemfile <<-G
        gem 'rack'

        #{ruby_version_correct}
      G

      bundle :cache
      expect(bundled_app("vendor/cache/rack-1.0.0.gem")).to exist
    end

    it "copies the .gem file to vendor/cache when ruby version matches any engine" do
      simulate_ruby_engine "jruby" do
        install_gemfile! <<-G
          source "#{file_uri_for(gem_repo1)}"
          gem 'rack'

          #{ruby_version_correct_engineless}
        G

        bundle :cache
        expect(bundled_app("vendor/cache/rack-1.0.0.gem")).to exist
      end
    end

    it "fails if the ruby version doesn't match" do
      gemfile <<-G
        gem 'rack'

        #{ruby_version_incorrect}
      G

      bundle :cache
      should_be_ruby_version_incorrect
    end

    it "fails if the engine doesn't match" do
      gemfile <<-G
        gem 'rack'

        #{engine_incorrect}
      G

      bundle :cache
      should_be_engine_incorrect
    end

    it "fails if the engine version doesn't match" do
      simulate_ruby_engine "jruby" do
        gemfile <<-G
          gem 'rack'

          #{engine_version_incorrect}
        G

        bundle :cache
        should_be_engine_version_incorrect
      end
    end

    it "fails when patchlevel doesn't match" do
      gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack"

        #{patchlevel_incorrect}
      G

      bundle :cache
      should_be_patchlevel_incorrect
    end
  end

  context "bundle exec" do
    before do
      ENV["BUNDLER_FORCE_TTY"] = "true"
      system_gems "rack-1.0.0", "rack-0.9.1", :path => :bundle_path
    end

    it "activates the correct gem when ruby version matches" do
      gemfile <<-G
        gem "rack", "0.9.1"

        #{ruby_version_correct}
      G

      bundle "exec rackup"
      expect(out).to include("0.9.1")
    end

    it "activates the correct gem when ruby version matches any engine" do
      simulate_ruby_engine "jruby" do
        system_gems "rack-1.0.0", "rack-0.9.1", :path => :bundle_path
        gemfile <<-G
          gem "rack", "0.9.1"

          #{ruby_version_correct_engineless}
        G

        bundle "exec rackup"
        expect(out).to include("0.9.1")
      end
    end

    it "fails when the ruby version doesn't match" do
      gemfile <<-G
        gem "rack", "0.9.1"

        #{ruby_version_incorrect}
      G

      bundle "exec rackup"
      should_be_ruby_version_incorrect
    end

    it "fails when the engine doesn't match" do
      gemfile <<-G
        gem "rack", "0.9.1"

        #{engine_incorrect}
      G

      bundle "exec rackup"
      should_be_engine_incorrect
    end

    # it "fails when the engine version doesn't match" do
    #   simulate_ruby_engine "jruby" do
    #     gemfile <<-G
    #       gem "rack", "0.9.1"
    #
    #       #{engine_version_incorrect}
    #     G
    #
    #     bundle "exec rackup"
    #     should_be_engine_version_incorrect
    #   end
    # end

    it "fails when patchlevel doesn't match" do
      gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack"

        #{patchlevel_incorrect}
      G

      bundle "exec rackup"
      should_be_patchlevel_incorrect
    end
  end

  context "bundle console", :bundler => "< 3" do
    before do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack"
        gem "activesupport", :group => :test
        gem "rack_middleware", :group => :development
      G
    end

    it "starts IRB with the default group loaded when ruby version matches" do
      gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack"
        gem "activesupport", :group => :test
        gem "rack_middleware", :group => :development

        #{ruby_version_correct}
      G

      bundle "console" do |input, _, _|
        input.puts("puts RACK")
        input.puts("exit")
      end
      expect(out).to include("0.9.1")
    end

    it "starts IRB with the default group loaded when ruby version matches any engine" do
      skip "irb depend on JRuby.compile_ir and don't work in simulated environment." unless RUBY_ENGINE == "jruby"
      simulate_ruby_engine "jruby" do
        gemfile <<-G
          source "#{file_uri_for(gem_repo1)}"
          gem "rack"
          gem "activesupport", :group => :test
          gem "rack_middleware", :group => :development

          #{ruby_version_correct_engineless}
        G

        bundle "console" do |input, _, _|
          input.puts("puts RACK")
          input.puts("exit")
        end
        expect(out).to include("0.9.1")
      end
    end

    it "fails when ruby version doesn't match" do
      gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack"
        gem "activesupport", :group => :test
        gem "rack_middleware", :group => :development

        #{ruby_version_incorrect}
      G

      bundle "console"
      should_be_ruby_version_incorrect
    end

    it "fails when engine doesn't match" do
      gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack"
        gem "activesupport", :group => :test
        gem "rack_middleware", :group => :development

        #{engine_incorrect}
      G

      bundle "console"
      should_be_engine_incorrect
    end

    it "fails when engine version doesn't match" do
      simulate_ruby_engine "jruby" do
        gemfile <<-G
          source "#{file_uri_for(gem_repo1)}"
          gem "rack"
          gem "activesupport", :group => :test
          gem "rack_middleware", :group => :development

          #{engine_version_incorrect}
        G

        bundle "console"
        should_be_engine_version_incorrect
      end
    end

    it "fails when patchlevel doesn't match" do
      gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack"
        gem "activesupport", :group => :test
        gem "rack_middleware", :group => :development

        #{patchlevel_incorrect}
      G

      bundle "console"
      should_be_patchlevel_incorrect
    end
  end

  context "Bundler.setup" do
    before do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "yard"
        gem "rack", :group => :test
      G

      ENV["BUNDLER_FORCE_TTY"] = "true"
    end

    it "makes a Gemfile.lock if setup succeeds" do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "yard"
        gem "rack"

        #{ruby_version_correct}
      G

      FileUtils.rm(bundled_app("Gemfile.lock"))

      run "1"
      expect(bundled_app("Gemfile.lock")).to exist
    end

    it "makes a Gemfile.lock if setup succeeds for any engine" do
      simulate_ruby_engine "jruby" do
        install_gemfile <<-G
          source "#{file_uri_for(gem_repo1)}"
          gem "yard"
          gem "rack"

          #{ruby_version_correct_engineless}
        G

        FileUtils.rm(bundled_app("Gemfile.lock"))

        run "1"
        expect(bundled_app("Gemfile.lock")).to exist
      end
    end

    it "fails when ruby version doesn't match" do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "yard"
        gem "rack"

        #{ruby_version_incorrect}
      G

      FileUtils.rm(bundled_app("Gemfile.lock"))

      ruby <<-R
        require 'bundler/setup'
      R

      expect(bundled_app("Gemfile.lock")).not_to exist
      should_be_ruby_version_incorrect
    end

    it "fails when engine doesn't match" do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "yard"
        gem "rack"

        #{engine_incorrect}
      G

      FileUtils.rm(bundled_app("Gemfile.lock"))

      ruby <<-R
        require 'bundler/setup'
      R

      expect(bundled_app("Gemfile.lock")).not_to exist
      should_be_engine_incorrect
    end

    it "fails when engine version doesn't match" do
      simulate_ruby_engine "jruby" do
        install_gemfile <<-G
          source "#{file_uri_for(gem_repo1)}"
          gem "yard"
          gem "rack"

          #{engine_version_incorrect}
        G

        FileUtils.rm(bundled_app("Gemfile.lock"))

        ruby <<-R
          require 'bundler/setup'
        R

        expect(bundled_app("Gemfile.lock")).not_to exist
        should_be_engine_version_incorrect
      end
    end

    it "fails when patchlevel doesn't match" do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "yard"
        gem "rack"

        #{patchlevel_incorrect}
      G

      FileUtils.rm(bundled_app("Gemfile.lock"))

      ruby <<-R
        require 'bundler/setup'
      R

      expect(bundled_app("Gemfile.lock")).not_to exist
      should_be_patchlevel_incorrect
    end
  end

  context "bundle outdated" do
    before do
      build_repo2 do
        build_git "foo", :path => lib_path("foo")
      end

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"
        gem "activesupport", "2.3.5"
        gem "foo", :git => "#{lib_path("foo")}"
      G
    end

    it "returns list of outdated gems when the ruby version matches" do
      update_repo2 do
        build_gem "activesupport", "3.0"
        update_git "foo", :path => lib_path("foo")
      end

      gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"
        gem "activesupport", "2.3.5"
        gem "foo", :git => "#{lib_path("foo")}"

        #{ruby_version_correct}
      G

      bundle "outdated"
      expect(out).to include("activesupport (newest 3.0, installed 2.3.5, requested = 2.3.5")
      expect(out).to include("foo (newest 1.0")
    end

    it "returns list of outdated gems when the ruby version matches for any engine" do
      simulate_ruby_engine "jruby" do
        bundle! :install
        update_repo2 do
          build_gem "activesupport", "3.0"
          update_git "foo", :path => lib_path("foo")
        end

        gemfile <<-G
          source "#{file_uri_for(gem_repo2)}"
          gem "activesupport", "2.3.5"
          gem "foo", :git => "#{lib_path("foo")}"

          #{ruby_version_correct_engineless}
        G

        bundle "outdated"
        expect(out).to include("activesupport (newest 3.0, installed 2.3.5, requested = 2.3.5)")
        expect(out).to include("foo (newest 1.0")
      end
    end

    it "fails when the ruby version doesn't match" do
      update_repo2 do
        build_gem "activesupport", "3.0"
        update_git "foo", :path => lib_path("foo")
      end

      gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"
        gem "activesupport", "2.3.5"
        gem "foo", :git => "#{lib_path("foo")}"

        #{ruby_version_incorrect}
      G

      bundle "outdated"
      should_be_ruby_version_incorrect
    end

    it "fails when the engine doesn't match" do
      update_repo2 do
        build_gem "activesupport", "3.0"
        update_git "foo", :path => lib_path("foo")
      end

      gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"
        gem "activesupport", "2.3.5"
        gem "foo", :git => "#{lib_path("foo")}"

        #{engine_incorrect}
      G

      bundle "outdated"
      should_be_engine_incorrect
    end

    it "fails when the engine version doesn't match" do
      simulate_ruby_engine "jruby" do
        update_repo2 do
          build_gem "activesupport", "3.0"
          update_git "foo", :path => lib_path("foo")
        end

        gemfile <<-G
          source "#{file_uri_for(gem_repo2)}"
          gem "activesupport", "2.3.5"
          gem "foo", :git => "#{lib_path("foo")}"

          #{engine_version_incorrect}
        G

        bundle "outdated"
        should_be_engine_version_incorrect
      end
    end

    it "fails when the patchlevel doesn't match" do
      simulate_ruby_engine "jruby" do
        update_repo2 do
          build_gem "activesupport", "3.0"
          update_git "foo", :path => lib_path("foo")
        end

        gemfile <<-G
          source "#{file_uri_for(gem_repo2)}"
          gem "activesupport", "2.3.5"
          gem "foo", :git => "#{lib_path("foo")}"

          #{patchlevel_incorrect}
        G

        bundle "outdated"
        should_be_patchlevel_incorrect
      end
    end

    it "fails when the patchlevel is a fixnum" do
      simulate_ruby_engine "jruby" do
        update_repo2 do
          build_gem "activesupport", "3.0"
          update_git "foo", :path => lib_path("foo")
        end

        gemfile <<-G
          source "#{file_uri_for(gem_repo2)}"
          gem "activesupport", "2.3.5"
          gem "foo", :git => "#{lib_path("foo")}"

          #{patchlevel_fixnum}
        G

        bundle "outdated"
        should_be_patchlevel_fixnum
      end
    end
  end
end
