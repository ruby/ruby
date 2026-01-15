# frozen_string_literal: true

RSpec.describe "bundle install with a lockfile present" do
  let(:gf) { <<-G }
    source "https://gem.repo1"

    gem "myrack", "1.0.0"
  G

  it "touches the lockfile on install even when nothing has changed" do
    install_gemfile(gf)
    expect { bundle :install }.to change { bundled_app_lock.mtime }
  end

  context "gemfile evaluation" do
    let(:gf) { super() + "\n\n File.open('evals', 'a') {|f| f << %(1\n) } unless ENV['BUNDLER_SPEC_NO_APPEND']" }

    context "with plugins disabled" do
      before do
        bundle "config set plugins false"
      end

      it "does not evaluate the gemfile twice when the gem is already installed" do
        install_gemfile(gf)
        bundle :install

        with_env_vars("BUNDLER_SPEC_NO_APPEND" => "1") { expect(the_bundle).to include_gem "myrack 1.0.0" }

        expect(bundled_app("evals").read.lines.to_a.size).to eq(2)
      end

      it "does not evaluate the gemfile twice when the gem is not installed" do
        gemfile(gf)
        bundle :install

        with_env_vars("BUNDLER_SPEC_NO_APPEND" => "1") { expect(the_bundle).to include_gem "myrack 1.0.0" }

        expect(bundled_app("evals").read.lines.to_a.size).to eq(1)
      end
    end
  end
end
