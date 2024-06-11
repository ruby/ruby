# frozen_string_literal: true

RSpec.describe "bundle init" do
  it "generates a Gemfile" do
    bundle :init
    expect(out).to include("Writing new Gemfile")
    expect(bundled_app_gemfile).to be_file
  end

  context "with a template with permission flags not matching current process umask" do
    let(:template_file) do
      gemfile = Bundler.preferred_gemfile_name
      templates_dir.join(gemfile)
    end

    let(:target_dir) { bundled_app("init_permissions_test") }

    around do |example|
      old_chmod = File.stat(template_file).mode
      FileUtils.chmod(old_chmod | 0o111, template_file) # chmod +x
      example.run
      FileUtils.chmod(old_chmod, template_file)
    end

    it "honours the current process umask when generating from a template" do
      FileUtils.mkdir(target_dir)
      bundle :init, dir: target_dir
      generated_mode = File.stat(File.join(target_dir, "Gemfile")).mode & 0o111
      expect(generated_mode).to be_zero
    end
  end

  context "when a Gemfile already exists" do
    before do
      create_file "Gemfile", <<-G
        gem "rails"
      G
    end

    it "does not change existing Gemfiles" do
      expect { bundle :init, raise_on_error: false }.not_to change { File.read(bundled_app_gemfile) }
    end

    it "notifies the user that an existing Gemfile already exists" do
      bundle :init, raise_on_error: false
      expect(err).to include("Gemfile already exists")
    end
  end

  context "when a Gemfile exists in a parent directory" do
    let(:subdir) { "child_dir" }

    it "lets users generate a Gemfile in a child directory" do
      bundle :init

      FileUtils.mkdir bundled_app(subdir)

      bundle :init, dir: bundled_app(subdir)

      expect(out).to include("Writing new Gemfile")
      expect(bundled_app("#{subdir}/Gemfile")).to be_file
    end
  end

  context "when the dir is not writable by the current user" do
    let(:subdir) { "child_dir" }

    it "notifies the user that it cannot write to it" do
      FileUtils.mkdir bundled_app(subdir)
      # chmod a-w it
      mode = File.stat(bundled_app(subdir)).mode ^ 0o222
      FileUtils.chmod mode, bundled_app(subdir)

      bundle :init, dir: bundled_app(subdir), raise_on_error: false

      expect(err).to include("directory is not writable")
      expect(Dir[bundled_app("#{subdir}/*")]).to be_empty
    end
  end

  context "given --gemspec option" do
    let(:spec_file) { tmp("test.gemspec") }

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

      bundle :init, gemspec: spec_file

      gemfile = bundled_app_gemfile.read
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

        bundle :init, gemspec: spec_file, raise_on_error: false
        expect(err).to include("There was an error while loading `test.gemspec`")
      end
    end
  end

  context "when init_gems_rb setting is enabled" do
    before { bundle "config set init_gems_rb true" }

    it "generates a gems.rb" do
      bundle :init
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
        expect { bundle :init, raise_on_error: false }.not_to change { File.read(bundled_app("gems.rb")) }
      end

      it "notifies the user that an existing gems.rb already exists" do
        bundle :init, raise_on_error: false
        expect(err).to include("gems.rb already exists")
      end
    end

    context "when a gems.rb file exists in a parent directory" do
      let(:subdir) { "child_dir" }

      it "lets users generate a Gemfile in a child directory" do
        bundle :init

        FileUtils.mkdir bundled_app(subdir)

        bundle :init, dir: bundled_app(subdir)

        expect(out).to include("Writing new gems.rb")
        expect(bundled_app("#{subdir}/gems.rb")).to be_file
      end
    end

    context "given --gemspec option" do
      let(:spec_file) { tmp("test.gemspec") }

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
        bundle :init, gemspec: spec_file

        gemfile = bundled_app("gems.rb").read
        expect(gemfile).to match(%r{source 'https://rubygems.org'})
        expect(gemfile.scan(/gem "rack", "= 1.0.1"/).size).to eq(1)
        expect(gemfile.scan(/gem "rspec", "= 1.2"/).size).to eq(1)
        expect(gemfile.scan(/group :development/).size).to eq(1)
      end

      it "prints message to user" do
        bundle :init, gemspec: spec_file

        expect(out).to include("Writing new gems.rb")
      end
    end
  end

  describe "using the --gemfile" do
    it "should use the --gemfile value to name the gemfile" do
      custom_gemfile_name = "NiceGemfileName"

      bundle :init, gemfile: custom_gemfile_name

      expect(out).to include("Writing new #{custom_gemfile_name}")
      used_template = File.read("#{source_root}/lib/bundler/templates/Gemfile")
      generated_gemfile = bundled_app(custom_gemfile_name).read
      expect(generated_gemfile).to eq(used_template)
    end
  end
end
