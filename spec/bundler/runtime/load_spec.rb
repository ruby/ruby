# frozen_string_literal: true

RSpec.describe "Bundler.load" do
  describe "with a gemfile" do
    before(:each) do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack"
      G
      allow(Bundler::SharedHelpers).to receive(:pwd).and_return(bundled_app)
    end

    it "provides a list of the env dependencies" do
      expect(Bundler.load.dependencies).to have_dep("rack", ">= 0")
    end

    it "provides a list of the resolved gems" do
      expect(Bundler.load.gems).to have_gem("rack-1.0.0", "bundler-#{Bundler::VERSION}")
    end

    it "ignores blank BUNDLE_GEMFILEs" do
      expect do
        ENV["BUNDLE_GEMFILE"] = ""
        Bundler.load
      end.not_to raise_error
    end
  end

  describe "with a gems.rb file" do
    before(:each) do
      create_file "gems.rb", <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack"
      G
      bundle :install
      allow(Bundler::SharedHelpers).to receive(:pwd).and_return(bundled_app)
    end

    it "provides a list of the env dependencies" do
      expect(Bundler.load.dependencies).to have_dep("rack", ">= 0")
    end

    it "provides a list of the resolved gems" do
      expect(Bundler.load.gems).to have_gem("rack-1.0.0", "bundler-#{Bundler::VERSION}")
    end
  end

  describe "without a gemfile" do
    it "raises an exception if the default gemfile is not found" do
      expect do
        Bundler.load
      end.to raise_error(Bundler::GemfileNotFound, /could not locate gemfile/i)
    end

    it "raises an exception if a specified gemfile is not found" do
      expect do
        ENV["BUNDLE_GEMFILE"] = "omg.rb"
        Bundler.load
      end.to raise_error(Bundler::GemfileNotFound, /omg\.rb/)
    end

    it "does not find a Gemfile above the testing directory" do
      bundler_gemfile = Pathname.new(__dir__).join("../../Gemfile")
      unless File.exist?(bundler_gemfile)
        FileUtils.touch(bundler_gemfile)
        @remove_bundler_gemfile = true
      end
      begin
        expect { Bundler.load }.to raise_error(Bundler::GemfileNotFound)
      ensure
        bundler_gemfile.rmtree if @remove_bundler_gemfile
      end
    end
  end

  describe "when called twice" do
    it "doesn't try to load the runtime twice" do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "rack"
        gem "activesupport", :group => :test
      G

      ruby <<-RUBY
        require "#{lib_dir}/bundler"
        Bundler.setup :default
        Bundler.require :default
        puts RACK
        begin
          require "activesupport"
        rescue LoadError
          puts "no activesupport"
        end
      RUBY

      expect(out.split("\n")).to eq(["1.0.0", "no activesupport"])
    end
  end

  describe "not hurting brittle rubygems" do
    it "does not inject #source into the generated YAML of the gem specs" do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gem "activerecord"
      G
      allow(Bundler::SharedHelpers).to receive(:find_gemfile).and_return(bundled_app_gemfile)
      Bundler.load.specs.each do |spec|
        expect(spec.to_yaml).not_to match(/^\s+source:/)
        expect(spec.to_yaml).not_to match(/^\s+groups:/)
      end
    end
  end
end
