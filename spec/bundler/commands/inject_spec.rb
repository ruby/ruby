# frozen_string_literal: true

RSpec.describe "bundle inject", bundler: "< 3" do
  before :each do
    gemfile <<-G
      source "https://gem.repo1"
      gem "myrack"
    G
  end

  context "without a lockfile" do
    it "locks with the injected gems" do
      expect(bundled_app_lock).not_to exist
      bundle "inject 'myrack-obama' '> 0'"
      expect(bundled_app_lock.read).to match(/myrack-obama/)
    end
  end

  context "with a lockfile" do
    before do
      bundle "install"
    end

    it "adds the injected gems to the Gemfile" do
      expect(bundled_app_gemfile.read).not_to match(/myrack-obama/)
      bundle "inject 'myrack-obama' '> 0'"
      expect(bundled_app_gemfile.read).to match(/myrack-obama/)
    end

    it "locks with the injected gems" do
      expect(bundled_app_lock.read).not_to match(/myrack-obama/)
      bundle "inject 'myrack-obama' '> 0'"
      expect(bundled_app_lock.read).to match(/myrack-obama/)
    end
  end

  context "with injected gems already in the Gemfile" do
    it "doesn't add existing gems" do
      bundle "inject 'myrack' '> 0'", raise_on_error: false
      expect(err).to match(/cannot specify the same gem twice/i)
    end
  end

  context "incorrect arguments" do
    it "fails when more than 2 arguments are passed" do
      bundle "inject gem_name 1 v", raise_on_error: false
      expect(err).to eq(<<-E.strip)
ERROR: "bundle inject" was called with arguments ["gem_name", "1", "v"]
Usage: "bundle inject GEM VERSION"
      E
    end
  end

  context "with source option" do
    it "add gem with source option in gemfile" do
      bundle "inject 'foo' '>0' --source https://gem.repo1"
      gemfile = bundled_app_gemfile.read
      str = "gem \"foo\", \"> 0\", :source => \"https://gem.repo1\""
      expect(gemfile).to include str
    end
  end

  context "with group option" do
    it "add gem with group option in gemfile" do
      bundle "inject 'myrack-obama' '>0' --group=development"
      gemfile = bundled_app_gemfile.read
      str = "gem \"myrack-obama\", \"> 0\", :group => :development"
      expect(gemfile).to include str
    end

    it "add gem with multiple groups in gemfile" do
      bundle "inject 'myrack-obama' '>0' --group=development,test"
      gemfile = bundled_app_gemfile.read
      str = "gem \"myrack-obama\", \"> 0\", :groups => [:development, :test]"
      expect(gemfile).to include str
    end
  end

  context "when frozen" do
    before do
      bundle "install"
      if Bundler.feature_flag.bundler_3_mode?
        bundle "config set --local deployment true"
      else
        bundle "config set --local frozen true"
      end
    end

    it "injects anyway" do
      bundle "inject 'myrack-obama' '> 0'"
      expect(bundled_app_gemfile.read).to match(/myrack-obama/)
    end

    it "locks with the injected gems" do
      expect(bundled_app_lock.read).not_to match(/myrack-obama/)
      bundle "inject 'myrack-obama' '> 0'"
      expect(bundled_app_lock.read).to match(/myrack-obama/)
    end

    it "restores frozen afterwards" do
      bundle "inject 'myrack-obama' '> 0'"
      config = Psych.load(bundled_app(".bundle/config").read)
      expect(config["BUNDLE_DEPLOYMENT"] || config["BUNDLE_FROZEN"]).to eq("true")
    end

    it "doesn't allow Gemfile changes" do
      gemfile <<-G
        source "https://gem.repo1"
        gem "myrack-obama"
      G
      bundle "inject 'myrack' '> 0'", raise_on_error: false
      expect(err).to match(/the lockfile can't be updated because frozen mode is set/)

      expect(bundled_app_lock.read).not_to match(/myrack-obama/)
    end
  end
end
