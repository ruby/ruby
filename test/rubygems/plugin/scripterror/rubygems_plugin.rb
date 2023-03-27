# frozen_string_literal: true

TestGem::TEST_PLUGIN_EXCEPTION = :loaded
raise ScriptError.new("boom")
