/**
 * @file compiler/fallthrough.h
 */
#ifndef PRISM_COMPILER_FALLTHROUGH_H
#define PRISM_COMPILER_FALLTHROUGH_H

/**
 * We use -Wimplicit-fallthrough to guard potentially unintended fall-through
 * between cases of a switch. Use PRISM_FALLTHROUGH to explicitly annotate cases
 * where the fallthrough is intentional.
 */
#if defined(__STDC_VERSION__) && __STDC_VERSION__ >= 202311L /* C23 or later */
    #define PRISM_FALLTHROUGH [[fallthrough]];
#elif defined(__GNUC__) || defined(__clang__)
    #define PRISM_FALLTHROUGH __attribute__((fallthrough));
#elif defined(_MSC_VER)
    #define PRISM_FALLTHROUGH __fallthrough;
#else
    #define PRISM_FALLTHROUGH
#endif

#endif
