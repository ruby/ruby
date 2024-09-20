# frozen_string_literal: true

RSpec.describe Bundler::CIDetector do
  # This is properly tested in rubygems, under the name Gem::CIDetector
  # But the test that confirms that our version _stays in sync_ with that version
  # will live here.

  it "stays in sync with the rubygems implementation" do
    rubygems_implementation_path = File.join(git_root, "lib", "rubygems", "ci_detector.rb")
    expect(File.exist?(rubygems_implementation_path)).to be_truthy
    rubygems_code = File.read(rubygems_implementation_path)
    denamespaced_rubygems_code = rubygems_code.sub("Gem", "NAMESPACE")

    bundler_implementation_path = File.join(source_lib_dir, "bundler", "ci_detector.rb")
    expect(File.exist?(bundler_implementation_path)).to be_truthy
    bundler_code = File.read(bundler_implementation_path)
    denamespaced_bundler_code = bundler_code.sub("Bundler", "NAMESPACE")

    expect(denamespaced_bundler_code).to eq(denamespaced_rubygems_code)
  end
end
