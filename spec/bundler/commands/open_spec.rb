# frozen_string_literal: true

RSpec.describe "bundle open" do
  before :each do
    install_gemfile <<-G
      source "file://#{gem_repo1}"
      gem "rails"
    G
  end

  it "opens the gem with BUNDLER_EDITOR as highest priority" do
    bundle "open rails", :env => { "EDITOR" => "echo editor", "VISUAL" => "echo visual", "BUNDLER_EDITOR" => "echo bundler_editor" }
    expect(out).to include("bundler_editor #{default_bundle_path("gems", "rails-2.3.2")}")
  end

  it "opens the gem with VISUAL as 2nd highest priority" do
    bundle "open rails", :env => { "EDITOR" => "echo editor", "VISUAL" => "echo visual", "BUNDLER_EDITOR" => "" }
    expect(out).to include("visual #{default_bundle_path("gems", "rails-2.3.2")}")
  end

  it "opens the gem with EDITOR as 3rd highest priority" do
    bundle "open rails", :env => { "EDITOR" => "echo editor", "VISUAL" => "", "BUNDLER_EDITOR" => "" }
    expect(out).to include("editor #{default_bundle_path("gems", "rails-2.3.2")}")
  end

  it "complains if no EDITOR is set" do
    bundle "open rails", :env => { "EDITOR" => "", "VISUAL" => "", "BUNDLER_EDITOR" => "" }
    expect(out).to eq("To open a bundled gem, set $EDITOR or $BUNDLER_EDITOR")
  end

  it "complains if gem not in bundle" do
    bundle "open missing", :env => { "EDITOR" => "echo editor", "VISUAL" => "", "BUNDLER_EDITOR" => "" }
    expect(err).to match(/could not find gem 'missing'/i)
  end

  it "does not blow up if the gem to open does not have a Gemfile" do
    git = build_git "foo"
    ref = git.ref_for("master", 11)

    install_gemfile <<-G
      source "file://#{gem_repo1}"
      gem 'foo', :git => "#{lib_path("foo-1.0")}"
    G

    bundle "open foo", :env => { "EDITOR" => "echo editor", "VISUAL" => "", "BUNDLER_EDITOR" => "" }
    expect(out).to match("editor #{default_bundle_path.join("bundler/gems/foo-1.0-#{ref}")}")
  end

  it "suggests alternatives for similar-sounding gems" do
    bundle "open Rails", :env => { "EDITOR" => "echo editor", "VISUAL" => "", "BUNDLER_EDITOR" => "" }
    expect(err).to match(/did you mean rails\?/i)
  end

  it "opens the gem with short words" do
    bundle "open rec", :env => { "EDITOR" => "echo editor", "VISUAL" => "echo visual", "BUNDLER_EDITOR" => "echo bundler_editor" }

    expect(out).to include("bundler_editor #{default_bundle_path("gems", "activerecord-2.3.2")}")
  end

  it "select the gem from many match gems" do
    env = { "EDITOR" => "echo editor", "VISUAL" => "echo visual", "BUNDLER_EDITOR" => "echo bundler_editor" }
    bundle "open active", :env => env do |input, _, _|
      input.puts "2"
    end

    expect(out).to match(/bundler_editor #{default_bundle_path('gems', 'activerecord-2.3.2')}\z/)
  end

  it "allows selecting exit from many match gems" do
    env = { "EDITOR" => "echo editor", "VISUAL" => "echo visual", "BUNDLER_EDITOR" => "echo bundler_editor" }
    bundle! "open active", :env => env do |input, _, _|
      input.puts "0"
    end
  end

  it "performs an automatic bundle install" do
    gemfile <<-G
      source "file://#{gem_repo1}"
      gem "rails"
      gem "foo"
    G

    bundle "config set auto_install 1"
    bundle "open rails", :env => { "EDITOR" => "echo editor", "VISUAL" => "", "BUNDLER_EDITOR" => "" }
    expect(out).to include("Installing foo 1.0")
  end

  it "opens the editor with a clean env" do
    bundle "open", :env => { "EDITOR" => "sh -c 'env'", "VISUAL" => "", "BUNDLER_EDITOR" => "" }
    expect(out).not_to include("BUNDLE_GEMFILE=")
  end
end
