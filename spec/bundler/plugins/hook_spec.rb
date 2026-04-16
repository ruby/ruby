# frozen_string_literal: true

RSpec.describe "hook plugins" do
  context "before-install-all hook" do
    before do
      build_repo2 do
        build_plugin "before-install-all-plugin" do |s|
          s.write "plugins.rb", <<-RUBY
            Bundler::Plugin::API.hook Bundler::Plugin::Events::GEM_BEFORE_INSTALL_ALL do |deps|
              puts "gems to be installed \#{deps.map(&:name).join(", ")}"
            end
          RUBY
        end
      end

      bundle "plugin install before-install-all-plugin --source https://gem.repo2"
    end

    it "runs before all rubygems are installed" do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "rake"
        gem "myrack"
      G

      expect(out).to include "gems to be installed rake, myrack"
    end
  end

  context "before-install hook" do
    before do
      build_repo2 do
        build_plugin "before-install-plugin" do |s|
          s.write "plugins.rb", <<-RUBY
            Bundler::Plugin::API.hook Bundler::Plugin::Events::GEM_BEFORE_INSTALL do |spec_install|
              puts "installing gem \#{spec_install.name}"
            end
          RUBY
        end
      end

      bundle "plugin install before-install-plugin --source https://gem.repo2"
    end

    it "runs before each rubygem is installed" do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "rake"
        gem "myrack"
      G

      expect(out).to include "installing gem rake"
      expect(out).to include "installing gem myrack"
    end
  end

  context "after-install-all hook" do
    before do
      build_repo2 do
        build_plugin "after-install-all-plugin" do |s|
          s.write "plugins.rb", <<-RUBY
            Bundler::Plugin::API.hook Bundler::Plugin::Events::GEM_AFTER_INSTALL_ALL do |deps|
              puts "installed gems \#{deps.map(&:name).join(", ")}"
            end
          RUBY
        end
      end

      bundle "plugin install after-install-all-plugin --source https://gem.repo2"
    end

    it "runs after each all rubygems are installed" do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "rake"
        gem "myrack"
      G

      expect(out).to include "installed gems rake, myrack"
    end
  end

  context "after-install hook" do
    before do
      build_repo2 do
        build_plugin "after-install-plugin" do |s|
          s.write "plugins.rb", <<-RUBY
            Bundler::Plugin::API.hook Bundler::Plugin::Events::GEM_AFTER_INSTALL do |spec_install|
              puts "installed gem \#{spec_install.name} : \#{spec_install.state}"
            end
          RUBY
        end
      end

      bundle "plugin install after-install-plugin --source https://gem.repo2"
    end

    it "runs after each rubygem is installed" do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "rake"
        gem "myrack"
      G

      expect(out).to include "installed gem rake : installed"
      expect(out).to include "installed gem myrack : installed"
    end
  end

  context "before-require-all hook" do
    before do
      build_repo2 do
        build_plugin "before-require-all-plugin" do |s|
          s.write "plugins.rb", <<-RUBY
            Bundler::Plugin::API.hook Bundler::Plugin::Events::GEM_BEFORE_REQUIRE_ALL do |deps|
              puts "gems to be required \#{deps.map(&:name).join(", ")}"
            end
          RUBY
        end
      end

      bundle "plugin install before-require-all-plugin --source https://gem.repo2"
    end

    it "runs before all rubygems are required" do
      install_gemfile_and_bundler_require
      expect(out).to include "gems to be required rake, myrack"
    end
  end

  context "before-require hook" do
    before do
      build_repo2 do
        build_plugin "before-require-plugin" do |s|
          s.write "plugins.rb", <<-RUBY
            Bundler::Plugin::API.hook Bundler::Plugin::Events::GEM_BEFORE_REQUIRE do |dep|
              puts "requiring gem \#{dep.name}"
            end
          RUBY
        end
      end

      bundle "plugin install before-require-plugin --source https://gem.repo2"
    end

    it "runs before each rubygem is required" do
      install_gemfile_and_bundler_require
      expect(out).to include "requiring gem rake"
      expect(out).to include "requiring gem myrack"
    end
  end

  context "after-require-all hook" do
    before do
      build_repo2 do
        build_plugin "after-require-all-plugin" do |s|
          s.write "plugins.rb", <<-RUBY
            Bundler::Plugin::API.hook Bundler::Plugin::Events::GEM_AFTER_REQUIRE_ALL do |deps|
              puts "required gems \#{deps.map(&:name).join(", ")}"
            end
          RUBY
        end
      end

      bundle "plugin install after-require-all-plugin --source https://gem.repo2"
    end

    it "runs after all rubygems are required" do
      install_gemfile_and_bundler_require
      expect(out).to include "required gems rake, myrack"
    end
  end

  context "after-require hook" do
    before do
      build_repo2 do
        build_plugin "after-require-plugin" do |s|
          s.write "plugins.rb", <<-RUBY
            Bundler::Plugin::API.hook Bundler::Plugin::Events::GEM_AFTER_REQUIRE do |dep|
              puts "required gem \#{dep.name}"
            end
          RUBY
        end
      end

      bundle "plugin install after-require-plugin --source https://gem.repo2"
    end

    it "runs after each rubygem is required" do
      install_gemfile_and_bundler_require
      expect(out).to include "required gem rake"
      expect(out).to include "required gem myrack"
    end
  end

  context "before-eval hook" do
    before do
      build_repo2 do
        build_plugin "before-eval-plugin" do |s|
          s.write "plugins.rb", <<-RUBY
            Bundler::Plugin::API.hook Bundler::Plugin::Events::GEM_BEFORE_EVAL do |gemfile, lockfile|
              puts "hooked eval start of \#{File.basename(gemfile)} to \#{File.basename(lockfile)}"
            end
          RUBY
        end
      end

      bundle "plugin install before-eval-plugin --source https://gem.repo2"
    end

    it "runs before the Gemfile is evaluated" do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "rake"
      G

      expect(out).to include "hooked eval start of Gemfile to Gemfile.lock"
    end
  end

  context "after-eval hook" do
    before do
      build_repo2 do
        build_plugin "after-eval-plugin" do |s|
          s.write "plugins.rb", <<-RUBY
            Bundler::Plugin::API.hook Bundler::Plugin::Events::GEM_AFTER_EVAL do |defn|
              puts "hooked eval after with gems \#{defn.dependencies.map(&:name).join(", ")}"
            end
          RUBY
        end
      end

      bundle "plugin install after-eval-plugin --source https://gem.repo2"
    end

    it "runs after the Gemfile is evaluated" do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
        gem "rake"
      G

      expect(out).to include "hooked eval after with gems myrack, rake"
    end
  end

  context "before-fetch and after-fetch hooks" do
    before do
      build_repo2 do
        build_plugin "fetch-timing-plugin" do |s|
          s.write "plugins.rb", <<-RUBY
            @timing_start = nil
            Bundler::Plugin::API.hook Bundler::Plugin::Events::GEM_BEFORE_FETCH do |spec|
              @timing_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
              puts "gem \#{spec.name} started fetch at \#{@timing_start}"
            end
            Bundler::Plugin::API.hook Bundler::Plugin::Events::GEM_AFTER_FETCH do |spec|
              timing_end = Process.clock_gettime(Process::CLOCK_MONOTONIC)
              puts "gem \#{spec.name} took \#{timing_end - @timing_start} to fetch"
              @timing_start = nil
            end
          RUBY
        end
      end

      bundle "plugin install fetch-timing-plugin --source https://gem.repo2"
    end

    it "runs around each gem download" do
      install_gemfile <<-G
        source "https://gem.repo1"
        gem "rake"
        gem "myrack"
      G

      expect(out).to include "gem rake started fetch at"
      expect(out).to match(/gem rake took \d+\.\d+ to fetch/)
      expect(out).to include "gem myrack started fetch at"
      expect(out).to match(/gem myrack took \d+\.\d+ to fetch/)
    end
  end

  context "before-git-fetch and after-git-fetch hooks" do
    before do
      build_repo2 do
        build_plugin "git-fetch-timing-plugin" do |s|
          s.write "plugins.rb", <<-RUBY
            @timing_start = nil
            Bundler::Plugin::API.hook Bundler::Plugin::Events::GIT_BEFORE_FETCH do |source|
              @timing_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
              puts "git source \#{source.name} started fetch at \#{@timing_start}"
            end
            Bundler::Plugin::API.hook Bundler::Plugin::Events::GIT_AFTER_FETCH do |source|
              timing_end = Process.clock_gettime(Process::CLOCK_MONOTONIC)
              puts "git source \#{source.name} took \#{timing_end - @timing_start} to fetch"
              @timing_start = nil
            end
          RUBY
        end
      end

      bundle "plugin install git-fetch-timing-plugin --source https://gem.repo2"
    end

    it "runs around each git source fetch" do
      build_git "foo", "1.0", path: lib_path("foo")

      relative_path = lib_path("foo").relative_path_from(bundled_app)
      install_gemfile <<-G, verbose: true
        source "https://gem.repo1"
        gem "foo", :git => "#{relative_path}"
      G

      expect(out).to include "git source foo started fetch at"
      expect(out).to match(/git source foo took \d+\.\d+ to fetch/)
    end
  end

  def install_gemfile_and_bundler_require
    install_gemfile <<-G
      source "https://gem.repo1"
      gem "rake"
      gem "myrack"
    G

    ruby <<-RUBY
      require "bundler"
      Bundler.require
    RUBY
  end
end
