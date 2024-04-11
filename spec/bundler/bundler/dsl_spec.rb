# frozen_string_literal: true

RSpec.describe Bundler::Dsl do
  before do
    @rubygems = double("rubygems")
    allow(Bundler::Source::Rubygems).to receive(:new) { @rubygems }
  end

  describe "#git_source" do
    it "registers custom hosts" do
      subject.git_source(:example) {|repo_name| "git@git.example.com:#{repo_name}.git" }
      subject.git_source(:foobar) {|repo_name| "git@foobar.com:#{repo_name}.git" }
      subject.gem("dobry-pies", example: "strzalek/dobry-pies")
      example_uri = "git@git.example.com:strzalek/dobry-pies.git"
      expect(subject.dependencies.first.source.uri).to eq(example_uri)
    end

    it "raises exception on invalid hostname" do
      expect do
        subject.git_source(:group) {|repo_name| "git@git.example.com:#{repo_name}.git" }
      end.to raise_error(Bundler::InvalidOption)
    end

    it "expects block passed" do
      expect { subject.git_source(:example) }.to raise_error(Bundler::InvalidOption)
    end

    it "converts :github PR to URI using https" do
      subject.gem("sparks", github: "https://github.com/indirect/sparks/pull/5")
      github_uri = "https://github.com/indirect/sparks.git"
      expect(subject.dependencies.first.source.uri).to eq(github_uri)
      expect(subject.dependencies.first.source.ref).to eq("refs/pull/5/head")
    end

    it "converts :gitlab PR to URI using https" do
      subject.gem("sparks", gitlab: "https://gitlab.com/indirect/sparks/-/merge_requests/5")
      gitlab_uri = "https://gitlab.com/indirect/sparks.git"
      expect(subject.dependencies.first.source.uri).to eq(gitlab_uri)
      expect(subject.dependencies.first.source.ref).to eq("refs/merge-requests/5/head")
    end

    it "rejects :github PR URI with a branch, ref or tag" do
      expect do
        subject.gem("sparks", github: "https://github.com/indirect/sparks/pull/5", branch: "foo")
      end.to raise_error(
        Bundler::GemfileError,
        %(The :branch option can't be used with `github: "https://github.com/indirect/sparks/pull/5"`),
      )

      expect do
        subject.gem("sparks", github: "https://github.com/indirect/sparks/pull/5", ref: "foo")
      end.to raise_error(
        Bundler::GemfileError,
        %(The :ref option can't be used with `github: "https://github.com/indirect/sparks/pull/5"`),
      )

      expect do
        subject.gem("sparks", github: "https://github.com/indirect/sparks/pull/5", tag: "foo")
      end.to raise_error(
        Bundler::GemfileError,
        %(The :tag option can't be used with `github: "https://github.com/indirect/sparks/pull/5"`),
      )
    end

    it "rejects :gitlab PR URI with a branch, ref or tag" do
      expect do
        subject.gem("sparks", gitlab: "https://gitlab.com/indirect/sparks/-/merge_requests/5", branch: "foo")
      end.to raise_error(
        Bundler::GemfileError,
        %(The :branch option can't be used with `gitlab: "https://gitlab.com/indirect/sparks/-/merge_requests/5"`),
      )

      expect do
        subject.gem("sparks", gitlab: "https://gitlab.com/indirect/sparks/-/merge_requests/5", ref: "foo")
      end.to raise_error(
        Bundler::GemfileError,
        %(The :ref option can't be used with `gitlab: "https://gitlab.com/indirect/sparks/-/merge_requests/5"`),
      )

      expect do
        subject.gem("sparks", gitlab: "https://gitlab.com/indirect/sparks/-/merge_requests/5", tag: "foo")
      end.to raise_error(
        Bundler::GemfileError,
        %(The :tag option can't be used with `gitlab: "https://gitlab.com/indirect/sparks/-/merge_requests/5"`),
      )
    end

    it "rejects :github with :git" do
      expect do
        subject.gem("sparks", github: "indirect/sparks", git: "https://github.com/indirect/sparks.git")
      end.to raise_error(
        Bundler::GemfileError,
        %(The :git option can't be used with `github: "indirect/sparks"`),
      )
    end

    it "rejects :gitlab with :git" do
      expect do
        subject.gem("sparks", gitlab: "indirect/sparks", git: "https://gitlab.com/indirect/sparks.git")
      end.to raise_error(
        Bundler::GemfileError,
        %(The :git option can't be used with `gitlab: "indirect/sparks"`),
      )
    end

    context "default hosts", bundler: "< 3" do
      it "converts :github to URI using https" do
        subject.gem("sparks", github: "indirect/sparks")
        github_uri = "https://github.com/indirect/sparks.git"
        expect(subject.dependencies.first.source.uri).to eq(github_uri)
      end

      it "converts :github shortcut to URI using https" do
        subject.gem("sparks", github: "rails")
        github_uri = "https://github.com/rails/rails.git"
        expect(subject.dependencies.first.source.uri).to eq(github_uri)
      end

      it "converts :gitlab to URI using https" do
        subject.gem("sparks", gitlab: "indirect/sparks")
        gitlab_uri = "https://gitlab.com/indirect/sparks.git"
        expect(subject.dependencies.first.source.uri).to eq(gitlab_uri)
      end

      it "converts :gitlab shortcut to URI using https" do
        subject.gem("sparks", gitlab: "rails")
        gitlab_uri = "https://gitlab.com/rails/rails.git"
        expect(subject.dependencies.first.source.uri).to eq(gitlab_uri)
      end

      it "converts numeric :gist to :git" do
        subject.gem("not-really-a-gem", gist: 2_859_988)
        github_uri = "https://gist.github.com/2859988.git"
        expect(subject.dependencies.first.source.uri).to eq(github_uri)
      end

      it "converts :gist to :git" do
        subject.gem("not-really-a-gem", gist: "2859988")
        github_uri = "https://gist.github.com/2859988.git"
        expect(subject.dependencies.first.source.uri).to eq(github_uri)
      end

      it "converts :bitbucket to :git" do
        subject.gem("not-really-a-gem", bitbucket: "mcorp/flatlab-rails")
        bitbucket_uri = "https://mcorp@bitbucket.org/mcorp/flatlab-rails.git"
        expect(subject.dependencies.first.source.uri).to eq(bitbucket_uri)
      end

      it "converts 'mcorp' to 'mcorp/mcorp'" do
        subject.gem("not-really-a-gem", bitbucket: "mcorp")
        bitbucket_uri = "https://mcorp@bitbucket.org/mcorp/mcorp.git"
        expect(subject.dependencies.first.source.uri).to eq(bitbucket_uri)
      end
    end

    context "default git sources" do
      it "has bitbucket, gist, github, and gitlab" do
        expect(subject.instance_variable_get(:@git_sources).keys.sort).to eq(%w[bitbucket gist github gitlab])
      end
    end
  end

  describe "#method_missing" do
    it "raises an error for unknown DSL methods" do
      expect(Bundler).to receive(:read_file).with(source_root.join("Gemfile").to_s).
        and_return("unknown")

      error_msg = "There was an error parsing `Gemfile`: Undefined local variable or method `unknown' for Gemfile. Bundler cannot continue."
      expect { subject.eval_gemfile("Gemfile") }.
        to raise_error(Bundler::GemfileError, Regexp.new(error_msg))
    end
  end

  describe "#eval_gemfile" do
    it "handles syntax errors with a useful message" do
      expect(Bundler).to receive(:read_file).with(source_root.join("Gemfile").to_s).and_return("}")
      expect { subject.eval_gemfile("Gemfile") }.
        to raise_error(Bundler::GemfileError, /There was an error parsing `Gemfile`: (syntax error, unexpected tSTRING_DEND|(compile error - )?syntax error, unexpected '\}'). Bundler cannot continue./)
    end

    it "distinguishes syntax errors from evaluation errors" do
      expect(Bundler).to receive(:read_file).with(source_root.join("Gemfile").to_s).and_return(
        "ruby '2.1.5', :engine => 'ruby', :engine_version => '1.2.4'"
      )
      expect { subject.eval_gemfile("Gemfile") }.
        to raise_error(Bundler::GemfileError, /There was an error evaluating `Gemfile`: ruby_version must match the :engine_version for MRI/)
    end

    it "populates __dir__ and __FILE__ correctly" do
      abs_path = source_root.join("../fragment.rb").to_s
      expect(Bundler).to receive(:read_file).with(abs_path).and_return(<<~RUBY)
        @fragment_dir = __dir__
        @fragment_file = __FILE__
      RUBY
      subject.eval_gemfile("../fragment.rb")
      expect(subject.instance_variable_get(:@fragment_dir)).to eq(source_root.dirname.to_s)
      expect(subject.instance_variable_get(:@fragment_file)).to eq(abs_path)
    end
  end

  describe "#gem" do
    # rubocop:disable Naming/VariableNumber
    [:ruby, :ruby_18, :ruby_19, :ruby_20, :ruby_21, :ruby_22, :ruby_23, :ruby_24, :ruby_25, :ruby_26, :ruby_27,
     :ruby_30, :ruby_31, :ruby_32, :ruby_33, :mri, :mri_18, :mri_19, :mri_20, :mri_21, :mri_22, :mri_23, :mri_24,
     :mri_25, :mri_26, :mri_27, :mri_30, :mri_31, :mri_32, :mri_33, :jruby, :rbx, :truffleruby].each do |platform|
      it "allows #{platform} as a valid platform" do
        subject.gem("foo", platform: platform)
      end
    end
    # rubocop:enable Naming/VariableNumber

    it "allows platforms matching the running Ruby version" do
      platform = "ruby_#{RbConfig::CONFIG["MAJOR"]}#{RbConfig::CONFIG["MINOR"]}"
      subject.gem("foo", platform: platform)
    end

    it "rejects invalid platforms" do
      expect { subject.gem("foo", platform: :bogus) }.
        to raise_error(Bundler::GemfileError, /is not a valid platform/)
    end

    it "rejects empty gem name" do
      expect { subject.gem("") }.
        to raise_error(Bundler::GemfileError, /an empty gem name is not valid/)
    end

    it "rejects with a leading space in the name" do
      expect { subject.gem(" foo") }.
        to raise_error(Bundler::GemfileError, /' foo' is not a valid gem name because it contains whitespace/)
    end

    it "rejects with a trailing space in the name" do
      expect { subject.gem("foo ") }.
        to raise_error(Bundler::GemfileError, /'foo ' is not a valid gem name because it contains whitespace/)
    end

    it "rejects with a space in the gem name" do
      expect { subject.gem("fo o") }.
        to raise_error(Bundler::GemfileError, /'fo o' is not a valid gem name because it contains whitespace/)
    end

    it "rejects with a tab in the gem name" do
      expect { subject.gem("fo\to") }.
        to raise_error(Bundler::GemfileError, /'fo\to' is not a valid gem name because it contains whitespace/)
    end

    it "rejects with a newline in the gem name" do
      expect { subject.gem("fo\no") }.
        to raise_error(Bundler::GemfileError, /'fo\no' is not a valid gem name because it contains whitespace/)
    end

    it "rejects with a carriage return in the gem name" do
      expect { subject.gem("fo\ro") }.
        to raise_error(Bundler::GemfileError, /'fo\ro' is not a valid gem name because it contains whitespace/)
    end

    it "rejects with a form feed in the gem name" do
      expect { subject.gem("fo\fo") }.
        to raise_error(Bundler::GemfileError, /'fo\fo' is not a valid gem name because it contains whitespace/)
    end

    it "rejects symbols as gem name" do
      expect { subject.gem(:foo) }.
        to raise_error(Bundler::GemfileError, /You need to specify gem names as Strings. Use 'gem "foo"' instead/)
    end

    it "rejects branch option on non-git gems" do
      expect { subject.gem("foo", branch: "test") }.
        to raise_error(Bundler::GemfileError, /The `branch` option for `gem 'foo'` is not allowed. Only gems with a git source can specify a branch/)
    end

    it "allows specifying a branch on git gems" do
      subject.gem("foo", branch: "test", git: "http://mytestrepo")
      dep = subject.dependencies.last
      expect(dep.name).to eq "foo"
    end

    it "allows specifying a branch on git gems with a git_source" do
      subject.git_source(:test_source) {|n| "https://github.com/#{n}" }
      subject.gem("foo", branch: "test", test_source: "bundler/bundler")
      dep = subject.dependencies.last
      expect(dep.name).to eq "foo"
    end
  end

  context "can bundle groups of gems with" do
    # git "https://github.com/rails/rails.git" do
    #   gem "railties"
    #   gem "action_pack"
    #   gem "active_model"
    # end
    describe "#git" do
      it "from a single repo" do
        rails_gems = %w[railties action_pack active_model]
        subject.git "https://github.com/rails/rails.git" do
          rails_gems.each {|rails_gem| subject.send :gem, rails_gem }
        end
        expect(subject.dependencies.map(&:name)).to match_array rails_gems
      end
    end

    # github 'spree' do
    #   gem 'spree_core'
    #   gem 'spree_api'
    #   gem 'spree_backend'
    # end
    describe "#github" do
      it "from github" do
        spree_gems = %w[spree_core spree_api spree_backend]
        subject.github "spree" do
          spree_gems.each {|spree_gem| subject.send :gem, spree_gem }
        end

        subject.dependencies.each do |d|
          expect(d.source.uri).to eq("https://github.com/spree/spree.git")
        end
      end
    end
  end

  describe "syntax errors" do
    it "will raise a Bundler::GemfileError" do
      gemfile "gem 'foo', :path => /unquoted/string/syntax/error"
      expect { Bundler::Dsl.evaluate(bundled_app_gemfile, nil, true) }.
        to raise_error(Bundler::GemfileError, /There was an error parsing `Gemfile`:( compile error -)? unknown regexp options - trg.+ Bundler cannot continue./)
    end
  end

  describe "Runtime errors" do
    it "will raise a Bundler::GemfileError" do
      gemfile "raise RuntimeError, 'foo'"
      expect { Bundler::Dsl.evaluate(bundled_app_gemfile, nil, true) }.
        to raise_error(Bundler::GemfileError, /There was an error parsing `Gemfile`: foo. Bundler cannot continue./i)
    end
  end

  describe "#with_source" do
    context "if there was a rubygem source already defined" do
      it "restores it after it's done" do
        other_source = double("other-source")
        allow(Bundler::Source::Rubygems).to receive(:new).and_return(other_source)
        allow(Bundler).to receive(:default_gemfile).and_return(Pathname.new("./Gemfile"))

        subject.source("https://other-source.org") do
          subject.gem("dobry-pies", path: "foo")
          subject.gem("foo")
        end

        expect(subject.dependencies.last.source).to eq(other_source)
      end
    end
  end

  describe "#check_primary_source_safety" do
    context "when a global source is not defined implicitly" do
      it "will raise a major deprecation warning" do
        not_a_global_source = double("not-a-global-source", no_remotes?: true)
        allow(Bundler::Source::Rubygems).to receive(:new).and_return(not_a_global_source)

        warning = "This Gemfile does not include an explicit global source. " \
          "Not using an explicit global source may result in a different lockfile being generated depending on " \
          "the gems you have installed locally before bundler is run. " \
          "Instead, define a global source in your Gemfile like this: source \"https://rubygems.org\"."
        expect(Bundler::SharedHelpers).to receive(:major_deprecation).with(2, warning)

        subject.check_primary_source_safety
      end
    end
  end
end
