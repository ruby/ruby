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
