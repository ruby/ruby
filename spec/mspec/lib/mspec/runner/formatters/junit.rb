require 'mspec/runner/formatters/yaml'

class JUnitFormatter < YamlFormatter
  def initialize(out = nil)
    super(out)
    @tests = []
  end

  def after(state = nil)
    super(state)
    @tests << {:test => state, :exception => false} unless exception?
  end

  def exception(exception)
    super(exception)
    @tests << {:test => exception, :exception => true}
  end

  def finish
    switch

    time = @timer.elapsed
    tests = @tally.counter.examples
    errors = @tally.counter.errors
    failures = @tally.counter.failures

    printf <<-XML

<?xml version="1.0" encoding="UTF-8" ?>
    <testsuites
        testCount="#{tests}"
        errorCount="#{errors}"
        failureCount="#{failures}"
        timeCount="#{time}" time="#{time}">
      <testsuite
          tests="#{tests}"
          errors="#{errors}"
          failures="#{failures}"
          time="#{time}"
          name="Spec Output For #{::RUBY_ENGINE} (#{::RUBY_VERSION})">
    XML
    @tests.each do |h|
      description = encode_for_xml h[:test].description

      printf <<-XML, "Spec", description, 0.0
        <testcase classname="%s" name="%s" time="%f">
      XML
      if h[:exception]
        outcome = h[:test].failure? ? "failure" : "error"
        message = encode_for_xml h[:test].message
        backtrace = encode_for_xml h[:test].backtrace
        print <<-XML
          <#{outcome} message="error in #{description}" type="#{outcome}">
            #{message}
            #{backtrace}
          </#{outcome}>
        XML
      end
      print <<-XML
        </testcase>
      XML
    end

    print <<-XML
      </testsuite>
    </testsuites>
    XML
  end

  private
  LT = "&lt;"
  GT = "&gt;"
  QU = "&quot;"
  AP = "&apos;"
  AM = "&amp;"
  TARGET_ENCODING = "ISO-8859-1"

  def encode_for_xml(str)
    encode_as_latin1(str).gsub("<", LT).gsub(">", GT).
      gsub('"', QU).gsub("'", AP).gsub("&", AM).
      tr("\x00-\x08", "?")
  end

  def encode_as_latin1(str)
    str.encode(TARGET_ENCODING, :undef => :replace, :invalid => :replace)
  end
end
