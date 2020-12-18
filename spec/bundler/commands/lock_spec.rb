# frozen_string_literal: true

RSpec.describe "bundle lock" do
  def strip_lockfile(lockfile)
    strip_whitespace(lockfile).sub(/\n\Z/, "")
  end

  def read_lockfile(file = "Gemfile.lock")
    strip_lockfile bundled_app(file).read
  end

  let(:repo) { gem_repo1 }

  before :each do
    gemfile <<-G
      source "#{file_uri_for(repo)}"
      gem "rails"
      gem "weakling"
      gem "foo"
    G

    @lockfile = strip_lockfile(<<-L)
      GEM
        remote: #{file_uri_for(repo)}/
        specs:
          actionmailer (2.3.2)
            activesupport (= 2.3.2)
          actionpack (2.3.2)
            activesupport (= 2.3.2)
          activerecord (2.3.2)
            activesupport (= 2.3.2)
          activeresource (2.3.2)
            activesupport (= 2.3.2)
          activesupport (2.3.2)
          foo (1.0)
          rails (2.3.2)
            actionmailer (= 2.3.2)
            actionpack (= 2.3.2)
            activerecord (= 2.3.2)
            activeresource (= 2.3.2)
            rake (= 13.0.1)
          rake (13.0.1)
          weakling (0.0.3)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        foo
        rails
        weakling

      BUNDLED WITH
         #{Bundler::VERSION}
    L
  end

  it "prints a lockfile when there is no existing lockfile with --print" do
    bundle "lock --print"

    expect(out).to eq(@lockfile)
  end

  it "prints a lockfile when there is an existing lockfile with --print" do
    lockfile @lockfile

    bundle "lock --print"

    expect(out).to eq(@lockfile)
  end

  it "writes a lockfile when there is no existing lockfile" do
    bundle "lock"

    expect(read_lockfile).to eq(@lockfile)
  end

  it "writes a lockfile when there is an outdated lockfile using --update" do
    lockfile @lockfile.gsub("2.3.2", "2.3.1")

    bundle "lock --update"

    expect(read_lockfile).to eq(@lockfile)
  end

  it "does not fetch remote specs when using the --local option" do
    bundle "lock --update --local", :raise_on_error => false

    expect(err).to match(/sources listed in your Gemfile|installed locally/)
  end

  it "works with --gemfile flag" do
    create_file "CustomGemfile", <<-G
      source "#{file_uri_for(repo)}"
      gem "foo"
    G
    lockfile = strip_lockfile(<<-L)
      GEM
        remote: #{file_uri_for(repo)}/
        specs:
          foo (1.0)

      PLATFORMS
        #{lockfile_platforms}

      DEPENDENCIES
        foo

      BUNDLED WITH
         #{Bundler::VERSION}
    L
    bundle "lock --gemfile CustomGemfile"

    expect(out).to match(/Writing lockfile to.+CustomGemfile\.lock/)
    expect(read_lockfile("CustomGemfile.lock")).to eq(lockfile)
    expect { read_lockfile }.to raise_error(Errno::ENOENT)
  end

  it "writes to a custom location using --lockfile" do
    bundle "lock --lockfile=lock"

    expect(out).to match(/Writing lockfile to.+lock/)
    expect(read_lockfile("lock")).to eq(@lockfile)
    expect { read_lockfile }.to raise_error(Errno::ENOENT)
  end

  it "writes to custom location using --lockfile when a default lockfile is present" do
    bundle "install"
    bundle "lock --lockfile=lock"

    expect(out).to match(/Writing lockfile to.+lock/)
    expect(read_lockfile("lock")).to eq(@lockfile)
  end

  it "update specific gems using --update" do
    lockfile @lockfile.gsub("2.3.2", "2.3.1").gsub("13.0.1", "10.0.1")

    bundle "lock --update rails rake"

    expect(read_lockfile).to eq(@lockfile)
  end

  it "errors when updating a missing specific gems using --update" do
    lockfile @lockfile

    bundle "lock --update blahblah", :raise_on_error => false
    expect(err).to eq("Could not find gem 'blahblah'.")

    expect(read_lockfile).to eq(@lockfile)
  end

  it "can lock without downloading gems" do
    gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"

      gem "thin"
      gem "rack_middleware", :group => "test"
    G
    bundle "config set without test"
    bundle "config set path .bundle"
    bundle "lock"
    expect(bundled_app(".bundle")).not_to exist
  end

  # see update_spec for more coverage on same options. logic is shared so it's not necessary
  # to repeat coverage here.
  context "conservative updates" do
    before do
      build_repo4 do
        build_gem "foo", %w[1.4.3 1.4.4] do |s|
          s.add_dependency "bar", "~> 2.0"
        end
        build_gem "foo", %w[1.4.5 1.5.0] do |s|
          s.add_dependency "bar", "~> 2.1"
        end
        build_gem "foo", %w[1.5.1] do |s|
          s.add_dependency "bar", "~> 3.0"
        end
        build_gem "bar", %w[2.0.3 2.0.4 2.0.5 2.1.0 2.1.1 3.0.0]
        build_gem "qux", %w[1.0.0 1.0.1 1.1.0 2.0.0]
      end

      # establish a lockfile set to 1.4.3
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo4)}"
        gem 'foo', '1.4.3'
        gem 'bar', '2.0.3'
        gem 'qux', '1.0.0'
      G

      # remove 1.4.3 requirement and bar altogether
      # to setup update specs below
      gemfile <<-G
        source "#{file_uri_for(gem_repo4)}"
        gem 'foo'
        gem 'qux'
      G

      allow(Bundler::SharedHelpers).to receive(:find_gemfile).and_return(bundled_app_gemfile)
    end

    it "single gem updates dependent gem to minor" do
      bundle "lock --update foo --patch"

      expect(the_bundle.locked_gems.specs.map(&:full_name)).to eq(%w[foo-1.4.5 bar-2.1.1 qux-1.0.0].sort)
    end

    it "minor preferred with strict" do
      bundle "lock --update --minor --strict"

      expect(the_bundle.locked_gems.specs.map(&:full_name)).to eq(%w[foo-1.5.0 bar-2.1.1 qux-1.1.0].sort)
    end
  end

  it "supports adding new platforms" do
    bundle "lock --add-platform java x86-mingw32"

    allow(Bundler::SharedHelpers).to receive(:find_gemfile).and_return(bundled_app_gemfile)
    lockfile = Bundler::LockfileParser.new(read_lockfile)
    expect(lockfile.platforms).to match_array(local_platforms.unshift(java, mingw).uniq)
  end

  it "supports adding the `ruby` platform" do
    bundle "lock --add-platform ruby"

    allow(Bundler::SharedHelpers).to receive(:find_gemfile).and_return(bundled_app_gemfile)
    lockfile = Bundler::LockfileParser.new(read_lockfile)
    expect(lockfile.platforms).to match_array(local_platforms.unshift("ruby").uniq)
  end

  it "warns when adding an unknown platform" do
    bundle "lock --add-platform foobarbaz"
    expect(err).to include("The platform `foobarbaz` is unknown to RubyGems and adding it will likely lead to resolution errors")
  end

  it "allows removing platforms" do
    bundle "lock --add-platform java x86-mingw32"

    allow(Bundler::SharedHelpers).to receive(:find_gemfile).and_return(bundled_app_gemfile)
    lockfile = Bundler::LockfileParser.new(read_lockfile)
    expect(lockfile.platforms).to match_array(local_platforms.unshift(java, mingw).uniq)

    bundle "lock --remove-platform java"

    lockfile = Bundler::LockfileParser.new(read_lockfile)
    expect(lockfile.platforms).to match_array(local_platforms.unshift(mingw).uniq)
  end

  it "errors when removing all platforms" do
    bundle "lock --remove-platform #{local_platforms.join(" ")}", :raise_on_error => false
    expect(err).to include("Removing all platforms from the bundle is not allowed")
  end

  # from https://github.com/rubygems/bundler/issues/4896
  it "properly adds platforms when platform requirements come from different dependencies" do
    build_repo4 do
      build_gem "ffi", "1.9.14"
      build_gem "ffi", "1.9.14" do |s|
        s.platform = mingw
      end

      build_gem "gssapi", "0.1"
      build_gem "gssapi", "0.2"
      build_gem "gssapi", "0.3"
      build_gem "gssapi", "1.2.0" do |s|
        s.add_dependency "ffi", ">= 1.0.1"
      end

      build_gem "mixlib-shellout", "2.2.6"
      build_gem "mixlib-shellout", "2.2.6" do |s|
        s.platform = "universal-mingw32"
        s.add_dependency "win32-process", "~> 0.8.2"
      end

      # we need all these versions to get the sorting the same as it would be
      # pulling from rubygems.org
      %w[0.8.3 0.8.2 0.8.1 0.8.0].each do |v|
        build_gem "win32-process", v do |s|
          s.add_dependency "ffi", ">= 1.0.0"
        end
      end
    end

    gemfile <<-G
      source "#{file_uri_for(gem_repo4)}"

      gem "mixlib-shellout"
      gem "gssapi"
    G

    simulate_platform(mingw) { bundle :lock }

    lockfile_should_be <<-G
      GEM
        remote: #{file_uri_for(gem_repo4)}/
        specs:
          ffi (1.9.14-x86-mingw32)
          gssapi (1.2.0)
            ffi (>= 1.0.1)
          mixlib-shellout (2.2.6-universal-mingw32)
            win32-process (~> 0.8.2)
          win32-process (0.8.3)
            ffi (>= 1.0.0)

      PLATFORMS
        x86-mingw32

      DEPENDENCIES
        gssapi
        mixlib-shellout

      BUNDLED WITH
         #{Bundler::VERSION}
    G

    simulate_platform(rb) { bundle :lock }

    lockfile_should_be <<-G
      GEM
        remote: #{file_uri_for(gem_repo4)}/
        specs:
          ffi (1.9.14)
          ffi (1.9.14-x86-mingw32)
          gssapi (1.2.0)
            ffi (>= 1.0.1)
          mixlib-shellout (2.2.6)
          mixlib-shellout (2.2.6-universal-mingw32)
            win32-process (~> 0.8.2)
          win32-process (0.8.3)
            ffi (>= 1.0.0)

      PLATFORMS
        ruby
        x86-mingw32

      DEPENDENCIES
        gssapi
        mixlib-shellout

      BUNDLED WITH
         #{Bundler::VERSION}
    G
  end

  context "when an update is available" do
    let(:repo) { gem_repo2 }

    before do
      lockfile(@lockfile)
      build_repo2 do
        build_gem "foo", "2.0"
      end
    end

    it "does not implicitly update" do
      bundle "lock"

      expect(read_lockfile).to eq(@lockfile)
    end

    it "accounts for changes in the gemfile" do
      gemfile gemfile.gsub('"foo"', '"foo", "2.0"')
      bundle "lock"

      expect(read_lockfile).to eq(@lockfile.sub("foo (1.0)", "foo (2.0)").sub(/foo$/, "foo (= 2.0)"))
    end
  end
end
