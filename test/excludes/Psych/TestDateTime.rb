exclude(:test_new_datetime, <<MSG)
Undefined behavior of YAML spec, no definitions for pre Gregorian dates.
https://github.com/yaml/yaml/issues/69
MSG
