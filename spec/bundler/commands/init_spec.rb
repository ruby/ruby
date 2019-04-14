# frozen_string_literal: true

RSpec.describe "bundle init" do
  it "generates a Gemfile" do
    bundle! :init
    expect(out).to include("Writing new Gemfile")
    expect(bundled_app("Gemfile")).to be_file
  end

  context "when a Gemfile already exists" do
    before do
      create_file "Gemfile", <<-G
        gem "rails"
      G
    end

    it "does not change existing Gemfiles" do
      expect { bundle :init }.not_to change { File.read(bundled_app("Gemfile")) }
    end

    it "notifies the user that an existing Gemfile already exists" do
      bundle :init
      expect(err).to include("Gemfile already exists")
    end
  end

  context "when a Gemfile exists in a parent directory" do
    let(:subdir) { "child_dir" }

    it "lets users generate a Gemfile in a child directory" do
      bundle! :init

      FileUtils.mkdir bundled_app(subdir)

      Dir.chdir bundled_app(subdir) do
        bundle! :init
      end

      expect(out).to include("Writing new Gemfile")
      expect(bundled_app("#{subdir}/Gemfile")).to be_file
    end
  end

  context "when the dir is not writable by the current user" do
    let(:subdir) { "child_dir" }

    it "notifies the user that it can not write to it" do
      FileUtils.mkdir bundled_app(subdir)
      # chmod a-w it
      mode = File.stat(bundled_app(subdir)).mode ^ 0o222
      FileUtils.chmod mode, bundled_app(subdir)

      Dir.chdir bundled_app(subdir) do
        bundle :init
      end

      expect(err).to include("directory is not writable")
      expect(Dir[bundled_app("#{subdir}/*")]).to be_empty
    end
  end

  context "given --gemspec option" do
    let(:spec_file) { tmp.join("test.gemspec") }

    it "should generate from an existing gemspec" do
      File.open(spec_file, "w") do |file|
        file << <<-S
          Gem::Specification.new do |s|
          s.name = 'test'
          s.add_dependency 'rack', '= 1.0.1'
          s.add_development_dependency 'rspec', '1.2'
          end
        S
      end

      bundle :init, :gemspec => spec_file

      gemfile = bundled_app("Gemfile").read
      expect(gemfile).to match(%r{source 'https://rubygems.org'})
      expect(gemfile.scan(/gem "rack", "= 1.0.1"/).size).to eq(1)
      expect(gemfile.scan(/gem "rspec", "= 1.2"/).size).to eq(1)
      expect(gemfile.scan(/group :development/).size).to eq(1)
    end

    context "when gemspec file is invalid" do
      it "notifies the user that specification is invalid" do
        File.open(spec_file, "w") do |file|
          file << <<-S
            Gem::Specification.new do |s|
            s.name = 'test'
            s.invalid_method_name
            end
          S
        end

        bundle :init, :gemspec => spec_file
        expect(last_command.bundler_err).to include("There was an error while loading `test.gemspec`")
      end
    end
  end

  context "when init_gems_rb setting is enabled" do
    before { bundle "config set init_gems_rb true" }

    it "generates a gems.rb" do
      bundle! :init
      expect(out).to include("Writing new gems.rb")
      expect(bundled_app("gems.rb")).to be_file
    end

    context "when gems.rb already exists" do
      before do
        create_file("gems.rb", <<-G)
          gem "rails"
        G
      end

      it "does not change existing Gemfiles" do
        expect { bundle :init }.not_to change { File.read(bundled_app("gems.rb")) }
      end

      it "notifies the user that an existing gems.rb already exists" do
        bundle :init
        expect(err).to include("gems.rb already exists")
      end
    end

    context "when a gems.rb file exists in a parent directory" do
      let(:subdir) { "child_dir" }

      it "lets users generate a Gemfile in a child directory" do
        bundle! :init

        FileUtils.mkdir bundled_app(subdir)

        Dir.chdir bundled_app(subdir) do
          bundle! :init
        end

        expect(out).to include("Writing new gems.rb")
        expect(bundled_app("#{subdir}/gems.rb")).to be_file
      end
    end

    context "given --gemspec option" do
      let(:spec_file) { tmp.join("test.gemspec") }

      before do
        File.open(spec_file, "w") do |file|
          file << <<-S
            Gem::Specification.new do |s|
            s.name = 'test'
            s.add_dependency 'rack', '= 1.0.1'
            s.add_development_dependency 'rspec', '1.2'
            end
          S
        end
      end

      it "should generate from an existing gemspec" do
        bundle :init, :gemspec => spec_file

        gemfile = bundled_app("gems.rb").read
        expect(gemfile).to match(%r{source 'https://rubygems.org'})
        expect(gemfile.scan(/gem "rack", "= 1.0.1"/).size).to eq(1)
        expect(gemfile.scan(/gem "rspec", "= 1.2"/).size).to eq(1)
        expect(gemfile.scan(/group :development/).size).to eq(1)
      end

      it "prints message to user" do
        bundle :init, :gemspec => spec_file

        expect(out).to include("Writing new gems.rb")
      end
    end
  end
end
