# frozen_string_literal: true

require "rubygems/security"

# unfortunately, testing signed gems with a provided CA is extremely difficult
# as 'gem cert' is currently the only way to add CAs to the system.

RSpec.describe "policies with unsigned gems" do
  before do
    build_security_repo
    gemfile <<-G
      source "#{file_uri_for(security_repo)}"
      gem "rack"
      gem "signed_gem"
    G
  end

  it "will work after you try to deploy without a lock" do
    bundle "install --deployment", raise_on_error: false
    bundle :install
    expect(the_bundle).to include_gems "rack 1.0", "signed_gem 1.0"
  end

  it "will fail when given invalid security policy" do
    bundle "install --trust-policy=InvalidPolicyName", raise_on_error: false
    expect(err).to include("RubyGems doesn't know about trust policy")
  end

  it "will fail with High Security setting due to presence of unsigned gem" do
    bundle "install --trust-policy=HighSecurity", raise_on_error: false
    expect(err).to include("security policy didn't allow")
  end

  it "will fail with Medium Security setting due to presence of unsigned gem" do
    bundle "install --trust-policy=MediumSecurity", raise_on_error: false
    expect(err).to include("security policy didn't allow")
  end

  it "will succeed with no policy" do
    bundle "install"
  end
end

RSpec.describe "policies with signed gems and no CA" do
  before do
    build_security_repo
    gemfile <<-G
      source "#{file_uri_for(security_repo)}"
      gem "signed_gem"
    G
  end

  it "will fail with High Security setting, gem is self-signed" do
    bundle "install --trust-policy=HighSecurity", raise_on_error: false
    expect(err).to include("security policy didn't allow")
  end

  it "will fail with Medium Security setting, gem is self-signed" do
    bundle "install --trust-policy=MediumSecurity", raise_on_error: false
    expect(err).to include("security policy didn't allow")
  end

  it "will succeed with Low Security setting, low security accepts self signed gem" do
    bundle "install --trust-policy=LowSecurity"
    expect(the_bundle).to include_gems "signed_gem 1.0"
  end

  it "will succeed with no policy" do
    bundle "install"
    expect(the_bundle).to include_gems "signed_gem 1.0"
  end
end
