path = File.expand_path("../TestString.rb", __FILE__)
instance_eval File.read(path), path
