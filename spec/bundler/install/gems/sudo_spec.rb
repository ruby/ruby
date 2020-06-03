# frozen_string_literal: true

RSpec.describe "when using sudo", :sudo => true do
  describe "and BUNDLE_PATH is writable" do
    context "but BUNDLE_PATH/build_info is not writable" do
      let(:subdir) do
        system_gem_path("cache")
      end

      before do
        bundle "config set path.system true"
        subdir.mkpath
        sudo "chmod u-w #{subdir}"
      end

      after do
        sudo "chmod u+w #{subdir}"
      end

      it "installs" do
        install_gemfile <<-G
          source "#{file_uri_for(gem_repo1)}"
          gem "rack"
        G

        expect(out).to_not match(/an error occurred/i)
        expect(system_gem_path("cache/rack-1.0.0.gem")).to exist
        expect(the_bundle).to include_gems "rack 1.0"
      end
    end
  end

  describe "and GEM_HOME is owned by root" do
    before :each do
      bundle "config set path.system true"
      chown_system_gems_to_root
    end

    it "installs" do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack", '1.0'
        gem "thin"
      G

      expect(system_gem_path("gems/rack-1.0.0")).to exist
      expect(system_gem_path("gems/rack-1.0.0").stat.uid).to eq(0)
      expect(the_bundle).to include_gems "rack 1.0"
    end

    it "installs rake and a gem dependent on rake in the same session" do
      gemfile <<-G
          source "#{file_uri_for(gem_repo1)}"
          gem "rake"
          gem "another_implicit_rake_dep"
      G
      bundle "install"
      expect(system_gem_path("gems/another_implicit_rake_dep-1.0")).to exist
    end

    it "installs when BUNDLE_PATH is owned by root" do
      bundle_path = tmp("owned_by_root")
      FileUtils.mkdir_p bundle_path
      sudo "chown -R root #{bundle_path}"

      ENV["BUNDLE_PATH"] = bundle_path.to_s
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack", '1.0'
      G

      expect(bundle_path.join(Bundler.ruby_scope, "gems/rack-1.0.0")).to exist
      expect(bundle_path.join(Bundler.ruby_scope, "gems/rack-1.0.0").stat.uid).to eq(0)
      expect(the_bundle).to include_gems "rack 1.0"
    end

    it "installs when BUNDLE_PATH does not exist" do
      root_path = tmp("owned_by_root")
      FileUtils.mkdir_p root_path
      sudo "chown -R root #{root_path}"
      bundle_path = root_path.join("does_not_exist")

      ENV["BUNDLE_PATH"] = bundle_path.to_s
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack", '1.0'
      G

      expect(bundle_path.join(Bundler.ruby_scope, "gems/rack-1.0.0")).to exist
      expect(bundle_path.join(Bundler.ruby_scope, "gems/rack-1.0.0").stat.uid).to eq(0)
      expect(the_bundle).to include_gems "rack 1.0"
    end

    it "installs extensions/" do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "very_simple_binary"
      G

      expect(system_gem_path("gems/very_simple_binary-1.0")).to exist
      binary_glob = system_gem_path("extensions/*/*/very_simple_binary-1.0")
      expect(Dir.glob(binary_glob).first).to be
    end
  end

  describe "and BUNDLE_PATH is not writable" do
    before do
      bundle "config set --local path .bundle"
      sudo "chmod ugo-w .bundle"
    end

    after do
      sudo "chmod ugo+w .bundle"
    end

    it "installs" do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack", '1.0'
      G

      expect(local_gem_path("gems/rack-1.0.0")).to exist
      expect(the_bundle).to include_gems "rack 1.0"
    end

    it "cleans up the tmpdirs generated" do
      require "tmpdir"
      Dir.glob("#{Dir.tmpdir}/bundler*").each do |tmpdir|
        FileUtils.remove_entry_secure(tmpdir)
      end

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack"
      G
      tmpdirs = Dir.glob("#{Dir.tmpdir}/bundler*")

      expect(tmpdirs).to be_empty
    end
  end

  describe "and GEM_HOME is not writable" do
    it "installs" do
      bundle "config set path.system true"
      gem_home = tmp("sudo_gem_home")
      sudo "mkdir -p #{gem_home}"
      sudo "chmod ugo-w #{gem_home}"

      system_gems :bundler, :path => gem_home

      gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack", '1.0'
      G

      bundle :install, :env => { "GEM_HOME" => gem_home.to_s, "GEM_PATH" => nil }
      expect(gem_home.join("bin/rackup")).to exist
      expect(the_bundle).to include_gems "rack 1.0", :env => { "GEM_HOME" => gem_home.to_s, "GEM_PATH" => nil }

      sudo "rm -rf #{tmp("sudo_gem_home")}"
    end
  end

  describe "and root runs install" do
    let(:warning) { "Don't run Bundler as root." }

    before do
      gemfile %(source "#{file_uri_for(gem_repo1)}")
    end

    it "warns against that" do
      bundle :install, :sudo => :preserve_env
      expect(err).to include(warning)
    end

    context "when ENV['BUNDLE_SILENCE_ROOT_WARNING'] is set" do
      it "skips the warning" do
        bundle :install, :sudo => :preserve_env, :env => { "BUNDLE_SILENCE_ROOT_WARNING" => "true" }
        expect(err).to_not include(warning)
      end
    end

    context "when silence_root_warning = false" do
      it "warns against that" do
        bundle :install, :sudo => :preserve_env, :env => { "BUNDLE_SILENCE_ROOT_WARNING" => "false" }
        expect(err).to include(warning)
      end
    end
  end
end
