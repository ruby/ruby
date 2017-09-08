# frozen_string_literal: true
require "spec_helper"

RSpec.describe "bundler source plugin" do
  describe "plugins dsl eval for #source with :type option" do
    before do
      update_repo2 do
        build_plugin "bundler-source-psource" do |s|
          s.write "plugins.rb", <<-RUBY
              class OPSource < Bundler::Plugin::API
                source "psource"
              end
          RUBY
        end
      end
    end

    it "installs bundler-source-* gem when no handler for source is present" do
      install_gemfile <<-G
        source "file://#{gem_repo2}"
        source "file://#{lib_path("gitp")}", :type => :psource do
        end
      G

      plugin_should_be_installed("bundler-source-psource")
    end

    it "enables the plugin to require a lib path" do
      update_repo2 do
        build_plugin "bundler-source-psource" do |s|
          s.write "plugins.rb", <<-RUBY
            require "bundler-source-psource"
            class PSource < Bundler::Plugin::API
              source "psource"
            end
          RUBY
        end
      end

      install_gemfile <<-G
        source "file://#{gem_repo2}"
        source "file://#{lib_path("gitp")}", :type => :psource do
        end
      G

      expect(out).to include("Bundle complete!")
    end

    context "with an explicit handler" do
      before do
        update_repo2 do
          build_plugin "another-psource" do |s|
            s.write "plugins.rb", <<-RUBY
                class Cheater < Bundler::Plugin::API
                  source "psource"
                end
            RUBY
          end
        end
      end

      context "explicit presence in gemfile" do
        before do
          install_gemfile <<-G
            source "file://#{gem_repo2}"

            plugin "another-psource"

            source "file://#{lib_path("gitp")}", :type => :psource do
            end
          G
        end

        it "completes successfully" do
          expect(out).to include("Bundle complete!")
        end

        it "installs the explicit one" do
          plugin_should_be_installed("another-psource")
        end

        it "doesn't install the default one" do
          plugin_should_not_be_installed("bundler-source-psource")
        end
      end

      context "explicit default source" do
        before do
          install_gemfile <<-G
            source "file://#{gem_repo2}"

            plugin "bundler-source-psource"

            source "file://#{lib_path("gitp")}", :type => :psource do
            end
          G
        end

        it "completes successfully" do
          expect(out).to include("Bundle complete!")
        end

        it "installs the default one" do
          plugin_should_be_installed("bundler-source-psource")
        end
      end
    end
  end
end
