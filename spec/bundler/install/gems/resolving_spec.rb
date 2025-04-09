# frozen_string_literal: true

RSpec.describe "bundle install with install-time dependencies" do
  before do
    build_repo2 do
      build_gem "with_implicit_rake_dep" do |s|
        s.extensions << "Rakefile"
        s.write "Rakefile", <<-RUBY
          task :default do
            path = File.expand_path("lib", __dir__)
            FileUtils.mkdir_p(path)
            File.open("\#{path}/implicit_rake_dep.rb", "w") do |f|
              f.puts "IMPLICIT_RAKE_DEP = 'YES'"
            end
          end
        RUBY
      end

      build_gem "another_implicit_rake_dep" do |s|
        s.extensions << "Rakefile"
        s.write "Rakefile", <<-RUBY
          task :default do
            path = File.expand_path("lib", __dir__)
            FileUtils.mkdir_p(path)
            File.open("\#{path}/another_implicit_rake_dep.rb", "w") do |f|
              f.puts "ANOTHER_IMPLICIT_RAKE_DEP = 'YES'"
            end
          end
        RUBY
      end

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
            path = File.expand_path("lib", __dir__)
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
      source "https://gem.repo2"
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

  it "installs gems with implicit rake dependencies without rake previously installed" do
    with_path_as("") do
      install_gemfile <<-G
        source "https://gem.repo2"
        gem "with_implicit_rake_dep"
        gem "another_implicit_rake_dep"
        gem "rake"
      G
    end

    run <<-R
      require 'implicit_rake_dep'
      require 'another_implicit_rake_dep'
      puts IMPLICIT_RAKE_DEP
      puts ANOTHER_IMPLICIT_RAKE_DEP
    R
    expect(out).to eq("YES\nYES")
  end

  it "does not install gems with a dependency with no type" do
    build_repo2

    path = "#{gem_repo2}/#{Gem::MARSHAL_SPEC_DIR}/actionpack-2.3.2.gemspec.rz"
    spec = Marshal.load(Bundler.rubygems.inflate(File.binread(path)))
    spec.dependencies.each do |d|
      d.instance_variable_set(:@type, "fail")
    end
    File.open(path, "wb") do |f|
      f.write Gem.deflate(Marshal.dump(spec))
    end

    install_gemfile <<-G, raise_on_error: false
      source "https://gem.repo2"
      gem "actionpack", "2.3.2"
    G

    expect(err).to include("Downloading actionpack-2.3.2 revealed dependencies not in the API (activesupport (= 2.3.2)).")

    expect(the_bundle).not_to include_gems "actionpack 2.3.2", "activesupport 2.3.2"
  end

  describe "with crazy rubygem plugin stuff" do
    it "installs plugins" do
      install_gemfile <<-G
        source "https://gem.repo2"
        gem "net_b"
      G

      expect(the_bundle).to include_gems "net_b 1.0"
    end

    it "installs plugins depended on by other plugins" do
      install_gemfile <<-G, env: { "DEBUG" => "1" }
        source "https://gem.repo2"
        gem "net_a"
      G

      expect(the_bundle).to include_gems "net_a 1.0", "net_b 1.0"
    end

    it "installs multiple levels of dependencies" do
      install_gemfile <<-G, env: { "DEBUG" => "1" }
        source "https://gem.repo2"
        gem "net_c"
        gem "net_e"
      G

      expect(the_bundle).to include_gems "net_a 1.0", "net_b 1.0", "net_c 1.0", "net_d 1.0", "net_e 1.0"
    end

    context "with ENV['BUNDLER_DEBUG_RESOLVER'] set" do
      it "produces debug output" do
        gemfile <<-G
          source "https://gem.repo2"
          gem "net_c"
          gem "net_e"
        G

        bundle :install, env: { "BUNDLER_DEBUG_RESOLVER" => "1", "DEBUG" => "1" }

        expect(out).to include("Resolving dependencies...")
      end
    end

    context "with ENV['DEBUG_RESOLVER'] set" do
      it "produces debug output" do
        gemfile <<-G
          source "https://gem.repo2"
          gem "net_c"
          gem "net_e"
        G

        bundle :install, env: { "DEBUG_RESOLVER" => "1", "DEBUG" => "1" }

        expect(out).to include("Resolving dependencies...")
      end
    end

    context "with ENV['DEBUG_RESOLVER_TREE'] set" do
      it "produces debug output" do
        gemfile <<-G
          source "https://gem.repo2"
          gem "net_c"
          gem "net_e"
        G

        bundle :install, env: { "DEBUG_RESOLVER_TREE" => "1", "DEBUG" => "1" }

        expect(out).to include(" net_b").
          and include("Resolving dependencies...").
          and include("Solution found after 1 attempts:").
          and include("selected net_b 1.0")
      end
    end
  end

  describe "when a required ruby version" do
    context "allows only an older version" do
      it "installs the older version" do
        build_repo2 do
          build_gem "myrack", "1.2" do |s|
            s.executables = "myrackup"
          end

          build_gem "myrack", "9001.0.0" do |s|
            s.required_ruby_version = "> 9000"
          end
        end

        install_gemfile <<-G
          ruby "#{Gem.ruby_version}"
          source "https://gem.repo2"
          gem 'myrack'
        G

        expect(err).to_not include("myrack-9001.0.0 requires ruby version > 9000")
        expect(the_bundle).to include_gems("myrack 1.2")
      end

      it "installs the older version when using servers not implementing the compact index API" do
        build_repo2 do
          build_gem "myrack", "1.2" do |s|
            s.executables = "myrackup"
          end

          build_gem "myrack", "9001.0.0" do |s|
            s.required_ruby_version = "> 9000"
          end
        end

        install_gemfile <<-G, artifice: "endpoint"
          ruby "#{Gem.ruby_version}"
          source "https://gem.repo2"
          gem 'myrack'
        G

        expect(err).to_not include("myrack-9001.0.0 requires ruby version > 9000")
        expect(the_bundle).to include_gems("myrack 1.2")
      end

      context "when there is a lockfile using the newer incompatible version" do
        before do
          build_repo2 do
            build_gem "parallel_tests", "3.7.0" do |s|
              s.required_ruby_version = ">= #{current_ruby_minor}"
            end

            build_gem "parallel_tests", "3.8.0" do |s|
              s.required_ruby_version = ">= #{next_ruby_minor}"
            end
          end

          gemfile <<-G
            source "https://gem.repo2"
            gem 'parallel_tests'
          G

          checksums = checksums_section do |c|
            c.checksum gem_repo2, "parallel_tests", "3.8.0"
          end

          lockfile <<~L
            GEM
              remote: https://gem.repo2/
              specs:
                parallel_tests (3.8.0)

            PLATFORMS
              #{lockfile_platforms}

            DEPENDENCIES
              parallel_tests
            #{checksums}
            BUNDLED WITH
               #{Bundler::VERSION}
          L
        end

        it "automatically updates lockfile to use the older version" do
          bundle "install --verbose"

          checksums = checksums_section_when_enabled do |c|
            c.checksum gem_repo2, "parallel_tests", "3.7.0"
          end

          expect(lockfile).to eq <<~L
            GEM
              remote: https://gem.repo2/
              specs:
                parallel_tests (3.7.0)

            PLATFORMS
              #{lockfile_platforms}

            DEPENDENCIES
              parallel_tests
            #{checksums}
            BUNDLED WITH
               #{Bundler::VERSION}
          L
        end

        it "gives a meaningful error if we're in frozen mode" do
          expect do
            bundle "install --verbose", env: { "BUNDLE_FROZEN" => "true" }, raise_on_error: false
          end.not_to change { lockfile }

          expect(err).to include("parallel_tests-3.8.0 requires ruby version >= #{next_ruby_minor}")
          expect(err).not_to include("That means the author of parallel_tests (3.8.0) has removed it.")
        end
      end

      context "with transitive dependencies in a lockfile" do
        before do
          build_repo2 do
            build_gem "rubocop", "1.28.2" do |s|
              s.required_ruby_version = ">= #{current_ruby_minor}"

              s.add_dependency "rubocop-ast", ">= 1.17.0", "< 2.0"
            end

            build_gem "rubocop", "1.35.0" do |s|
              s.required_ruby_version = ">= #{next_ruby_minor}"

              s.add_dependency "rubocop-ast", ">= 1.20.1", "< 2.0"
            end

            build_gem "rubocop-ast", "1.17.0" do |s|
              s.required_ruby_version = ">= #{current_ruby_minor}"
            end

            build_gem "rubocop-ast", "1.21.0" do |s|
              s.required_ruby_version = ">= #{next_ruby_minor}"
            end
          end

          gemfile <<-G
            source "https://gem.repo2"
            gem 'rubocop'
          G

          checksums = checksums_section do |c|
            c.checksum gem_repo2, "rubocop", "1.35.0"
            c.checksum gem_repo2, "rubocop-ast", "1.21.0"
          end

          lockfile <<~L
            GEM
              remote: https://gem.repo2/
              specs:
                rubocop (1.35.0)
                  rubocop-ast (>= 1.20.1, < 2.0)
                rubocop-ast (1.21.0)

            PLATFORMS
              #{lockfile_platforms}

            DEPENDENCIES
              parallel_tests
            #{checksums}
            BUNDLED WITH
               #{Bundler::VERSION}
          L
        end

        it "automatically updates lockfile to use the older compatible versions" do
          bundle "install --verbose"

          checksums = checksums_section_when_enabled do |c|
            c.checksum gem_repo2, "rubocop", "1.28.2"
            c.checksum gem_repo2, "rubocop-ast", "1.17.0"
          end

          expect(lockfile).to eq <<~L
            GEM
              remote: https://gem.repo2/
              specs:
                rubocop (1.28.2)
                  rubocop-ast (>= 1.17.0, < 2.0)
                rubocop-ast (1.17.0)

            PLATFORMS
              #{lockfile_platforms}

            DEPENDENCIES
              rubocop
            #{checksums}
            BUNDLED WITH
               #{Bundler::VERSION}
          L
        end
      end

      context "with a Gemfile and lockfile that don't resolve under the current platform" do
        before do
          build_repo4 do
            build_gem "sorbet", "0.5.10554" do |s|
              s.add_dependency "sorbet-static", "0.5.10554"
            end

            build_gem "sorbet-static", "0.5.10554" do |s|
              s.platform = "universal-darwin-21"
            end
          end

          gemfile <<~G
            source "https://gem.repo4"
            gem 'sorbet', '= 0.5.10554'
          G

          lockfile <<~L
            GEM
              remote: https://gem.repo4/
              specs:
                sorbet (0.5.10554)
                  sorbet-static (= 0.5.10554)
                sorbet-static (0.5.10554-universal-darwin-21)

            PLATFORMS
              arm64-darwin-21

            DEPENDENCIES
              sorbet (= 0.5.10554)

            BUNDLED WITH
               #{Bundler::VERSION}
          L
        end

        it "raises a proper error" do
          simulate_platform "aarch64-linux" do
            bundle "install", raise_on_error: false
          end

          nice_error = <<~E.strip
            Could not find gems matching 'sorbet-static (= 0.5.10554)' valid for all resolution platforms (arm64-darwin-21, aarch64-linux) in rubygems repository https://gem.repo4/ or installed locally.

            The source contains the following gems matching 'sorbet-static (= 0.5.10554)':
              * sorbet-static-0.5.10554-universal-darwin-21
          E
          expect(err).to end_with(nice_error)
        end
      end

      context "when adding a new gem that does not resolve under all locked platforms" do
        before do
          simulate_platform "x86_64-linux" do
            build_repo4 do
              build_gem "nokogiri", "1.14.0" do |s|
                s.platform = "x86_64-linux"
              end
              build_gem "nokogiri", "1.14.0" do |s|
                s.platform = "arm-linux"
              end

              build_gem "sorbet-static", "0.5.10696" do |s|
                s.platform = "x86_64-linux"
              end
            end

            lockfile <<~L
              GEM
                remote: https://gem.repo4/
                specs:
                  nokogiri (1.14.0-arm-linux)
                  nokogiri (1.14.0-x86_64-linux)

              PLATFORMS
                arm-linux
                x86_64-linux

              DEPENDENCIES
                nokogiri

              BUNDLED WITH
                 #{Bundler::VERSION}
            L

            gemfile <<~G
              source "https://gem.repo4"

              gem "nokogiri"
              gem "sorbet-static"
            G

            bundle "lock", raise_on_error: false
          end
        end

        it "raises a proper error" do
          nice_error = <<~E.strip
            Could not find gems matching 'sorbet-static' valid for all resolution platforms (arm-linux, x86_64-linux) in rubygems repository https://gem.repo4/ or installed locally.

            The source contains the following gems matching 'sorbet-static':
              * sorbet-static-0.5.10696-x86_64-linux
          E
          expect(err).to end_with(nice_error)
        end
      end

      context "when locked generic variant supports current Ruby, but locked specific variant does not" do
        let(:original_lockfile) do
          <<~L
            GEM
              remote: https://gem.repo4/
              specs:
                nokogiri (1.16.3)
                nokogiri (1.16.3-x86_64-linux)

            PLATFORMS
              ruby
              x86_64-linux

            DEPENDENCIES
              nokogiri

            BUNDLED WITH
               #{Bundler::VERSION}
          L
        end

        before do
          build_repo4 do
            build_gem "nokogiri", "1.16.3"
            build_gem "nokogiri", "1.16.3" do |s|
              s.required_ruby_version = "< #{Gem.ruby_version}"
              s.platform = "x86_64-linux"
            end
          end

          gemfile <<~G
            source "https://gem.repo4"

            gem "nokogiri"
          G

          lockfile original_lockfile
        end

        it "keeps both variants in the lockfile, and uses the generic one since it's compatible" do
          simulate_platform "x86_64-linux" do
            bundle "install --verbose"

            expect(lockfile).to eq(original_lockfile)
            expect(the_bundle).to include_gems("nokogiri 1.16.3")
          end
        end
      end

      it "gives a meaningful error on ruby version mismatches between dependencies" do
        build_repo4 do
          build_gem "requires-old-ruby" do |s|
            s.required_ruby_version = "< #{Gem.ruby_version}"
          end
        end

        build_lib("foo", path: bundled_app) do |s|
          s.required_ruby_version = ">= #{Gem.ruby_version}"

          s.add_dependency "requires-old-ruby"
        end

        install_gemfile <<-G, raise_on_error: false
          source "https://gem.repo4"
          gemspec
        G

        expect(err).to end_with <<~E.strip
          Could not find compatible versions

          Because every version of foo depends on requires-old-ruby >= 0
            and every version of requires-old-ruby depends on Ruby < #{Gem.ruby_version},
            every version of foo requires Ruby < #{Gem.ruby_version}.
          So, because Gemfile depends on foo >= 0
            and current Ruby version is = #{Gem.ruby_version},
            version solving has failed.
        E
      end

      it "installs the older version under rate limiting conditions" do
        build_repo4 do
          build_gem "myrack", "9001.0.0" do |s|
            s.required_ruby_version = "> 9000"
          end
          build_gem "myrack", "1.2"
          build_gem "foo1", "1.0"
        end

        install_gemfile <<-G, artifice: "compact_index_rate_limited"
          ruby "#{Gem.ruby_version}"
          source "https://gem.repo4"
          gem 'myrack'
          gem 'foo1'
        G

        expect(err).to_not include("myrack-9001.0.0 requires ruby version > 9000")
        expect(the_bundle).to include_gems("myrack 1.2")
      end

      it "installs the older not platform specific version" do
        build_repo4 do
          build_gem "myrack", "9001.0.0" do |s|
            s.required_ruby_version = "> 9000"
          end
          build_gem "myrack", "1.2" do |s|
            s.platform = "x86-mingw32"
            s.required_ruby_version = "> 9000"
          end
          build_gem "myrack", "1.2"
        end

        simulate_platform "x86-mingw32" do
          install_gemfile <<-G, artifice: "compact_index"
            ruby "#{Gem.ruby_version}"
            source "https://gem.repo4"
            gem 'myrack'
          G
        end

        expect(err).to_not include("myrack-9001.0.0 requires ruby version > 9000")
        expect(err).to_not include("myrack-1.2-#{Bundler.local_platform} requires ruby version > 9000")
        expect(the_bundle).to include_gems("myrack 1.2")
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

      let(:ruby_requirement) { %("#{Gem.ruby_version}") }
      let(:error_message_requirement) { "= #{Gem.ruby_version}" }

      it "raises a proper error that mentions the current Ruby version during resolution" do
        install_gemfile <<-G, raise_on_error: false
          source "https://gem.repo2"
          gem 'require_ruby'
        G

        expect(out).to_not include("Gem::InstallError: require_ruby requires Ruby version > 9000")

        nice_error = <<~E.strip
          Could not find compatible versions

          Because every version of require_ruby depends on Ruby > 9000
            and Gemfile depends on require_ruby >= 0,
            Ruby > 9000 is required.
          So, because current Ruby version is #{error_message_requirement},
            version solving has failed.
        E
        expect(err).to end_with(nice_error)
      end

      shared_examples_for "ruby version conflicts" do
        it "raises an error during resolution" do
          install_gemfile <<-G, raise_on_error: false
            source "https://gem.repo2"
            ruby #{ruby_requirement}
            gem 'require_ruby'
          G

          expect(out).to_not include("Gem::InstallError: require_ruby requires Ruby version > 9000")

          nice_error = <<~E.strip
            Could not find compatible versions

            Because every version of require_ruby depends on Ruby > 9000
              and Gemfile depends on require_ruby >= 0,
              Ruby > 9000 is required.
            So, because current Ruby version is #{error_message_requirement},
              version solving has failed.
          E
          expect(err).to end_with(nice_error)
        end
      end

      it_behaves_like "ruby version conflicts"

      describe "with a < requirement" do
        let(:ruby_requirement) { %("< 5000") }

        it_behaves_like "ruby version conflicts"
      end

      describe "with a compound requirement" do
        let(:reqs) { ["> 0.1", "< 5000"] }
        let(:ruby_requirement) { reqs.map(&:dump).join(", ") }

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

      install_gemfile <<-G, raise_on_error: false
        source "https://gem.repo2"
        gem 'require_rubygems'
      G

      expect(err).to_not include("Gem::InstallError: require_rubygems requires RubyGems version > 9000")
      nice_error = <<~E.strip
        Because every version of require_rubygems depends on RubyGems > 9000
          and Gemfile depends on require_rubygems >= 0,
          RubyGems > 9000 is required.
        So, because current RubyGems version is = #{Gem::VERSION},
          version solving has failed.
      E
      expect(err).to end_with(nice_error)
    end
  end

  context "when non platform specific gems bring more dependencies", :truffleruby_only do
    before do
      build_repo4 do
        build_gem "foo", "1.0" do |s|
          s.add_dependency "bar"
        end

        build_gem "foo", "2.0" do |s|
          s.platform = "x86_64-linux"
        end

        build_gem "bar"
      end

      gemfile <<-G
        source "https://gem.repo4"
        gem "foo"
      G
    end

    it "locks both ruby and current platform, and resolve to ruby variants that install on truffleruby" do
      checksums = checksums_section_when_enabled do |c|
        c.checksum gem_repo4, "foo", "1.0"
        c.checksum gem_repo4, "bar", "1.0"
      end

      simulate_platform "x86_64-linux" do
        bundle "install"

        expect(lockfile).to eq <<~L
          GEM
            remote: https://gem.repo4/
            specs:
              bar (1.0)
              foo (1.0)
                bar

          PLATFORMS
            ruby
            x86_64-linux

          DEPENDENCIES
            foo
          #{checksums}
          BUNDLED WITH
             #{Bundler::VERSION}
        L
      end
    end
  end
end
