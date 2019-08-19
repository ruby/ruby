# frozen_string_literal: true

RSpec.describe "bundle inject", :bundler => "< 2" do
  before :each do
    gemfile <<-G
      source "file://#{gem_repo1}"
      gem "rack"
    G
  end

  context "without a lockfile" do
    it "locks with the injected gems" do
      expect(bundled_app("Gemfile.lock")).not_to exist
      bundle "inject 'rack-obama' '> 0'"
      expect(bundled_app("Gemfile.lock").read).to match(/rack-obama/)
    end
  end

  context "with a lockfile" do
    before do
      bundle "install"
    end

    it "adds the injected gems to the Gemfile" do
      expect(bundled_app("Gemfile").read).not_to match(/rack-obama/)
      bundle "inject 'rack-obama' '> 0'"
      expect(bundled_app("Gemfile").read).to match(/rack-obama/)
    end

    it "locks with the injected gems" do
      expect(bundled_app("Gemfile.lock").read).not_to match(/rack-obama/)
      bundle "inject 'rack-obama' '> 0'"
      expect(bundled_app("Gemfile.lock").read).to match(/rack-obama/)
    end
  end

  context "with injected gems already in the Gemfile" do
    it "doesn't add existing gems" do
      bundle "inject 'rack' '> 0'"
      expect(out).to match(/cannot specify the same gem twice/i)
    end
  end

  context "incorrect arguments" do
    it "fails when more than 2 arguments are passed" do
      bundle "inject gem_name 1 v"
      expect(out).to eq(<<-E.strip)
ERROR: "bundle inject" was called with arguments ["gem_name", "1", "v"]
Usage: "bundle inject GEM VERSION"
      E
    end
  end

  context "with source option" do
    it "add gem with source option in gemfile" do
      bundle "inject 'foo' '>0' --source file://#{gem_repo1}"
      gemfile = bundled_app("Gemfile").read
      str = "gem \"foo\", \"> 0\", :source => \"file://#{gem_repo1}\""
      expect(gemfile).to include str
    end
  end

  context "with group option" do
    it "add gem with group option in gemfile" do
      bundle "inject 'rack-obama' '>0' --group=development"
      gemfile = bundled_app("Gemfile").read
      str = "gem \"rack-obama\", \"> 0\", :group => :development"
      expect(gemfile).to include str
    end

    it "add gem with multiple groups in gemfile" do
      bundle "inject 'rack-obama' '>0' --group=development,test"
      gemfile = bundled_app("Gemfile").read
      str = "gem \"rack-obama\", \"> 0\", :groups => [:development, :test]"
      expect(gemfile).to include str
    end
  end

  context "when frozen" do
    before do
      bundle "install"
      if Bundler.feature_flag.bundler_2_mode?
        bundle! "config --local deployment true"
      else
        bundle! "config --local frozen true"
      end
    end

    it "injects anyway" do
      bundle "inject 'rack-obama' '> 0'"
      expect(bundled_app("Gemfile").read).to match(/rack-obama/)
    end

    it "locks with the injected gems" do
      expect(bundled_app("Gemfile.lock").read).not_to match(/rack-obama/)
      bundle "inject 'rack-obama' '> 0'"
      expect(bundled_app("Gemfile.lock").read).to match(/rack-obama/)
    end

    it "restores frozen afterwards" do
      bundle "inject 'rack-obama' '> 0'"
      config = YAML.load(bundled_app(".bundle/config").read)
      expect(config["BUNDLE_DEPLOYMENT"] || config["BUNDLE_FROZEN"]).to eq("true")
    end

    it "doesn't allow Gemfile changes" do
      gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack-obama"
      G
      bundle "inject 'rack' '> 0'"
      expect(out).to match(/trying to install in deployment mode after changing/)

      expect(bundled_app("Gemfile.lock").read).not_to match(/rack-obama/)
    end
  end
end
