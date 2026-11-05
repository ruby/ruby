# frozen_string_literal: true

RSpec.describe "bundle install" do
  let(:env) { { "BUNDLER_GEM_DEFAULT_DIR" => system_gem_path.to_s } }

  before do
    build_gem "foo", "2.0", to_system: true, default: true
    build_repo4 do
      build_gem "foo", "1.0"
      build_gem "foo", "2.0"
      build_gem "bar", "1.0" do |s|
        s.add_dependency "foo", "1.0"
      end
    end
  end

  it "warns about older gems when installing" do
    install_gemfile <<~G, env: env
      source "https://gem.repo4"
      gem "bar", "1.0"
    G

    expect(err).to include("foo 1.0 (default: 2.0)")
    expect(the_bundle).to include_gems("bar 1.0", "foo 1.0")
  end

  it "warns before installing, so that the warning is shown even if the installation fails" do
    gem_repo4("gems", "foo-1.0.gem").write("not a gem")
    install_gemfile <<~G, env: env, raise_on_error: false
      source "https://gem.repo4"
      gem "foo", "1.0"
    G

    expect(err).to include("foo 1.0 (default: 2.0)")
    expect(last_command).to be_failure
  end

  it "does not warn about gems at the default gem version" do
    install_gemfile <<~G, env: env
      source "https://gem.repo4"
      gem "foo", "2.0"
    G

    expect(err).to be_empty
  end
end
