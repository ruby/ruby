module LaunchableFormatter
  def self.extend_object(obj)
    super
    obj.init
  end

  def self.setDir(dir)
    @@path = File.join(dir, "#{rand.to_s}.json")
    self
  end

  def init
    @timer = nil
    @tests = []
  end

  def before(state = nil)
    super
    @timer = TimerAction.new
    @timer.start
  end

  def after(state = nil)
    super
    @timer.finish
    file = MSpec.file
    return if file.nil? || state&.example.nil? || exception?

    @tests << {:test => state, :file => file, :exception => false, duration: @timer.elapsed}
  end

  def exception(exception)
    super
    @timer.finish
    file = MSpec.file
    return if file.nil?

    @tests << {:test => exception, :file => file, :exception => true, duration: @timer.elapsed}
  end

  def finish
    super

    require_relative '../../../../../../tool/lib/launchable'

    @writer = writer = Launchable::JsonStreamWriter.new(@@path)
    @writer.write_array('testCases')
    at_exit {
      @writer.close
    }

    repo_path = File.expand_path("#{__dir__}/../../../../../../")

    @tests.each do |t|
      testcase = t[:test].description
      relative_path = t[:file].delete_prefix("#{repo_path}/")
      # The test path is a URL-encoded representation.
      # https://github.com/launchableinc/cli/blob/v1.81.0/launchable/testpath.py#L18
      test_path = {file: relative_path, testcase: testcase}.map{|key, val|
        "#{encode_test_path_component(key)}=#{encode_test_path_component(val)}"
      }.join('#')

      status = 'TEST_PASSED'
      if t[:exception]
        message = t[:test].message
        backtrace = t[:test].backtrace
        e = "#{message}\n#{backtrace}"
        status = 'TEST_FAILED'
      end

      @writer.write_object(
        {
          testPath: test_path,
          status: status,
          duration: t[:duration],
          createdAt: Time.now.to_s,
          stderr: e,
          stdout: nil
        }
      )
    end
  end

  private
  def encode_test_path_component component
    component.to_s.gsub('%', '%25').gsub('=', '%3D').gsub('#', '%23').gsub('&', '%26').tr("\x00-\x08", "")
  end
end
