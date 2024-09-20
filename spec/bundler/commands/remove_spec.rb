# frozen_string_literal: true

RSpec.describe "bundle remove" do
  context "when no gems are specified" do
    it "throws error" do
      gemfile <<-G
        source "https://gem.repo1"
      G

      bundle "remove", raise_on_error: false

      expect(err).to include("Please specify gems to remove.")
    end
  end

  context "after 'bundle install' is run" do
    describe "running 'bundle remove GEM_NAME'" do
      it "removes it from the lockfile" do
        myrack_dep = <<~L

          DEPENDENCIES
            myrack

        L

        gemfile <<-G
          source "https://gem.repo1"

          gem "myrack"
        G

        bundle "install"

        expect(lockfile).to include(myrack_dep)

        bundle "remove myrack"

        expect(gemfile).to eq <<~G
          source "https://gem.repo1"
        G
        expect(lockfile).to_not include(myrack_dep)
      end
    end
  end

  context "when --install flag is specified", bundler: "< 3" do
    it "removes gems from .bundle" do
      gemfile <<-G
        source "https://gem.repo1"

        gem "myrack"
      G

      bundle "remove myrack --install"

      expect(out).to include("myrack was removed.")
      expect(the_bundle).to_not include_gems "myrack"
    end
  end

  describe "remove single gem from gemfile" do
    context "when gem is present in gemfile" do
      it "shows success for removed gem" do
        gemfile <<-G
          source "https://gem.repo1"

          gem "myrack"
        G

        bundle "remove myrack"

        expect(out).to include("myrack was removed.")
        expect(the_bundle).to_not include_gems "myrack"
        expect(gemfile).to eq <<~G
          source "https://gem.repo1"
        G
      end

      context "when gem is specified in multiple lines" do
        it "shows success for removed gem" do
          build_git "myrack"

          gemfile <<-G
            source 'https://gem.repo1'

            gem 'git'
            gem 'myrack',
                git: "#{lib_path("myrack-1.0")}",
                branch: 'main'
            gem 'nokogiri'
          G

          bundle "remove myrack"

          expect(out).to include("myrack was removed.")
          expect(gemfile).to eq <<~G
            source 'https://gem.repo1'

            gem 'git'
            gem 'nokogiri'
          G
        end
      end
    end

    context "when gem is not present in gemfile" do
      it "shows warning for gem that could not be removed" do
        gemfile <<-G
          source "https://gem.repo1"
        G

        bundle "remove myrack", raise_on_error: false

        expect(err).to include("`myrack` is not specified in #{bundled_app_gemfile} so it could not be removed.")
      end
    end
  end

  describe "remove multiple gems from gemfile" do
    context "when all gems are present in gemfile" do
      it "shows success fir all removed gems" do
        gemfile <<-G
          source "https://gem.repo1"

          gem "myrack"
          gem "rails"
        G

        bundle "remove myrack rails"

        expect(out).to include("myrack was removed.")
        expect(out).to include("rails was removed.")
        expect(gemfile).to eq <<~G
        source "https://gem.repo1"
        G
      end
    end

    context "when some gems are not present in the gemfile" do
      it "shows warning for those not present and success for those that can be removed" do
        gemfile <<-G
          source "https://gem.repo1"

          gem "rails"
          gem "minitest"
          gem "rspec"
        G

        bundle "remove rails myrack minitest", raise_on_error: false

        expect(err).to include("`myrack` is not specified in #{bundled_app_gemfile} so it could not be removed.")
        expect(gemfile).to eq <<~G
          source "https://gem.repo1"

          gem "rails"
          gem "minitest"
          gem "rspec"
        G
      end
    end
  end

  context "with inline groups" do
    it "removes the specified gem" do
      gemfile <<-G
        source "https://gem.repo1"

        gem "myrack", :group => [:dev]
      G

      bundle "remove myrack"

      expect(out).to include("myrack was removed.")
      expect(gemfile).to eq <<~G
        source "https://gem.repo1"
      G
    end
  end

  describe "with group blocks" do
    context "when single group block with gem to be removed is present" do
      it "removes the group block" do
        gemfile <<-G
          source "https://gem.repo1"

          group :test do
            gem "rspec"
          end
        G

        bundle "remove rspec"

        expect(out).to include("rspec was removed.")
        expect(gemfile).to eq <<~G
          source "https://gem.repo1"
        G
      end
    end

    context "when gem to be removed is outside block" do
      it "does not modify group" do
        gemfile <<-G
          source "https://gem.repo1"

          gem "myrack"
          group :test do
            gem "coffee-script-source"
          end
        G

        bundle "remove myrack"

        expect(out).to include("myrack was removed.")
        expect(gemfile).to eq <<~G
          source "https://gem.repo1"

          group :test do
            gem "coffee-script-source"
          end
        G
      end
    end

    context "when an empty block is also present" do
      it "removes all empty blocks" do
        gemfile <<-G
          source "https://gem.repo1"

          group :test do
            gem "rspec"
          end

          group :dev do
          end
        G

        bundle "remove rspec"

        expect(out).to include("rspec was removed.")
        expect(gemfile).to eq <<~G
          source "https://gem.repo1"
        G
      end
    end

    context "when the gem belongs to multiple groups" do
      it "removes the groups" do
        gemfile <<-G
          source "https://gem.repo1"

          group :test, :serioustest do
            gem "rspec"
          end
        G

        bundle "remove rspec"

        expect(out).to include("rspec was removed.")
        expect(gemfile).to eq <<~G
          source "https://gem.repo1"
        G
      end
    end

    context "when the gem is present in multiple groups" do
      it "removes all empty blocks" do
        gemfile <<-G
          source "https://gem.repo1"

          group :one do
            gem "rspec"
          end

          group :two do
            gem "rspec"
          end
        G

        bundle "remove rspec"

        expect(out).to include("rspec was removed.")
        expect(gemfile).to eq <<~G
          source "https://gem.repo1"
        G
      end
    end
  end

  describe "nested group blocks" do
    context "when all the groups will be empty after removal" do
      it "removes the empty nested blocks" do
        gemfile <<-G
          source "https://gem.repo1"

          group :test do
            group :serioustest do
              gem "rspec"
            end
          end
        G

        bundle "remove rspec"

        expect(out).to include("rspec was removed.")
        expect(gemfile).to eq <<~G
          source "https://gem.repo1"
        G
      end
    end

    context "when outer group will not be empty after removal" do
      it "removes only empty blocks" do
        install_gemfile <<-G
          source "https://gem.repo1"

          group :test do
            gem "myrack-test"

            group :serioustest do
              gem "rspec"
            end
          end
        G

        bundle "remove rspec"

        expect(out).to include("rspec was removed.")
        expect(gemfile).to eq <<~G
          source "https://gem.repo1"

          group :test do
            gem "myrack-test"

          end
        G
      end
    end

    context "when inner group will not be empty after removal" do
      it "removes only empty blocks" do
        install_gemfile <<-G
          source "https://gem.repo1"

          group :test do
            group :serioustest do
              gem "rspec"
              gem "myrack-test"
            end
          end
        G

        bundle "remove rspec"

        expect(out).to include("rspec was removed.")
        expect(gemfile).to eq <<~G
          source "https://gem.repo1"

          group :test do
            group :serioustest do
              gem "myrack-test"
            end
          end
        G
      end
    end
  end

  describe "arbitrary gemfile" do
    context "when multiple gems are present in same line" do
      it "shows warning for gems not removed" do
        install_gemfile <<-G
          source "https://gem.repo1"
          gem "myrack"; gem "rails"
        G

        bundle "remove rails", raise_on_error: false

        expect(err).to include("Gems could not be removed. myrack (>= 0) would also have been removed.")
        expect(gemfile).to eq <<~G
          source "https://gem.repo1"
          gem "myrack"; gem "rails"
        G
      end
    end

    context "when some gems could not be removed" do
      it "shows warning for gems not removed and success for those removed" do
        install_gemfile <<-G, raise_on_error: false
          source "https://gem.repo1"
          gem"myrack"
          gem"rspec"
          gem "rails"
          gem "minitest"
        G

        bundle "remove rails myrack rspec minitest"

        expect(out).to include("rails was removed.")
        expect(out).to include("minitest was removed.")
        expect(out).to include("myrack, rspec could not be removed.")
        expect(gemfile).to eq <<~G
          source "https://gem.repo1"
          gem"myrack"
          gem"rspec"
        G
      end
    end
  end

  context "with sources" do
    before do
      build_repo3 do
        build_gem "rspec"
      end
    end

    it "removes gems and empty source blocks" do
      gemfile <<-G
        source "https://gem.repo1"

        gem "myrack"

        source "https://gem.repo3" do
          gem "rspec"
        end
      G

      bundle "install"

      bundle "remove rspec"

      expect(out).to include("rspec was removed.")
      expect(gemfile).to eq <<~G
        source "https://gem.repo1"

        gem "myrack"
      G
    end
  end

  describe "with eval_gemfile" do
    context "when gems are present in both gemfiles" do
      it "removes the gems" do
        gemfile "Gemfile-other", <<-G
          gem "myrack"
        G

        install_gemfile <<-G
          source "https://gem.repo1"

          eval_gemfile "Gemfile-other"

          gem "myrack"
        G

        bundle "remove myrack"

        expect(out).to include("myrack was removed.")
      end
    end

    context "when gems are present in other gemfile" do
      it "removes the gems" do
        gemfile "Gemfile-other", <<-G
          gem "myrack"
        G

        install_gemfile <<-G
          source "https://gem.repo1"

          eval_gemfile "Gemfile-other"
        G

        bundle "remove myrack"

        expect(bundled_app("Gemfile-other").read).to_not include("gem \"myrack\"")
        expect(out).to include("myrack was removed.")
      end
    end

    context "when gems to be removed are not specified in any of the gemfiles" do
      it "throws error for the gems not present" do
        # an empty gemfile
        # indicating the gem is not present in the gemfile
        create_file "Gemfile-other", <<-G
        G

        install_gemfile <<-G
          source "https://gem.repo1"

          eval_gemfile "Gemfile-other"
        G

        bundle "remove myrack", raise_on_error: false

        expect(err).to include("`myrack` is not specified in #{bundled_app_gemfile} so it could not be removed.")
      end
    end

    context "when the gem is present in parent file but not in gemfile specified by eval_gemfile" do
      it "removes the gem" do
        gemfile "Gemfile-other", <<-G
          gem "rails"
        G

        install_gemfile <<-G
          source "https://gem.repo1"

          eval_gemfile "Gemfile-other"
          gem "myrack"
        G

        bundle "remove myrack", raise_on_error: false

        expect(out).to include("myrack was removed.")
        expect(err).to include("`myrack` is not specified in #{bundled_app("Gemfile-other")} so it could not be removed.")
        expect(gemfile).to eq <<~G
          source "https://gem.repo1"

          eval_gemfile "Gemfile-other"
        G
      end
    end

    context "when gems cannot be removed from other gemfile" do
      it "shows error" do
        gemfile "Gemfile-other", <<-G
          gem "rails"; gem "myrack"
        G

        install_gemfile <<-G
          source "https://gem.repo1"

          eval_gemfile "Gemfile-other"
          gem "myrack"
        G

        bundle "remove myrack", raise_on_error: false

        expect(out).to include("myrack was removed.")
        expect(err).to include("Gems could not be removed. rails (>= 0) would also have been removed.")
        expect(gemfile).to eq <<~G
          source "https://gem.repo1"

          eval_gemfile "Gemfile-other"
        G
      end
    end

    context "when gems could not be removed from parent gemfile" do
      it "shows error" do
        gemfile "Gemfile-other", <<-G
          gem "myrack"
        G

        install_gemfile <<-G
          source "https://gem.repo1"

          eval_gemfile "Gemfile-other"
          gem "rails"; gem "myrack"
        G

        bundle "remove myrack", raise_on_error: false

        expect(err).to include("Gems could not be removed. rails (>= 0) would also have been removed.")
        expect(bundled_app("Gemfile-other").read).to include("gem \"myrack\"")
        expect(gemfile).to eq <<~G
          source "https://gem.repo1"

          eval_gemfile "Gemfile-other"
          gem "rails"; gem "myrack"
        G
      end
    end

    context "when gem present in gemfiles but could not be removed from one from one of them" do
      it "removes gem which can be removed and shows warning for file from which it cannot be removed" do
        gemfile "Gemfile-other", <<-G
          gem "myrack"
        G

        install_gemfile <<-G
          source "https://gem.repo1"

          eval_gemfile "Gemfile-other"
          gem"myrack"
        G

        bundle "remove myrack"

        expect(out).to include("myrack was removed.")
        expect(bundled_app("Gemfile-other").read).to_not include("gem \"myrack\"")
      end
    end
  end

  context "with install_if" do
    it "removes gems inside blocks and empty blocks" do
      install_gemfile <<-G
        source "https://gem.repo1"

        install_if(lambda { false }) do
          gem "myrack"
        end
      G

      bundle "remove myrack"

      expect(out).to include("myrack was removed.")
      expect(gemfile).to eq <<~G
        source "https://gem.repo1"
      G
    end
  end

  context "with env" do
    it "removes gems inside blocks and empty blocks" do
      install_gemfile <<-G
        source "https://gem.repo1"

        env "BUNDLER_TEST" do
          gem "myrack"
        end
      G

      bundle "remove myrack"

      expect(out).to include("myrack was removed.")
      expect(gemfile).to eq <<~G
        source "https://gem.repo1"
      G
    end
  end

  context "with gemspec" do
    it "should not remove the gem" do
      build_lib("foo", path: tmp("foo")) do |s|
        s.write("foo.gemspec", "")
        s.add_dependency "myrack"
      end

      install_gemfile(<<-G)
        source "https://gem.repo1"
        gemspec :path => '#{tmp("foo")}', :name => 'foo'
      G

      bundle "remove foo"

      expect(out).to include("foo could not be removed.")
    end
  end

  describe "with comments that mention gems" do
    context "when comment is a separate line comment" do
      it "does not remove the line comment" do
        gemfile <<-G
          source "https://gem.repo1"

          # gem "myrack" might be used in the future
          gem "myrack"
        G

        bundle "remove myrack"

        expect(out).to include("myrack was removed.")
        expect(gemfile).to eq <<~G
          source "https://gem.repo1"

          # gem "myrack" might be used in the future
        G
      end
    end

    context "when gem specified for removal has an inline comment" do
      it "removes the inline comment" do
        gemfile <<-G
          source "https://gem.repo1"

          gem "myrack" # this can be removed
        G

        bundle "remove myrack"

        expect(out).to include("myrack was removed.")
        expect(gemfile).to eq <<~G
          source "https://gem.repo1"
        G
      end
    end

    context "when gem specified for removal is mentioned in other gem's comment" do
      it "does not remove other gem" do
        gemfile <<-G
          source "https://gem.repo1"
          gem "puma" # implements interface provided by gem "myrack"

          gem "myrack"
        G

        bundle "remove myrack"

        expect(out).to_not include("puma was removed.")
        expect(out).to include("myrack was removed.")
        expect(gemfile).to eq <<~G
          source "https://gem.repo1"
          gem "puma" # implements interface provided by gem "myrack"
        G
      end
    end

    context "when gem specified for removal has a comment that mentions other gem" do
      it "does not remove other gem" do
        gemfile <<-G
          source "https://gem.repo1"
          gem "puma" # implements interface provided by gem "myrack"

          gem "myrack"
        G

        bundle "remove puma"

        expect(out).to include("puma was removed.")
        expect(out).to_not include("myrack was removed.")
        expect(gemfile).to eq <<~G
          source "https://gem.repo1"

          gem "myrack"
        G
      end
    end
  end
end
