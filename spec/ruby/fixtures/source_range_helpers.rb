def source_range_values(range)
  [range.start_line, range.start_column, range.end_line, range.end_column]
end

def keep_source(value = true)
  always_keeps_source = RUBY_ENGINE == "truffleruby"
  if always_keeps_source
    if value
      yield
    else
      skip "This Ruby implementation always keeps the source in memory so cannot run specs which rely on not keeping it"
    end
  end

  return yield unless defined?(RubyVM.keep_script_lines)

  previous = RubyVM.keep_script_lines
  begin
    RubyVM.keep_script_lines = value
    yield
  ensure
    RubyVM.keep_script_lines = previous
  end
end

def source_range_source(source)
  raise "Expected 2 '$' to mark start and end of source_range" unless source.count('$') == 2
  from = source.byteindex('$')
  to = source.byteindex('$', from + 1)
  lines = source.lines
  from_line = 1 + source.byteslice(0, from).count("\n")
  from_column = lines[from_line-1].byteindex('$')
  to_line = 1 + source.byteslice(0, to).count("\n")
  if from_line == to_line
    to_column = lines[to_line-1].byteindex('$', from_column + 1) - 1
  else
    to_column = lines[to_line-1].byteindex('$')
  end

  eval_source = source.gsub('$', '')
  [eval_source, [from_line, from_column, to_line, to_column]]
end

# Use <<-RUBY and not <<~RUBY to keep some spaces in front to make it more representative of a Proc in some file
def check_source_range(marked_source)
  source, expected = source_range_source(marked_source)
  result = eval(source)
  range = result.source_range
  range.should.instance_of?(Ruby::SourceRange)
  source_range_values(range).should == expected

  # Check consistency with source_location start line
  result.source_location[1].should == expected[0]
end

def capture_backtrace_location_source_range(marked_source, prism_class, frame: 0)
  source, expected = source_range_source(marked_source)
  path = tmp("backtrace_location_source_range.rb")
  File.binwrite(path, source)
  absolute_path = File.realpath(path)

  exception = nil
  begin
    load path
  rescue Exception => error
    exception = error
  end

  raise "Expected source to raise an exception" unless exception

  total_frames = 0
  user_frames = 0
  while true
    location = exception.backtrace_locations.fetch(total_frames)
    if location.path.start_with?("<internal:")
      total_frames += 1
    else
      break if user_frames == frame
      user_frames += 1
      total_frames += 1
    end
  end

  range = location.source_range
  range.should.instance_of?(Ruby::SourceRange)
  source_range_values(range).should == expected

  # Check the Prism node at that location is the one we expect
  expected_class_name = "Prism::#{prism_class or raise "prism_class must be passed"}"

  # Also check #syntax_tree is consistent
  if location.respond_to?(:syntax_tree)
    node = location.syntax_tree
    node.class.name.should == expected_class_name
    source_range_values(node).should == expected
  end

  [location, range, path, absolute_path]
ensure
  rm_r path if path
end

def capture_backtrace_location_from_source(source, frame: 0)
  path = tmp("backtrace_location_source_range.rb")
  File.binwrite(path, source)

  exception = nil
  begin
    load path
  rescue Exception => error
    exception = error
  end

  raise "Expected source to raise an exception" unless exception

  [exception.backtrace_locations.fetch(frame), path]
end

def capture_eval_backtrace_location_source_range(marked_source, path, first_lineno)
  source, expected = source_range_source(marked_source)
  exception = nil

  begin
    eval(source, binding, path, first_lineno)
  rescue Exception => error
    exception = error
  end

  raise "Expected source to raise an exception" unless exception

  location = exception.backtrace_locations.first
  range = location.source_range
  range.should.instance_of?(Ruby::SourceRange)
  source_range_values(range).should == [
    expected[0] + first_lineno - 1,
    expected[1],
    expected[2] + first_lineno - 1,
    expected[3]
  ]

  [location, range]
end
