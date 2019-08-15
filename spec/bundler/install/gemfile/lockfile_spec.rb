# frozen_string_literal: true

RSpec.describe "bundle install with a lockfile present" do
  let(:gf) { <<-G }
    source "#{file_uri_for(gem_repo1)}"

    gem "rack", "1.0.0"
  G

  subject do
    install_gemfile(gf)
  end

  context "gemfile evaluation" do
    let(:gf) { super() + "\n\n File.open('evals', 'a') {|f| f << %(1\n) } unless ENV['BUNDLER_SPEC_NO_APPEND']" }

    context "with plugins disabled" do
      before do
        bundle! "config set plugins false"
        subject
      end

      it "does not evaluate the gemfile twice" do
        bundle! :install

        with_env_vars("BUNDLER_SPEC_NO_APPEND" => "1") { expect(the_bundle).to include_gem "rack 1.0.0" }

        # The first eval is from the initial install, we're testing that the
        # second install doesn't double-eval
        expect(bundled_app("evals").read.lines.to_a.size).to eq(2)
      end

      context "when the gem is not installed" do
        before { FileUtils.rm_rf ".bundle" }

        it "does not evaluate the gemfile twice" do
          bundle! :install

          with_env_vars("BUNDLER_SPEC_NO_APPEND" => "1") { expect(the_bundle).to include_gem "rack 1.0.0" }

          # The first eval is from the initial install, we're testing that the
          # second install doesn't double-eval
          expect(bundled_app("evals").read.lines.to_a.size).to eq(2)
        end
      end
    end
  end
end
