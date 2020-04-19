require "ruby/signature"
require "ruby/signature/test"

require "optparse"
require "shellwords"

logger = Logger.new(STDERR)

begin
  opts = Shellwords.shellsplit(ENV["RBS_TEST_OPT"] || "-I sig")
  filter = ENV.fetch("RBS_TEST_TARGET").split(",")
  skips = (ENV["RBS_TEST_SKIP"] || "").split(",")
  logger.level = (ENV["RBS_TEST_LOGLEVEL"] || "info")
  raise_on_error = ENV["RBS_TEST_RAISE"]
rescue
  STDERR.puts "ruby/signature/test/setup handles the following environment variables:"
  STDERR.puts "  [REQUIRED] RBS_TEST_TARGET: test target class name, `Foo::Bar,Foo::Baz` for each class or `Foo::*` for all classes under `Foo`"
  STDERR.puts "  [OPTIONAL] RBS_TEST_SKIP: skip testing classes"
  STDERR.puts "  [OPTIONAL] RBS_TEST_OPT: options for signatures (`-r` for libraries or `-I` for signatures)"
  STDERR.puts "  [OPTIONAL] RBS_TEST_LOGLEVEL: one of debug|info|warn|error|fatal (defaults to info)"
  STDERR.puts "  [OPTIONAL] RBS_TEST_RAISE: specify any value to raise an exception when type error is detected"
  exit 1
end

hooks = []

env = Ruby::Signature::Environment.new

loader = Ruby::Signature::EnvironmentLoader.new
OptionParser.new do |opts|
  opts.on("-r [LIB]") do |name| loader.add(library: name) end
  opts.on("-I [DIR]") do |dir| loader.add(path: Pathname(dir)) end
end.parse!(opts)
loader.load(env: env)

def match(filter, name)
  if filter.end_with?("*")
    name.start_with?(filter[0, filter.size - 1]) || name == filter[0, filter.size-3]
  else
    filter == name
  end
end

TracePoint.trace :end do |tp|
  class_name = tp.self.name

  if class_name
    if filter.any? {|f| match(f, class_name) } && skips.none? {|f| match(f, class_name) }
      type_name = Ruby::Signature::Namespace.parse(class_name).absolute!.to_type_name
      if hooks.none? {|hook| hook.klass == tp.self }
        if env.find_class(type_name)
          logger.info "Setting up hooks for #{class_name}"
          hooks << Ruby::Signature::Test::Hook.install(env, tp.self, logger: logger).verify_all.raise_on_error!(raise_on_error)
        end
      end
    end
  end
end
