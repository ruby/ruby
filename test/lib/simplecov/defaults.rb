# Load default formatter gem
require 'simplecov-html'

# Gotta stash this a-s-a-p, see the CommandGuesser class and i.e. #110 for further info
SimpleCov::CommandGuesser.original_run_command = "#{$0} #{ARGV.join(" ")}"

at_exit do

  if $! # was an exception thrown?
    # if it was a SystemExit, use the accompanying status
    # otherwise set a non-zero status representing termination by some other exception
    # (see github issue 41)
    @exit_status = $!.is_a?(SystemExit) ? $!.status : SimpleCov::ExitCodes::EXCEPTION
  else
    # Store the exit status of the test run since it goes away after calling the at_exit proc...
    @exit_status = SimpleCov::ExitCodes::SUCCESS
  end

  SimpleCov.at_exit.call

  if SimpleCov.result? # Result has been computed
    covered_percent = SimpleCov.result.covered_percent.round(2)

    if @exit_status == SimpleCov::ExitCodes::SUCCESS # No other errors
      if covered_percent < SimpleCov.minimum_coverage
        $stderr.puts "Coverage (%.2f%%) is below the expected minimum coverage (%.2f%%)." % \
                     [covered_percent, SimpleCov.minimum_coverage]

        @exit_status = SimpleCov::ExitCodes::MINIMUM_COVERAGE

      elsif (last_run = SimpleCov::LastRun.read)
        diff = last_run['result']['covered_percent'] - covered_percent
        if diff > SimpleCov.maximum_coverage_drop
          $stderr.puts "Coverage has dropped by %.2f%% since the last time (maximum allowed: %.2f%%)." % \
                       [diff, SimpleCov.maximum_coverage_drop]

          @exit_status = SimpleCov::ExitCodes::MAXIMUM_COVERAGE_DROP
        end
      end
    end

    SimpleCov::LastRun.write(:result => {:covered_percent => covered_percent})
  end

  # Force exit with stored status (see github issue #5)
  # unless it's nil or 0 (see github issue #281)
  Kernel.exit @exit_status if @exit_status && @exit_status > 0
end

# Autoload config from ~/.simplecov if present
require 'etc'
home_dir = Dir.home || Etc.getpwuid.dir || (user = ENV["USER"] && Dir.home(user))
if home_dir
  global_config_path = File.join(home_dir, '.simplecov')
  load global_config_path if File.exist?(global_config_path)
end

# Autoload config from .simplecov if present
config_path = File.join(SimpleCov.root, '.simplecov')
load config_path if File.exist?(config_path)
