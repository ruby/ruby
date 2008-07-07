f = File.open(ARGV[0], File::WRONLY|File::APPEND)
f.write <<EOM
class Object
  remove_const :RUBY_PLATFORM
  RUBY_PLATFORM = Config::CONFIG[\"RUBY_PLATFORM\"]
end
EOM
