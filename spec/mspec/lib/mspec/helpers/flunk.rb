def flunk(msg = "This example is a failure")
  SpecExpectation.fail_with "Failed:", msg
end
