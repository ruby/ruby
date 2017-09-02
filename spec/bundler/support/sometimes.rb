# frozen_string_literal: true
module Sometimes
  def run_with_retries(example_to_run, retries)
    example = RSpec.current_example
    example.metadata[:retries] ||= retries

    retries.times do |t|
      example.metadata[:retried] = t + 1
      example.instance_variable_set(:@exception, nil)
      example_to_run.run
      break unless example.exception
    end

    if e = example.exception
      new_exception = e.exception(e.message + "[Retried #{retries} times]")
      new_exception.set_backtrace e.backtrace
      example.instance_variable_set(:@exception, new_exception)
    end
  end
end

RSpec.configure do |config|
  config.include Sometimes
  config.alias_example_to :sometimes, :sometimes => true
  config.add_setting :sometimes_retry_count, :default => 5

  config.around(:each, :sometimes => true) do |example|
    retries = example.metadata[:retries] || RSpec.configuration.sometimes_retry_count
    run_with_retries(example, retries)
  end

  config.after(:suite) do
    message = proc do |color, text|
      colored = RSpec::Core::Formatters::ConsoleCodes.wrap(text, color)
      notification = RSpec::Core::Notifications::MessageNotification.new(colored)
      formatter = RSpec.configuration.formatters.first
      formatter.message(notification) if formatter.respond_to?(:message)
    end

    retried_examples = RSpec.world.example_groups.map do |g|
      g.descendants.map do |d|
        d.filtered_examples.select do |e|
          e.metadata[:sometimes] && e.metadata.fetch(:retried, 1) > 1
        end
      end
    end.flatten

    message.call(retried_examples.empty? ? :green : :yellow, "\n\nRetried examples: #{retried_examples.count}")

    retried_examples.each do |e|
      message.call(:cyan, "  #{e.full_description}")
      path = RSpec::Core::Metadata.relative_path(e.location)
      message.call(:cyan, "  [#{e.metadata[:retried]}/#{e.metadata[:retries]}] " + path)
    end
  end
end
