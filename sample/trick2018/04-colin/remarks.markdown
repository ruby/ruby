### Remarks

Create a Ruby file that requires entry.rb with a series of test in it the run the file using ruby:

```
ruby name_of_test_file.rb
```

To create a test, call 🤔 with two arguments. The first is a string describing what this tests, the second argument is the test assertion. If the assertion is truthy, the test passes. If the assertion is falsy, the test fails.

```
string_1 = "Hello world!"
string_2 = "This is not the same!"

🤔 "The two strings are equal",
  string_1 == string_2
```

To create a group of tests under a label, call 🤔 with a string describing the group and a block containing the tests in that group.

```
🤔 "This is a group of tests" do
  # Add other groups and/or tests here.
end
```

Here is an example:

```
require './entry'

🤔 "Math" do
  🤔 "Addition" do
    🤔 "One plus one equals two.",
      1+1 == 2
    🤔 "One plus one equals eleven. (This should fail.)",
      1+1 == 11
  end

  🤔 "Subtraction" do
    🤔 "One minus one equals zero.",
      1-1 == 0
    🤔 "Ten minus one equal nine.",
      10-1 == 9
  end
end
```

It has been tested with the following Ruby versions:

* ruby 2.5.1p57 (2018-03-29 revision 63029) [x86_64-darwin17]
* ruby 2.3.0p0 (2015-12-25 revision 53290) [x86_64-darwin15]
* If you replace `b&.[]` with `b&&b[]` it will work with ruby 2.0.0 as well, but it will be one character longer.


### Description

The goal was to create a testing library where the test files looked good and the output looked good in as few characters as possible. The result is 68 characters and has one method to handle everything.

### Limitation

Your terminal program must support Unicode characters for the test output to look correct. If your terminal does not support Unicode, simply replace the 🚫 in the code with whatever character you want to prefix failing tests.
