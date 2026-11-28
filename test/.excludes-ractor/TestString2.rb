path = File.expand_path("../TestString.rb", __FILE__)
instance_eval File.read(path), path
exclude(:test_capacity_inflation, "Bug::String is not ractor safe")
exclude(:test_capacity_no_inflation, "Bug::String is not ractor safe")
exclude(:test_wide_encoding_terminator_with_capacity, "Bug::String is not ractor safe")
exclude(:test_wide_encoding_terminator_without_capacity, "Bug::String is not ractor safe")
