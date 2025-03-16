/*

This file is released under the terms of the MIT License. It is based on the
work of James Edward Anhalt III, with the original license listed below.

MIT License

Copyright (c) 2024,2025 Enrico Thierbach - https://github.com/radiospiel
Copyright (c) 2022 James Edward Anhalt III - https://github.com/jeaiii/itoa

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

#ifndef JEAIII_TO_TEXT_H_
#define JEAIII_TO_TEXT_H_

#include <stdint.h>

typedef uint_fast32_t u32_t;
typedef uint_fast64_t u64_t;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wshorten-64-to-32"

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wmissing-braces"

#define u32(x) ((u32_t)(x))
#define u64(x) ((u64_t)(x))

struct pair
{
    char dd[2];
};

#define cast_to_pair_ptr(b) ((struct pair*)(void*)(b))

static struct pair digits_dd[100] =
{
    { '0', '0' }, { '0', '1' }, { '0', '2' }, { '0', '3' }, { '0', '4' }, { '0', '5' }, { '0', '6' }, { '0', '7' }, { '0', '8' }, { '0', '9' },
    { '1', '0' }, { '1', '1' }, { '1', '2' }, { '1', '3' }, { '1', '4' }, { '1', '5' }, { '1', '6' }, { '1', '7' }, { '1', '8' }, { '1', '9' },
    { '2', '0' }, { '2', '1' }, { '2', '2' }, { '2', '3' }, { '2', '4' }, { '2', '5' }, { '2', '6' }, { '2', '7' }, { '2', '8' }, { '2', '9' },
    { '3', '0' }, { '3', '1' }, { '3', '2' }, { '3', '3' }, { '3', '4' }, { '3', '5' }, { '3', '6' }, { '3', '7' }, { '3', '8' }, { '3', '9' },
    { '4', '0' }, { '4', '1' }, { '4', '2' }, { '4', '3' }, { '4', '4' }, { '4', '5' }, { '4', '6' }, { '4', '7' }, { '4', '8' }, { '4', '9' },
    { '5', '0' }, { '5', '1' }, { '5', '2' }, { '5', '3' }, { '5', '4' }, { '5', '5' }, { '5', '6' }, { '5', '7' }, { '5', '8' }, { '5', '9' },
    { '6', '0' }, { '6', '1' }, { '6', '2' }, { '6', '3' }, { '6', '4' }, { '6', '5' }, { '6', '6' }, { '6', '7' }, { '6', '8' }, { '6', '9' },
    { '7', '0' }, { '7', '1' }, { '7', '2' }, { '7', '3' }, { '7', '4' }, { '7', '5' }, { '7', '6' }, { '7', '7' }, { '7', '8' }, { '7', '9' },
    { '8', '0' }, { '8', '1' }, { '8', '2' }, { '8', '3' }, { '8', '4' }, { '8', '5' }, { '8', '6' }, { '8', '7' }, { '8', '8' }, { '8', '9' },
    { '9', '0' }, { '9', '1' }, { '9', '2' }, { '9', '3' }, { '9', '4' }, { '9', '5' }, { '9', '6' }, { '9', '7' }, { '9', '8' }, { '9', '9' },
};

#define NUL 'x'

static struct pair digits_fd[100] =
{
    { '0', NUL }, { '1', NUL }, { '2', NUL }, { '3', NUL }, { '4', NUL }, { '5', NUL }, { '6', NUL }, { '7', NUL }, { '8', NUL }, { '9', NUL },
    { '1', '0' }, { '1', '1' }, { '1', '2' }, { '1', '3' }, { '1', '4' }, { '1', '5' }, { '1', '6' }, { '1', '7' }, { '1', '8' }, { '1', '9' },
    { '2', '0' }, { '2', '1' }, { '2', '2' }, { '2', '3' }, { '2', '4' }, { '2', '5' }, { '2', '6' }, { '2', '7' }, { '2', '8' }, { '2', '9' },
    { '3', '0' }, { '3', '1' }, { '3', '2' }, { '3', '3' }, { '3', '4' }, { '3', '5' }, { '3', '6' }, { '3', '7' }, { '3', '8' }, { '3', '9' },
    { '4', '0' }, { '4', '1' }, { '4', '2' }, { '4', '3' }, { '4', '4' }, { '4', '5' }, { '4', '6' }, { '4', '7' }, { '4', '8' }, { '4', '9' },
    { '5', '0' }, { '5', '1' }, { '5', '2' }, { '5', '3' }, { '5', '4' }, { '5', '5' }, { '5', '6' }, { '5', '7' }, { '5', '8' }, { '5', '9' },
    { '6', '0' }, { '6', '1' }, { '6', '2' }, { '6', '3' }, { '6', '4' }, { '6', '5' }, { '6', '6' }, { '6', '7' }, { '6', '8' }, { '6', '9' },
    { '7', '0' }, { '7', '1' }, { '7', '2' }, { '7', '3' }, { '7', '4' }, { '7', '5' }, { '7', '6' }, { '7', '7' }, { '7', '8' }, { '7', '9' },
    { '8', '0' }, { '8', '1' }, { '8', '2' }, { '8', '3' }, { '8', '4' }, { '8', '5' }, { '8', '6' }, { '8', '7' }, { '8', '8' }, { '8', '9' },
    { '9', '0' }, { '9', '1' }, { '9', '2' }, { '9', '3' }, { '9', '4' }, { '9', '5' }, { '9', '6' }, { '9', '7' }, { '9', '8' }, { '9', '9' },
};

#undef NUL

static u64_t mask24 = (u64(1) << 24) - 1;
static u64_t mask32 = (u64(1) << 32) - 1;
static u64_t mask57 = (u64(1) << 57) - 1;

static 
char* to_text_from_ulong(char* b, u64_t n) {
    if (n < u32(1e2))
    {
        *cast_to_pair_ptr(b) = digits_fd[n];
        return n < 10 ? b + 1 : b + 2;
    }
    if (n < u32(1e6))
    {
        if (n < u32(1e4))
        {
            u32_t f0 = u32(10 * (1 << 24) / 1e3 + 1) * n;
            *cast_to_pair_ptr(b) = digits_fd[f0 >> 24];
            b -= n < u32(1e3);
            u32_t f2 = (f0 & mask24) * 100;
            *cast_to_pair_ptr(b + 2) = digits_dd[f2 >> 24];
            return b + 4;
        }
        u64_t f0 = u64(10 * (1ull << 32ull)/ 1e5 + 1) * n;
        *cast_to_pair_ptr(b) = digits_fd[f0 >> 32];
        b -= n < u32(1e5);
        u64_t f2 = (f0 & mask32) * 100;
        *cast_to_pair_ptr(b + 2) = digits_dd[f2 >> 32];
        u64_t f4 = (f2 & mask32) * 100;
        *cast_to_pair_ptr(b + 4) = digits_dd[f4 >> 32];
        return b + 6;
    }
    if (n < u64(1ull << 32ull))
    {
        if (n < u32(1e8))
        {
            u64_t f0 = u64(10 * (1ull << 48ull) / 1e7 + 1) * n >> 16;
            *cast_to_pair_ptr(b) = digits_fd[f0 >> 32];
            b -= n < u32(1e7);
            u64_t f2 = (f0 & mask32) * 100;
            *cast_to_pair_ptr(b + 2) = digits_dd[f2 >> 32];
            u64_t f4 = (f2 & mask32) * 100;
            *cast_to_pair_ptr(b + 4) = digits_dd[f4 >> 32];
            u64_t f6 = (f4 & mask32) * 100;
            *cast_to_pair_ptr(b + 6) = digits_dd[f6 >> 32];
            return b + 8;
        }
        u64_t f0 = u64(10 * (1ull << 57ull) / 1e9 + 1) * n;
        *cast_to_pair_ptr(b) = digits_fd[f0 >> 57];
        b -= n < u32(1e9);
        u64_t f2 = (f0 & mask57) * 100;
        *cast_to_pair_ptr(b + 2) = digits_dd[f2 >> 57];
        u64_t f4 = (f2 & mask57) * 100;
        *cast_to_pair_ptr(b + 4) = digits_dd[f4 >> 57];
        u64_t f6 = (f4 & mask57) * 100;
        *cast_to_pair_ptr(b + 6) = digits_dd[f6 >> 57];
        u64_t f8 = (f6 & mask57) * 100;
        *cast_to_pair_ptr(b + 8) = digits_dd[f8 >> 57];
        return b + 10;
    }

    // if we get here U must be u64 but some compilers don't know that, so reassign n to a u64 to avoid warnings
    u32_t z = n % u32(1e8);
    u64_t u = n / u32(1e8);

    if (u < u32(1e2))
    {
        // u can't be 1 digit (if u < 10 it would have been handled above as a 9 digit 32bit number)
        *cast_to_pair_ptr(b) = digits_dd[u];
        b += 2;
    }
    else if (u < u32(1e6))
    {
        if (u < u32(1e4))
        {
            u32_t f0 = u32(10 * (1 << 24) / 1e3 + 1) * u;
            *cast_to_pair_ptr(b) = digits_fd[f0 >> 24];
            b -= u < u32(1e3);
            u32_t f2 = (f0 & mask24) * 100;
            *cast_to_pair_ptr(b + 2) = digits_dd[f2 >> 24];
            b += 4;
        }
        else
        {
            u64_t f0 = u64(10 * (1ull << 32ull) / 1e5 + 1) * u;
            *cast_to_pair_ptr(b) = digits_fd[f0 >> 32];
            b -= u < u32(1e5);
            u64_t f2 = (f0 & mask32) * 100;
            *cast_to_pair_ptr(b + 2) = digits_dd[f2 >> 32];
            u64_t f4 = (f2 & mask32) * 100;
            *cast_to_pair_ptr(b + 4) = digits_dd[f4 >> 32];
            b += 6;
        }
    }
    else if (u < u32(1e8))
    {
        u64_t f0 = u64(10 * (1ull << 48ull) / 1e7 + 1) * u >> 16;
        *cast_to_pair_ptr(b) = digits_fd[f0 >> 32];
        b -= u < u32(1e7);
        u64_t f2 = (f0 & mask32) * 100;
        *cast_to_pair_ptr(b + 2) = digits_dd[f2 >> 32];
        u64_t f4 = (f2 & mask32) * 100;
        *cast_to_pair_ptr(b + 4) = digits_dd[f4 >> 32];
        u64_t f6 = (f4 & mask32) * 100;
        *cast_to_pair_ptr(b + 6) = digits_dd[f6 >> 32];
        b += 8;
    }
    else if (u < u64(1ull << 32ull))
    {
        u64_t f0 = u64(10 * (1ull << 57ull) / 1e9 + 1) * u;
        *cast_to_pair_ptr(b) = digits_fd[f0 >> 57];
        b -= u < u32(1e9);
        u64_t f2 = (f0 & mask57) * 100;
        *cast_to_pair_ptr(b + 2) = digits_dd[f2 >> 57];
        u64_t f4 = (f2 & mask57) * 100;
        *cast_to_pair_ptr(b + 4) = digits_dd[f4 >> 57];
        u64_t f6 = (f4 & mask57) * 100;
        *cast_to_pair_ptr(b + 6) = digits_dd[f6 >> 57];
        u64_t f8 = (f6 & mask57) * 100;
        *cast_to_pair_ptr(b + 8) = digits_dd[f8 >> 57];
        b += 10;
    }
    else
    {
        u32_t y = u % u32(1e8);
        u /= u32(1e8);

        // u is 2, 3, or 4 digits (if u < 10 it would have been handled above)
        if (u < u32(1e2))
        {
            *cast_to_pair_ptr(b) = digits_dd[u];
            b += 2;
        }
        else
        {
            u32_t f0 = u32(10 * (1 << 24) / 1e3 + 1) * u;
            *cast_to_pair_ptr(b) = digits_fd[f0 >> 24];
            b -= u < u32(1e3);
            u32_t f2 = (f0 & mask24) * 100;
            *cast_to_pair_ptr(b + 2) = digits_dd[f2 >> 24];
            b += 4;
        }
        // do 8 digits
        u64_t f0 = (u64((1ull << 48ull) / 1e6 + 1) * y >> 16) + 1;
        *cast_to_pair_ptr(b) = digits_dd[f0 >> 32];
        u64_t f2 = (f0 & mask32) * 100;
        *cast_to_pair_ptr(b + 2) = digits_dd[f2 >> 32];
        u64_t f4 = (f2 & mask32) * 100;
        *cast_to_pair_ptr(b + 4) = digits_dd[f4 >> 32];
        u64_t f6 = (f4 & mask32) * 100;
        *cast_to_pair_ptr(b + 6) = digits_dd[f6 >> 32];
        b += 8;
    }
    // do 8 digits
    u64_t f0 = (u64((1ull << 48ull) / 1e6 + 1) * z >> 16) + 1;
    *cast_to_pair_ptr(b) = digits_dd[f0 >> 32];
    u64_t f2 = (f0 & mask32) * 100;
    *cast_to_pair_ptr(b + 2) = digits_dd[f2 >> 32];
    u64_t f4 = (f2 & mask32) * 100;
    *cast_to_pair_ptr(b + 4) = digits_dd[f4 >> 32];
    u64_t f6 = (f4 & mask32) * 100;
    *cast_to_pair_ptr(b + 6) = digits_dd[f6 >> 32];
    return b + 8;
}

#undef u32
#undef u64

#pragma clang diagnostic pop
#pragma GCC diagnostic pop

#endif // JEAIII_TO_TEXT_H_

