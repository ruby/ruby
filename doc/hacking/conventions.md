# Naming Conventions

This document gives an overview of naming conventions.

## Avoid Exposing `struct`

We should avoid exposing the internals of `struct` as a public interface unless absolutely necessary.

## Avoid Naming With `_t` Suffix

According to the [POSIX specification](https://pubs.opengroup.org/onlinepubs/9699919799/functions/V2_chap02.html), top level names ending in `_t` are reserved.

## Avoid Redundant Names

Avoid naming structs like this:

``` c
struct my_struct {} // redundant use of struct
struct my_struct_t {} // reserved use of _t
```

Both of these are missing `rb_` prefix which should be standard part of public interface.

## Public / Internal Interfaces

Generally speaking, for a given Ruby object, e.g. `IO::Buffer` you would expect to use names like this:

```c
// ruby/include/io/buffer.h

VALUE rb_io_buffer_new(void *base, size_t size, enum rb_io_buffer_flags flags);
```
