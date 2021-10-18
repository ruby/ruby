# frozen_string_literal: true

RSpec.describe "bundle remove" do
  context "when no gems are specified" do
    it "throws error" do
      gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
      G

      bundle "remove", raise_on_error: false

      expect(err).to include("Please specify gems to remove.")
    end
  end

  context "after 'bundle install' is run" do
    describe "running 'bundle remove GEM_NAME'" do
      it "removes it from the lockfile" do
        rack_dep = <<~L

          DEPENDENCIES
            rack

        L

        gemfile <<-G
          source "#{file_uri_for(gem_repo1)}"

          gem "rack"
        G

        bundle "install"

        expect(lockfile).to include(rack_dep)

        bundle "remove rack"

        expect(gemfile).to eq <<~G
          source "#{file_uri_for(gem_repo1)}"
        G
        expect(lockfile).to_not include(rack_dep)
      end
    end
  end

  context "when --install flag is specified", bundler: "< 3" do
    it "removes gems from .bundle" do
      gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"

        gem "rack"
      G

      bundle "remove rack --install"

      expect(out).to include("rack was removed.")
      expect(the_bundle).to_not include_gems "rack"
    end
  end

  describe "remove single gem from gemfile" do
    context "when gem is present in gemfile" do
      it "shows success for removed gem" do
        gemfile <<-G
          source "#{file_uri_for(gem_repo1)}"

          gem "rack"
        G

        bundle "remove rack"

        expect(out).to include("rack was removed.")
        expect(the_bundle).to_not include_gems "rack"
        expect(gemfile).to eq <<~G
          source "#{file_uri_for(gem_repo1)}"
        G
      end

      context "when gem is specified in multiple lines" do
        it "shows success for removed gem" do
          build_git "rack"

          gemfile <<-G
            source '#{file_uri_for(gem_repo1)}'

            gem 'git'
            gem 'rack',
                git: "#{lib_path("rack-1.0")}",
                branch: 'main'
            gem 'nokogiri'
          G

          bundle "remove rack"

          expect(out).to include("rack was removed.")
          expect(gemfile).to eq <<~G
            source '#{file_uri_for(gem_repo1)}'

            gem 'git'
            gem 'nokogiri'
          G
        end
      end
    end

    context "when gem is not present in gemfile" do
      it "shows warning for gem that could not be removed" do
        gemfile <<-G
          source "#{file_uri_for(gem_repo1)}"
        G

        bundle "remove rack", raise_on_error: false

        expect(err).to include("`rack` is not specified in #{bundled_app_gemfile} so it could not be removed.")
      end
    end
  end

  describe "remove multiple gems from gemfile" do
    context "when all gems are present in gemfile" do
      it "shows success fir all removed gems" do
        gemfile <<-G
          source "#{file_uri_for(gem_repo1)}"

          gem "rack"
          gem "rails"
        G

        bundle "remove rack rails"

        expect(out).to include("rack was removed.")
        expect(out).to include("rails was removed.")
        expect(gemfile).to eq <<~G
        source "#{file_uri_for(gem_repo1)}"
        G
      end
    end

    context "when some gems are not present in the gemfile" do
      it "shows warning for those not present and success for those that can be removed" do
        gemfile <<-G
          source "#{file_uri_for(gem_repo1)}"

          gem "rails"
          gem "minitest"
          gem "rspec"
        G

        bundle "remove rails rack minitest", raise_on_error: false

        expect(err).to include("`rack` is not specified in #{bundled_app_gemfile} so it could not be removed.")
        expect(gemfile).to eq <<~G
          source "#{file_uri_for(gem_repo1)}"

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
        source "#{file_uri_for(gem_repo1)}"

        gem "rack", :group => [:dev]
      G

      bundle "remove rack"

      expect(out).to include("rack was removed.")
      expect(gemfile).to eq <<~G
        source "#{file_uri_for(gem_repo1)}"
      G
    end
  end

  describe "with group blocks" do
    context "when single group block with gem to be removed is present" do
      it "removes the group block" do
        gemfile <<-G
          source "#{file_uri_for(gem_repo1)}"

          group :test do
            gem "rspec"
          end
        G

        bundle "remove rspec"

        expect(out).to include("rspec was removed.")
        expect(gemfile).to eq <<~G
          source "#{file_uri_for(gem_repo1)}"
        G
      end
    end

    context "when gem to be removed is outside block" do
      it "does not modify group" do
        gemfile <<-G
          source "#{file_uri_for(gem_repo1)}"

          gem "rack"
          group :test do
            gem "coffee-script-source"
          end
        G

        bundle "remove rack"

        expect(out).to include("rack was removed.")
        expect(gemfile).to eq <<~G
          source "#{file_uri_for(gem_repo1)}"

          group :test do
            gem "coffee-script-source"
          end
        G
      end
    end

    context "when an empty block is also present" do
      it "removes all empty blocks" do
        gemfile <<-G
          source "#{file_uri_for(gem_repo1)}"

          group :test do
            gem "rspec"
          end

          group :dev do
          end
        G

        bundle "remove rspec"

        expect(out).to include("rspec was removed.")
        expect(gemfile).to eq <<~G
          source "#{file_uri_for(gem_repo1)}"
        G
      end
    end

    context "when the gem belongs to multiple groups" do
      it "removes the groups" do
        gemfile <<-G
          source "#{file_uri_for(gem_repo1)}"

          group :test, :serioustest do
            gem "rspec"
          end
        G

        bundle "remove rspec"

        expect(out).to include("rspec was removed.")
        expect(gemfile).to eq <<~G
          source "#{file_uri_for(gem_repo1)}"
        G
      end
    end

    context "when the gem is present in multiple groups" do
      it "removes all empty blocks" do
        gemfile <<-G
          source "#{file_uri_for(gem_repo1)}"

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
          source "#{file_uri_for(gem_repo1)}"
        G
      end
    end
  end

  describe "nested group blocks" do
    context "when all the groups will be empty after removal" do
      it "removes the empty nested blocks" do
        gemfile <<-G
          source "#{file_uri_for(gem_repo1)}"

          group :test do
            group :serioustest do
              gem "rspec"
            end
          end
        G

        bundle "remove rspec"

        expect(out).to include("rspec was removed.")
        expect(gemfile).to eq <<~G
          source "#{file_uri_for(gem_repo1)}"
        G
      end
    end

    context "when outer group will not be empty after removal" do
      it "removes only empty blocks" do
        install_gemfile <<-G
          source "#{file_uri_for(gem_repo1)}"

          group :test do
            gem "rack-test"

            group :serioustest do
              gem "rspec"
            end
          end
        G

        bundle "remove rspec"

        expect(out).to include("rspec was removed.")
        expect(gemfile).to eq <<~G
          source "#{file_uri_for(gem_repo1)}"

          group :test do
            gem "rack-test"

          end
        G
      end
    end

    context "when inner group will not be empty after removal" do
      it "removes only empty blocks" do
        install_gemfile <<-G
          source "#{file_uri_for(gem_repo1)}"

          group :test do
            group :serioustest do
              gem "rspec"
              gem "rack-test"
            end
          end
        G

        bundle "remove rspec"

        expect(out).to include("rspec was removed.")
        expect(gemfile).to eq <<~G
          source "#{file_uri_for(gem_repo1)}"

          group :test do
            group :serioustest do
              gem "rack-test"
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
          source "#{file_uri_for(gem_repo1)}"
          gem "rack"; gem "rails"
        G

        bundle "remove rails", raise_on_error: false

        expect(err).to include("Gems could not be removed. rack (>= 0) would also have been removed.")
        expect(gemfile).to eq <<~G
          source "#{file_uri_for(gem_repo1)}"
          gem "rack"; gem "rails"
        G
      end
    end

    context "when some gems could not be removed" do
      it "shows warning for gems not removed and success for those removed" do
        install_gemfile <<-G, raise_on_error: false
          source "#{file_uri_for(gem_repo1)}"
          gem"rack"
          gem"rspec"
          gem "rails"
          gem "minitest"
        G

        bundle "remove rails rack rspec minitest"

        expect(out).to include("rails was removed.")
        expect(out).to include("minitest was removed.")
        expect(out).to include("rack, rspec could not be removed.")
        expect(gemfile).to eq <<~G
          source "#{file_uri_for(gem_repo1)}"
          gem"rack"
          gem"rspec"
        G
      end
    end
  end

  context "with sources" do
    before do
      build_repo gem_repo3 do
        build_gem "rspec"
      end
    end

    it "removes gems and empty source blocks" do
      gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"

        gem "rack"

        source "#{file_uri_for(gem_repo3)}" do
          gem "rspec"
        end
      G

      bundle "install"

      bundle "remove rspec"

      expect(out).to include("rspec was removed.")
      expect(gemfile).to eq <<~G
        source "#{file_uri_for(gem_repo1)}"

        gem "rack"
      G
    end
  end

  describe "with eval_gemfile" do
    context "when gems are present in both gemfiles" do
      it "removes the gems" do
        create_file "Gemfile-other", <<-G
          gem "rack"
        G

        install_gemfile <<-G
          source "#{file_uri_for(gem_repo1)}"

          eval_gemfile "Gemfile-other"

          gem "rack"
        G

        bundle "remove rack"

        expect(out).to include("rack was removed.")
      end
    end

    context "when gems are present in other gemfile" do
      it "removes the gems" do
        create_file "Gemfile-other", <<-G
          gem "rack"
        G

        install_gemfile <<-G
          source "#{file_uri_for(gem_repo1)}"

          eval_gemfile "Gemfile-other"
        G

        bundle "remove rack"

        expect(bundled_app("Gemfile-other").read).to_not include("gem \"rack\"")
        expect(out).to include("rack was removed.")
      end
    end

    context "when gems to be removed are not specified in any of the gemfiles" do
      it "throws error for the gems not present" do
        # an empty gemfile
        # indicating the gem is not present in the gemfile
        create_file "Gemfile-other", <<-G
        G

        install_gemfile <<-G
          source "#{file_uri_for(gem_repo1)}"

          eval_gemfile "Gemfile-other"
        G

        bundle "remove rack", raise_on_error: false

        expect(err).to include("`rack` is not specified in #{bundled_app_gemfile} so it could not be removed.")
      end
    end

    context "when the gem is present in parent file but not in gemfile specified by eval_gemfile" do
      it "removes the gem" do
        create_file "Gemfile-other", <<-G
          gem "rails"
        G

        install_gemfile <<-G
          source "#{file_uri_for(gem_repo1)}"

          eval_gemfile "Gemfile-other"
          gem "rack"
        G

        bundle "remove rack", raise_on_error: false

        expect(out).to include("rack was removed.")
        expect(err).to include("`rack` is not specified in #{bundled_app("Gemfile-other")} so it could not be removed.")
        expect(gemfile).to eq <<~G
          source "#{file_uri_for(gem_repo1)}"

          eval_gemfile "Gemfile-other"
        G
      end
    end

    context "when gems cannot be removed from other gemfile" do
      it "shows error" do
        create_file "Gemfile-other", <<-G
          gem "rails"; gem "rack"
        G

        install_gemfile <<-G
          source "#{file_uri_for(gem_repo1)}"

          eval_gemfile "Gemfile-other"
          gem "rack"
        G

        bundle "remove rack", raise_on_error: false

        expect(out).to include("rack was removed.")
        expect(err).to include("Gems could not be removed. rails (>= 0) would also have been removed.")
        expect(gemfile).to eq <<~G
          source "#{file_uri_for(gem_repo1)}"

          eval_gemfile "Gemfile-other"
        G
      end
    end

    context "when gems could not be removed from parent gemfile" do
      it "shows error" do
        create_file "Gemfile-other", <<-G
          gem "rack"
        G

        install_gemfile <<-G
          source "#{file_uri_for(gem_repo1)}"

          eval_gemfile "Gemfile-other"
          gem "rails"; gem "rack"
        G

        bundle "remove rack", raise_on_error: false

        expect(err).to include("Gems could not be removed. rails (>= 0) would also have been removed.")
        expect(bundled_app("Gemfile-other").read).to include("gem \"rack\"")
        expect(gemfile).to eq <<~G
          source "#{file_uri_for(gem_repo1)}"

          eval_gemfile "Gemfile-other"
          gem "rails"; gem "rack"
        G
      end
    end

    context "when gem present in gemfiles but could not be removed from one from one of them" do
      it "removes gem which can be removed and shows warning for file from which it cannot be removed" do
        create_file "Gemfile-other", <<-G
          gem "rack"
        G

        install_gemfile <<-G
          source "#{file_uri_for(gem_repo1)}"

          eval_gemfile "Gemfile-other"
          gem"rack"
        G

        bundle "remove rack"

        expect(out).to include("rack was removed.")
        expect(bundled_app("Gemfile-other").read).to_not include("gem \"rack\"")
      end
    end
  end

  context "with install_if" do
    it "removes gems inside blocks and empty blocks" do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"

        install_if(lambda { false }) do
          gem "rack"
        end
      G

      bundle "remove rack"

      expect(out).to include("rack was removed.")
      expect(gemfile).to eq <<~G
        source "#{file_uri_for(gem_repo1)}"
      G
    end
  end

  context "with env" do
    it "removes gems inside blocks and empty blocks" do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"

        env "BUNDLER_TEST" do
          gem "rack"
        end
      G

      bundle "remove rack"

      expect(out).to include("rack was removed.")
      expect(gemfile).to eq <<~G
        source "#{file_uri_for(gem_repo1)}"
      G
    end
  end

  context "with gemspec" do
    it "should not remove the gem" do
      build_lib("foo", path: tmp("foo")) do |s|
        s.write("foo.gemspec", "")
        s.add_dependency "rack"
      end

      install_gemfile(<<-G)
        source "#{file_uri_for(gem_repo1)}"
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
          source "#{file_uri_for(gem_repo1)}"

          # gem "rack" might be used in the future
          gem "rack"
        G

        bundle "remove rack"

        expect(out).to include("rack was removed.")
        expect(gemfile).to eq <<~G
          source "#{file_uri_for(gem_repo1)}"

          # gem "rack" might be used in the future
        G
      end
    end

    context "when gem specified for removal has an inline comment" do
      it "removes the inline comment" do
        gemfile <<-G
          source "#{file_uri_for(gem_repo1)}"

          gem "rack" # this can be removed
        G

        bundle "remove rack"

        expect(out).to include("rack was removed.")
        expect(gemfile).to eq <<~G
          source "#{file_uri_for(gem_repo1)}"
        G
      end
    end

    context "when gem specified for removal is mentioned in other gem's comment" do
      it "does not remove other gem" do
        gemfile <<-G
          source "#{file_uri_for(gem_repo1)}"
          gem "puma" # implements interface provided by gem "rack"

          gem "rack"
        G

        bundle "remove rack"

        expect(out).to_not include("puma was removed.")
        expect(out).to include("rack was removed.")
        expect(gemfile).to eq <<~G
          source "#{file_uri_for(gem_repo1)}"
          gem "puma" # implements interface provided by gem "rack"
        G
      end
    end

    context "when gem specified for removal has a comment that mentions other gem" do
      it "does not remove other gem" do
        gemfile <<-G
          source "#{file_uri_for(gem_repo1)}"
          gem "puma" # implements interface provided by gem "rack"

          gem "rack"
        G

        bundle "remove puma"

        expect(out).to include("puma was removed.")
        expect(out).to_not include("rack was removed.")
        expect(gemfile).to eq <<~G
          source "#{file_uri_for(gem_repo1)}"

          gem "rack"
        G
      end
    end
  end
end
