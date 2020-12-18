# frozen_string_literal: true

RSpec.describe "bundle install with install-time dependencies" do
  before do
    build_repo2 do
      # Test complicated gem dependencies for install
      build_gem "net_a" do |s|
        s.add_dependency "net_b"
        s.add_dependency "net_build_extensions"
      end

      build_gem "net_b"

      build_gem "net_build_extensions" do |s|
        s.add_dependency "rake"
        s.extensions << "Rakefile"
        s.write "Rakefile", <<-RUBY
          task :default do
            path = File.expand_path("../lib", __FILE__)
            FileUtils.mkdir_p(path)
            File.open("\#{path}/net_build_extensions.rb", "w") do |f|
              f.puts "NET_BUILD_EXTENSIONS = 'YES'"
            end
          end
        RUBY
      end

      build_gem "net_c" do |s|
        s.add_dependency "net_a"
        s.add_dependency "net_d"
      end

      build_gem "net_d"

      build_gem "net_e" do |s|
        s.add_dependency "net_d"
      end
    end
  end

  it "installs gems with implicit rake dependencies" do
    install_gemfile <<-G
      source "#{file_uri_for(gem_repo2)}"
      gem "with_implicit_rake_dep"
      gem "another_implicit_rake_dep"
      gem "rake"
    G

    run <<-R
      require 'implicit_rake_dep'
      require 'another_implicit_rake_dep'
      puts IMPLICIT_RAKE_DEP
      puts ANOTHER_IMPLICIT_RAKE_DEP
    R
    expect(out).to eq("YES\nYES")
  end

  it "installs gems with a dependency with no type" do
    skip "incorrect data check error" if Gem.win_platform?

    build_repo2

    path = "#{gem_repo2}/#{Gem::MARSHAL_SPEC_DIR}/actionpack-2.3.2.gemspec.rz"
    spec = Marshal.load(Bundler.rubygems.inflate(File.binread(path)))
    spec.dependencies.each do |d|
      d.instance_variable_set(:@type, :fail)
    end
    File.open(path, "w") do |f|
      f.write Gem.deflate(Marshal.dump(spec))
    end

    install_gemfile <<-G
      source "#{file_uri_for(gem_repo2)}"
      gem "actionpack", "2.3.2"
    G

    expect(the_bundle).to include_gems "actionpack 2.3.2", "activesupport 2.3.2"
  end

  describe "with crazy rubygem plugin stuff" do
    it "installs plugins" do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"
        gem "net_b"
      G

      expect(the_bundle).to include_gems "net_b 1.0"
    end

    it "installs plugins depended on by other plugins" do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"
        gem "net_a"
      G

      expect(the_bundle).to include_gems "net_a 1.0", "net_b 1.0"
    end

    it "installs multiple levels of dependencies" do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo2)}"
        gem "net_c"
        gem "net_e"
      G

      expect(the_bundle).to include_gems "net_a 1.0", "net_b 1.0", "net_c 1.0", "net_d 1.0", "net_e 1.0"
    end

    context "with ENV['BUNDLER_DEBUG_RESOLVER'] set" do
      it "produces debug output" do
        gemfile <<-G
          source "#{file_uri_for(gem_repo2)}"
          gem "net_c"
          gem "net_e"
        G

        bundle :install, :env => { "BUNDLER_DEBUG_RESOLVER" => "1" }

        expect(out).to include("BUNDLER: Starting resolution")
      end
    end

    context "with ENV['DEBUG_RESOLVER'] set" do
      it "produces debug output" do
        gemfile <<-G
          source "#{file_uri_for(gem_repo2)}"
          gem "net_c"
          gem "net_e"
        G

        bundle :install, :env => { "DEBUG_RESOLVER" => "1" }

        expect(out).to include("BUNDLER: Starting resolution")
      end
    end

    context "with ENV['DEBUG_RESOLVER_TREE'] set" do
      it "produces debug output" do
        gemfile <<-G
          source "#{file_uri_for(gem_repo2)}"
          gem "net_c"
          gem "net_e"
        G

        bundle :install, :env => { "DEBUG_RESOLVER_TREE" => "1" }

        activated_groups = "net_b (1.0) (ruby)"
        activated_groups += ", net_b (1.0) (#{local_platforms.join(", ")})" if local_platforms.any? && local_platforms != ["ruby"]

        expect(out).to include(" net_b").
          and include("BUNDLER: Starting resolution").
          and include("BUNDLER: Finished resolution").
          and include("Attempting to activate [#{activated_groups}]")
      end
    end
  end

  describe "when a required ruby version" do
    context "allows only an older version" do
      before do
        skip "gem not found" if Gem.win_platform?
      end

      it "installs the older version" do
        build_repo2 do
          build_gem "rack", "1.2" do |s|
            s.executables = "rackup"
          end

          build_gem "rack", "9001.0.0" do |s|
            s.required_ruby_version = "> 9000"
          end
        end

        install_gemfile <<-G, :artifice => "compact_index", :env => { "BUNDLER_SPEC_GEM_REPO" => gem_repo2.to_s }
          ruby "#{RUBY_VERSION}"
          source "http://localgemserver.test/"
          gem 'rack'
        G

        expect(out).to_not include("rack-9001.0.0 requires ruby version > 9000")
        expect(the_bundle).to include_gems("rack 1.2")
      end

      it "installs the older version under rate limiting conditions" do
        build_repo4 do
          build_gem "rack", "9001.0.0" do |s|
            s.required_ruby_version = "> 9000"
          end
          build_gem "rack", "1.2"
          build_gem "foo1", "1.0"
        end

        install_gemfile <<-G, :artifice => "compact_index_rate_limited", :env => { "BUNDLER_SPEC_GEM_REPO" => gem_repo4.to_s }
          ruby "#{RUBY_VERSION}"
          source "http://localgemserver.test/"
          gem 'rack'
          gem 'foo1'
        G

        expect(out).to_not include("rack-9001.0.0 requires ruby version > 9000")
        expect(the_bundle).to include_gems("rack 1.2")
      end

      it "installs the older not platform specific version" do
        build_repo4 do
          build_gem "rack", "9001.0.0" do |s|
            s.required_ruby_version = "> 9000"
          end
          build_gem "rack", "1.2" do |s|
            s.platform = mingw
            s.required_ruby_version = "> 9000"
          end
          build_gem "rack", "1.2"
        end

        simulate_platform mingw do
          install_gemfile <<-G, :artifice => "compact_index", :env => { "BUNDLER_SPEC_GEM_REPO" => gem_repo4.to_s }
            ruby "#{RUBY_VERSION}"
            source "http://localgemserver.test/"
            gem 'rack'
          G
        end

        expect(out).to_not include("rack-9001.0.0 requires ruby version > 9000")
        expect(out).to_not include("rack-1.2-#{Bundler.local_platform} requires ruby version > 9000")
        expect(the_bundle).to include_gems("rack 1.2")
      end
    end

    context "allows no gems" do
      before do
        build_repo2 do
          build_gem "require_ruby" do |s|
            s.required_ruby_version = "> 9000"
          end
        end
      end

      let(:ruby_requirement) { %("#{RUBY_VERSION}") }
      let(:error_message_requirement) { "~> #{RUBY_VERSION}.0" }
      let(:error_message_platform) { " #{Bundler.local_platform}" }

      shared_examples_for "ruby version conflicts" do
        it "raises an error during resolution" do
          skip "ruby requirement includes platform and it shouldn't" if Gem.win_platform?

          install_gemfile <<-G, :artifice => "compact_index", :env => { "BUNDLER_SPEC_GEM_REPO" => gem_repo2.to_s }, :raise_on_error => false
            source "http://localgemserver.test/"
            ruby #{ruby_requirement}
            gem 'require_ruby'
          G

          expect(out).to_not include("Gem::InstallError: require_ruby requires Ruby version > 9000")

          nice_error = strip_whitespace(<<-E).strip
            Bundler found conflicting requirements for the Ruby\0 version:
              In Gemfile:
                Ruby\0 (#{error_message_requirement})#{error_message_platform}

                require_ruby#{error_message_platform} was resolved to 1.0, which depends on
                  Ruby\0 (> 9000)

            Ruby\0 (> 9000), which is required by gem 'require_ruby', is not available in the local ruby installation
          E
          expect(err).to end_with(nice_error)
        end
      end

      it_behaves_like "ruby version conflicts"

      describe "with a < requirement" do
        let(:ruby_requirement) { %("< 5000") }
        let(:error_message_requirement) { "< 5000" }

        it_behaves_like "ruby version conflicts"
      end

      describe "with a compound requirement" do
        let(:reqs) { ["> 0.1", "< 5000"] }
        let(:ruby_requirement) { reqs.map(&:dump).join(", ") }
        let(:error_message_requirement) { Gem::Requirement.new(reqs).to_s }

        it_behaves_like "ruby version conflicts"
      end
    end
  end

  describe "when a required rubygems version disallows a gem" do
    it "does not try to install those gems" do
      build_repo2 do
        build_gem "require_rubygems" do |s|
          s.required_rubygems_version = "> 9000"
        end
      end

      install_gemfile <<-G, :raise_on_error => false
        source "#{file_uri_for(gem_repo2)}"
        gem 'require_rubygems'
      G

      expect(err).to_not include("Gem::InstallError: require_rubygems requires RubyGems version > 9000")
      expect(err).to include("require_rubygems-1.0 requires rubygems version > 9000, which is incompatible with the current version, #{Gem::VERSION}")
    end
  end
end
