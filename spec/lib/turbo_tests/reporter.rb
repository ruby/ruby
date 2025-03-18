# frozen_string_literal: true

module TurboTests
  class Reporter
    attr_writer :load_time

    def self.from_config(formatter_config, start_time, seed, seed_used)
      reporter = new(start_time, seed, seed_used)

      formatter_config.each do |config|
        name, outputs = config.values_at(:name, :outputs)

        outputs.map! do |filename|
          filename == "-" ? $stdout : File.open(filename, "w")
        end

        reporter.add(name, outputs)
      end

      reporter
    end

    attr_reader :pending_examples
    attr_reader :failed_examples

    def initialize(start_time, seed, seed_used)
      @formatters = []
      @pending_examples = []
      @failed_examples = []
      @all_examples = []
      @messages = []
      @start_time = start_time
      @seed = seed
      @seed_used = seed_used
      @load_time = 0
      @errors_outside_of_examples_count = 0
    end

    def add(name, outputs)
      outputs.each do |output|
        formatter_class =
          case name
          when "p", "progress"
            RSpec::Core::Formatters::ProgressFormatter
          when "d", "documentation"
            RSpec::Core::Formatters::DocumentationFormatter
          else
            Kernel.const_get(name)
          end

        @formatters << formatter_class.new(output)
      end
    end

    # Borrowed from RSpec::Core::Reporter
    # https://github.com/rspec/rspec-core/blob/5699fcdc4723087ff6139af55bd155ad9ad61a7b/lib/rspec/core/reporter.rb#L71
    def report(example_groups)
      start(example_groups)
      begin
        yield self
      ensure
        finish
      end
    end

    def start(example_groups, time=RSpec::Core::Time.now)
      @start = time
      @load_time = (@start - @start_time).to_f

      report_number_of_tests(example_groups)
      expected_example_count = example_groups.flatten(1).count

      delegate_to_formatters(:seed, RSpec::Core::Notifications::SeedNotification.new(@seed, @seed_used))
      delegate_to_formatters(:start, RSpec::Core::Notifications::StartNotification.new(expected_example_count, @load_time))
    end

    def report_number_of_tests(groups)
      name = ParallelTests::RSpec::Runner.test_file_name

      num_processes = groups.size
      num_tests = groups.map(&:size).sum
      tests_per_process = (num_processes == 0 ? 0 : num_tests.to_f / num_processes).round

      puts "#{num_processes} processes for #{num_tests} #{name}s, ~ #{tests_per_process} #{name}s per process"
    end

    def group_started(notification)
      delegate_to_formatters(:example_group_started, notification)
    end

    def group_finished
      delegate_to_formatters(:example_group_finished, nil)
    end

    def example_passed(example)
      delegate_to_formatters(:example_passed, example.notification)

      @all_examples << example
    end

    def example_pending(example)
      delegate_to_formatters(:example_pending, example.notification)

      @all_examples << example
      @pending_examples << example
    end

    def example_failed(example)
      delegate_to_formatters(:example_failed, example.notification)

      @all_examples << example
      @failed_examples << example
    end

    def message(message)
      delegate_to_formatters(:message, RSpec::Core::Notifications::MessageNotification.new(message))
      @messages << message
    end

    def error_outside_of_examples(error_message)
      @errors_outside_of_examples_count += 1
      message error_message
    end

    def finish
      end_time = RSpec::Core::Time.now

      @duration = end_time - @start_time
      delegate_to_formatters :stop, RSpec::Core::Notifications::ExamplesNotification.new(self)

      delegate_to_formatters :start_dump, RSpec::Core::Notifications::NullNotification
      delegate_to_formatters(:dump_pending,
        RSpec::Core::Notifications::ExamplesNotification.new(
          self
        ))
      delegate_to_formatters(:dump_failures,
        RSpec::Core::Notifications::ExamplesNotification.new(
          self
        ))
      delegate_to_formatters(:dump_summary,
        RSpec::Core::Notifications::SummaryNotification.new(
          end_time - @start_time,
          @all_examples,
          @failed_examples,
          @pending_examples,
          @load_time,
          @errors_outside_of_examples_count
        ))
      delegate_to_formatters(:seed,
        RSpec::Core::Notifications::SeedNotification.new(
          @seed,
          @seed_used,
        ))
    ensure
      delegate_to_formatters :close, RSpec::Core::Notifications::NullNotification
    end

    protected

    def delegate_to_formatters(method, *args)
      @formatters.each do |formatter|
        formatter.send(method, *args) if formatter.respond_to?(method)
      end
    end
  end
end
