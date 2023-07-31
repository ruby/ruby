# Building

The following describes how to build YARP from source.

## Common

All of the source files match `src/**/*.c` and all of the headers match `include/**/*.h`.

The following flags should be used to compile YARP:

* `-std=c99` - Use the C99 standard
* `-Wall -Wconversion -Wextra -Wpedantic -Wundef` - Enable the warnings we care about
* `-Werror` - Treat warnings as errors
* `-fvisibility=hidden` - Hide all symbols by default

The following flags can be used to compile YARP:

* `-DHAVE_MMAP` - Should be passed if the system has the `mmap` function
* `-DHAVE_SNPRINTF` - Should be passed if the system has the `snprintf` function

## Shared

If you want to build YARP as a shared library and link against it, you should compile with:

* `-fPIC -shared` - Compile as a shared library
* `-DYP_EXPORT_SYMBOLS` - Export the symbols (by default nothing is exported)
