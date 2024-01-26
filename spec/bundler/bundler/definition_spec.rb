# frozen_string_literal: true

require "bundler/definition"

RSpec.describe Bundler::Definition do
  describe "#lock" do
    before do
      allow(Bundler::SharedHelpers).to receive(:find_gemfile) { bundled_app_gemfile }
      allow(Bundler).to receive(:ui) { double("UI", info: "", debug: "") }
    end

    subject { Bundler::Definition.new(bundled_app_lock, [], Bundler::SourceList.new, {}) }

    context "when it's not possible to write to the file" do
      it "raises an PermissionError with explanation" do
        allow(File).to receive(:open).and_call_original
        expect(File).to receive(:open).with(bundled_app_lock, "wb").
          and_raise(Errno::EACCES)
        expect { subject.lock }.
          to raise_error(Bundler::PermissionError, /Gemfile\.lock/)
      end
    end
    context "when a temporary resource access issue occurs" do
      it "raises a TemporaryResourceError with explanation" do
        allow(File).to receive(:open).and_call_original
        expect(File).to receive(:open).with(bundled_app_lock, "wb").
          and_raise(Errno::EAGAIN)
        expect { subject.lock }.
          to raise_error(Bundler::TemporaryResourceError, /temporarily unavailable/)
      end
    end
    context "when Bundler::Definition.no_lock is set to true" do
      before { Bundler::Definition.no_lock = true }
      after { Bundler::Definition.no_lock = false }

      it "does not create a lock file" do
        subject.lock
        expect(File.file?("Gemfile.lock")).to eq false
      end
    end
  end

  describe "detects changes" do
    it "for a path gem with changes" do
      build_lib "foo", "1.0", path: lib_path("foo")

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "foo", :path => "#{lib_path("foo")}"
      G

      build_lib "foo", "1.0", path: lib_path("foo") do |s|
        s.add_dependency "rack", "1.0"
      end

      checksums = checksums_section_when_existing do |c|
        c.no_checksum "foo", "1.0"
        c.checksum gem_repo1, "rack", "1.0.0"
      end

      bundle :install, env: { "DEBUG" => "1" }

      expect(out).to match(/re-resolving dependencies/)
      expect(lockfile).to eq <<~G
        PATH
          remote: #{lib_path("foo")}
          specs:
            foo (1.0)
              rack (= 1.0)

        GEM
          remote: #{file_uri_for(gem_repo1)}/
          specs:
            rack (1.0.0)

        PLATFORMS
          #{lockfile_platforms}

        DEPENDENCIES
          foo!
        #{checksums}
        BUNDLED WITH
           #{Bundler::VERSION}
      G
    end

    it "with an explicit update" do
      build_repo4 do
        build_gem("ffi", "1.9.23") {|s| s.platform = "java" }
        build_gem("ffi", "1.9.23")
      end

      gemfile <<-G
        source "#{file_uri_for(gem_repo4)}"
        gem "ffi"
      G

      bundle "lock --add-platform java"

      bundle "update ffi", env: { "DEBUG" => "1" }

      expect(out).to match(/because bundler is unlocking gems: \(ffi\)/)
    end

    it "for a path gem with deps and no changes" do
      build_lib "foo", "1.0", path: lib_path("foo") do |s|
        s.add_dependency "rack", "1.0"
        s.add_development_dependency "net-ssh", "1.0"
      end

      checksums = checksums_section_when_existing do |c|
        c.no_checksum "foo", "1.0"
        c.checksum gem_repo1, "rack", "1.0.0"
      end

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "foo", :path => "#{lib_path("foo")}"
      G

      expected_lockfile = <<~G
        PATH
          remote: #{lib_path("foo")}
          specs:
            foo (1.0)
              rack (= 1.0)

        GEM
          remote: #{file_uri_for(gem_repo1)}/
          specs:
            rack (1.0.0)

        PLATFORMS
          #{lockfile_platforms}

        DEPENDENCIES
          foo!
        #{checksums}
        BUNDLED WITH
           #{Bundler::VERSION}
      G

      expect(lockfile).to eq(expected_lockfile)

      bundle :check, env: { "DEBUG" => "1" }

      expect(out).to match(/using resolution from the lockfile/)
      expect(lockfile).to eq(expected_lockfile)
    end

    it "for a locked gem for another platform" do
      checksums = checksums_section_when_existing do |c|
        c.no_checksum "only_java", "1.1", "java"
      end

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "only_java", platform: :jruby
      G

      bundle "lock --add-platform java"
      bundle :check, env: { "DEBUG" => "1" }

      expect(out).to match(/using resolution from the lockfile/)
      expect(lockfile).to eq <<~G
        GEM
          remote: #{file_uri_for(gem_repo1)}/
          specs:
            only_java (1.1-java)

        PLATFORMS
          #{lockfile_platforms("java")}

        DEPENDENCIES
          only_java
        #{checksums}
        BUNDLED WITH
           #{Bundler::VERSION}
      G
    end

    it "for a rubygems gem" do
      checksums = checksums_section_when_existing do |c|
        c.checksum gem_repo1, "foo", "1.0"
      end

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "foo"
      G

      bundle :check, env: { "DEBUG" => "1" }

      expect(out).to match(/using resolution from the lockfile/)
      expect(lockfile).to eq <<~G
        GEM
          remote: #{file_uri_for(gem_repo1)}/
          specs:
            foo (1.0)

        PLATFORMS
          #{lockfile_platforms}

        DEPENDENCIES
          foo
        #{checksums}
        BUNDLED WITH
           #{Bundler::VERSION}
      G
    end
  end

  describe "initialize" do
    context "gem version promoter" do
      context "eager unlock" do
        let(:source_list) do
          Bundler::SourceList.new.tap do |source_list|
            source_list.add_global_rubygems_remote(file_uri_for(gem_repo4))
          end
        end

        before do
          gemfile <<-G
            source "#{file_uri_for(gem_repo4)}"
            gem 'isolated_owner'

            gem 'shared_owner_a'
            gem 'shared_owner_b'
          G

          lockfile <<-L
            GEM
              remote: #{file_uri_for(gem_repo4)}
              specs:
                isolated_dep (2.0.1)
                isolated_owner (1.0.1)
                  isolated_dep (~> 2.0)
                shared_dep (5.0.1)
                shared_owner_a (3.0.1)
                  shared_dep (~> 5.0)
                shared_owner_b (4.0.1)
                  shared_dep (~> 5.0)

            PLATFORMS
              ruby

            DEPENDENCIES
              shared_owner_a
              shared_owner_b
              isolated_owner

            BUNDLED WITH
               1.13.0
          L

          allow(Bundler::SharedHelpers).to receive(:find_gemfile).and_return(bundled_app_gemfile)
        end

        it "should not eagerly unlock shared dependency with bundle install conservative updating behavior" do
          updated_deps_in_gemfile = [Bundler::Dependency.new("isolated_owner", ">= 0"),
                                     Bundler::Dependency.new("shared_owner_a", "3.0.2"),
                                     Bundler::Dependency.new("shared_owner_b", ">= 0")]
          unlock_hash_for_bundle_install = {}
          definition = Bundler::Definition.new(
            bundled_app_lock,
            updated_deps_in_gemfile,
            source_list,
            unlock_hash_for_bundle_install
          )
          locked = definition.send(:converge_locked_specs).map(&:name)
          expect(locked).to include "shared_dep"
        end

        it "should not eagerly unlock shared dependency with bundle update conservative updating behavior" do
          updated_deps_in_gemfile = [Bundler::Dependency.new("isolated_owner", ">= 0"),
                                     Bundler::Dependency.new("shared_owner_a", ">= 0"),
                                     Bundler::Dependency.new("shared_owner_b", ">= 0")]
          definition = Bundler::Definition.new(
            bundled_app_lock,
            updated_deps_in_gemfile,
            source_list,
            gems: ["shared_owner_a"], conservative: true
          )
          locked = definition.send(:converge_locked_specs).map(&:name)
          expect(locked).to eq %w[isolated_dep isolated_owner shared_dep shared_owner_b]
          expect(locked.include?("shared_dep")).to be_truthy
        end
      end
    end
  end

  def mock_source_list
    Class.new do
      def all_sources
        []
      end

      def path_sources
        []
      end

      def rubygems_remotes
        []
      end

      def replace_sources!(arg)
        nil
      end
    end.new
  end
end
