ENV["GEM_HOME"] = File.expand_path("../../.bundle", __dir__)
ENV["BUNDLE_APP_CONFIG"] = File.expand_path("../../.bundle", __dir__)
ENV["BUNDLE_PATH__SYSTEM"] = "true"
ENV["BUNDLE_WITHOUT"] = "lint doc"
