/*
 * Copyright (C) 2020 HAW Hamburg
 *
 * This file is subject to the terms and conditions of the GNU Lesser
 * General Public License v2.1. See the file LICENSE in the top level
 * directory for more details.
 */

/**
 * @ingroup     tests
 * @{
 *
 * @file
 * @brief       RIOT timer benchmarks
 *
 * @author      M. Aiman Ismail <muhammadaimanbin.ismail@haw-hamburg.de>

 *
 * @}
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "periph/gpio.h"
#include "test_utils/expect.h"
#include "fmt.h"

#include "shell.h"
#include "test_helpers.h"
#include "sc_args.h"
#include "random.h"
#include "timex.h"

#define ENABLE_DEBUG (0)
#include "debug.h"
#include "log.h"

#ifndef PARSER_DEV_NUM
#define PARSER_DEV_NUM 0
#endif

#define TEST_REPEAT     (50)
#define TEST_MAX_TIMERS (100)

#define TEST_GPIO           GPIO_PIN(HIL_DUT_IC_PORT, HIL_DUT_IC_PIN)
#define START_TIMER()       gpio_set(TEST_GPIO)
#define STOP_TIMER()        gpio_clear(TEST_GPIO)

#ifndef MODULE_ZTIMER
#include "xtimer.h"

#define TIMER_T                     xtimer_t
#define TIMER_NOW()                 xtimer_now_usec()
#define TIMER_SET(timer, duration)  xtimer_set(timer, duration)
#define TIMER_REMOVE(timer)         xtimer_remove(timer)
#define TIMER_SLEEP(duration)       xtimer_usleep(duration)
#define TIMER_PERIODIC_WAKEUP(last_wakeup, duration)  \
    xtimer_periodic_wakeup(last_wakeup, duration)
#else
#include "ztimer.h"

#define TIMER_T                     ztimer_t
#define ZTIMER_CLOCK                ZTIMER_USEC
#define TIMER_NOW()                 ztimer_now(ZTIMER_CLOCK)
#define TIMER_SET(timer, duration)  ztimer_set(ZTIMER_CLOCK, timer, duration)
#define TIMER_REMOVE(timer)         ztimer_remove(ZTIMER_CLOCK, timer)
#define TIMER_SLEEP(duration)       ztimer_sleep(ZTIMER_CLOCK, duration)
#define TIMER_PERIODIC_WAKEUP(last_wakeup, duration)  \
    ztimer_periodic_wakeup(ZTIMER_CLOCK, last_wakeup, duration)
#endif

char printbuf[SHELL_DEFAULT_BUFSIZE] = { 0 };
uint8_t in_buf[64];
uint8_t out_buf[64];

uint32_t dut_results[TEST_REPEAT] = { 0 };
static TIMER_T test_timers[TEST_MAX_TIMERS];

/* Default is whatever, just some small delay if the user forgets to initialize */
static uint32_t spin_max = 64;

/************************
* HELPER FUNCTIONS
************************/

/**
 * @brief   Busy wait (spin) for the given number of loop iterations
 */
static void spin(uint32_t limit)
{
    /* Platform independent busy wait loop, should never be optimized out
     * because of the volatile asm statement */
    while (limit--) {
        __asm__ volatile ("");
    }
}

void spin_random_delay(void)
{
    uint32_t limit = random_uint32_range(0, spin_max);

    spin(limit);
}

/************************
* OVERHEAD
************************/

#define OVERHEAD_SPREAD (1000UL)

static unsigned overhead_triggers = 0;

void cleanup_overhead(void)
{
    for (unsigned i = 0; i < TEST_REPEAT; ++i) {
        dut_results[i] = 0;
    }

    for (unsigned i = 0; i < TEST_MAX_TIMERS; ++i) {
        TIMER_REMOVE(&test_timers[i]);
    }
}

int overhead_gpio_cmd(int argc, char **argv)
{
    (void)argc;
    (void)argv;

    sprintf(printbuf, "gpio overhead");
    print_cmd(PARSER_DEV_NUM, printbuf);
    for (int i = 0; i < TEST_REPEAT; i++) {
        START_TIMER();
        STOP_TIMER();
        spin_random_delay();
    }
    print_result(PARSER_DEV_NUM, TEST_RESULT_SUCCESS);
    return 0;
}

int overhead_timer_now(int argc, char **argv)
{
    (void)argc;
    (void)argv;

    sprintf(printbuf, "overhead timer now");
    print_cmd(PARSER_DEV_NUM, printbuf);

    for (unsigned i = 0; i < TEST_REPEAT; ++i) {
        START_TIMER();
        TIMER_NOW();
        STOP_TIMER();
        spin_random_delay();
    }

    print_result(PARSER_DEV_NUM, TEST_RESULT_SUCCESS);
    return 0;
}

static void _overhead_callback(void *arg)
{
    unsigned *triggers = arg;

    *triggers += 1;
}

uint32_t _delay(unsigned n)
{
    return 1 * US_PER_SEC + (OVERHEAD_SPREAD * n);
}

int timer_overhead_timer_cmd(int argc, char **argv)
{
    if (argc < 3) {
        print_result(PARSER_DEV_NUM, TEST_RESULT_ERROR);
        return -1;
    }

    const char *method = argv[1];
    const char *pos = argv[2];

    sprintf(printbuf, "timer overhead: %s %s timer", method, pos);
    print_cmd(PARSER_DEV_NUM, printbuf);

    sprintf(printbuf, "%u", TEST_MAX_TIMERS);
    print_data_dict_str(PARSER_DEV_NUM, "timer count", printbuf);

    sprintf(printbuf, "%u", TEST_REPEAT);
    print_data_dict_str(PARSER_DEV_NUM, "sample count", printbuf);

    /* init the timers */
    for (unsigned i = 0; i < TEST_MAX_TIMERS; ++i) {
        test_timers[i].callback = _overhead_callback;
        test_timers[i].arg = &overhead_triggers;
    }

    unsigned timer_idx = -1;
    if (strcmp(pos, "first") == 0) {
        timer_idx = 0;
    }
    else if (strcmp(pos, "middle") == 0) {
        timer_idx = (TEST_MAX_TIMERS / 2) - 1;
    }
    else if (strcmp(pos, "last") == 0) {
        timer_idx = TEST_MAX_TIMERS - 1;
    }
    else {
        goto error;
    }

    if (strcmp(method, "set") == 0) {
        for (unsigned n = 0; n < TEST_REPEAT; ++n) {
            /* set all but the last timer */
            for (unsigned i = 0; i < timer_idx; ++i) {
                TIMER_SET(&test_timers[i], _delay(i));
            }

            /* set the last timer */
            START_TIMER();
            TIMER_SET(&test_timers[timer_idx], _delay(timer_idx));
            STOP_TIMER();
            spin_random_delay();
        }
    }
    else if (strcmp(method, "remove") == 0) {
        for (unsigned n = 0; n < TEST_REPEAT; ++n) {
            /* set timers until timer_idx */
            for (unsigned i = 0; i <= timer_idx; ++i) {
                TIMER_SET(&test_timers[i], _delay(i));
            }

            /* remove the timer at timer_idx */
            START_TIMER();
            TIMER_REMOVE(&test_timers[timer_idx]);
            STOP_TIMER();
            spin_random_delay();
        }
    }
    else {
error:
        cleanup_overhead();
        print_result(PARSER_DEV_NUM, TEST_RESULT_ERROR);
        return -1;
    }

    expect(!overhead_triggers);

    cleanup_overhead();

    print_result(PARSER_DEV_NUM, TEST_RESULT_SUCCESS);
    return 0;
}

/************************
* ACCURACY
************************/

typedef struct accuracy_cb_params {
    volatile bool triggered;    /* volatile avoid loop optimised */
    uint32_t start;
    uint32_t *diff;
} accuracy_params_t;

void _sleep_accuracy_timer_set_cb(void *arg)
{
    accuracy_params_t *params = (accuracy_params_t *)arg;

    if (params->start) {
        *(params->diff) = TIMER_NOW() - params->start;
    }
    else {
        STOP_TIMER();
    }
    params->triggered = true;
}

int sleep_accuracy_timer_set_cmd(int argc, char **argv)
{
    if (argc < 2) {
        print_result(PARSER_DEV_NUM, TEST_RESULT_ERROR);
        return -1;
    }

    int sleeptime = strtol(argv[1], NULL, 10);
    if (sleeptime < 0) {
        print_result(PARSER_DEV_NUM, TEST_RESULT_ERROR);
        return -1;
    }

    sprintf(printbuf, "sleep_accuracy: timer_sleep(%s)", argv[1]);
    print_cmd(PARSER_DEV_NUM, printbuf);

    accuracy_params_t params = { 0 };

    TIMER_T timer = { 0 };
    timer.callback = _sleep_accuracy_timer_set_cb;
    timer.arg = &params;

    /* measure using dut timer (xtimer/ztimer) */
    for (unsigned i = 0; i < TEST_REPEAT; i++) {
        params.diff = &dut_results[i];
        params.start = TIMER_NOW();
        TIMER_SET(&timer, sleeptime);
        while (!params.triggered) {}
        params.triggered = false;
        spin_random_delay();
    }

    /* reset, we're not using dut timer for measurement anymore */
    TIMER_REMOVE(&timer);
    params.start = 0;
    params.diff = NULL;
    params.triggered = false;

    /* measure using PHiLIP */
    for (unsigned i = 0; i < TEST_REPEAT; i++) {
        START_TIMER();
        TIMER_SET(&timer, sleeptime);
        while (!params.triggered) {}
        params.triggered = false;
        spin_random_delay();
    }

    TIMER_REMOVE(&timer);

    /* print dut result to shell */
    for (unsigned i = 0; i < ARRAY_SIZE(dut_results); ++i) {
        sprintf(printbuf, "%" PRIu32 "", dut_results[i]);
        print_data_dict_str(PARSER_DEV_NUM, "dut-result", printbuf);
    }

    print_result(PARSER_DEV_NUM, TEST_RESULT_SUCCESS);
    return 0;
}

int sleep_accuracy_timer_sleep_cmd(int argc, char **argv)
{
    if (argc < 2) {
        print_result(PARSER_DEV_NUM, TEST_RESULT_ERROR);
        return -1;
    }

    sprintf(printbuf, "sleep_accuracy: timer_sleep(%s)", argv[1]);
    print_cmd(PARSER_DEV_NUM, printbuf);

    int sleeptime = strtol(argv[1], NULL, 10);
    if (sleeptime < 0) {
        print_result(PARSER_DEV_NUM, TEST_RESULT_ERROR);
        return -1;
    }

    /* measure using dut timer (xtimer/ztimer) */
    for (unsigned i = 0; i < TEST_REPEAT; i++) {
        uint32_t start = TIMER_NOW();
        TIMER_SLEEP(sleeptime);
        dut_results[i] = TIMER_NOW() - start;
        spin_random_delay();
    }

    /* measure using PHiLIP */
    for (unsigned i = 0; i < TEST_REPEAT; i++) {
        START_TIMER();
        TIMER_SLEEP(sleeptime);
        STOP_TIMER();
        spin_random_delay();
    }

    /* print dut result to shell */
    for (unsigned i = 0; i < ARRAY_SIZE(dut_results); ++i) {
        sprintf(printbuf, "%" PRIu32 "", dut_results[i]);
        print_data_dict_str(PARSER_DEV_NUM, "dut-result", printbuf);
    }

    print_result(PARSER_DEV_NUM, TEST_RESULT_SUCCESS);
    return 0;
}

/************************
* JITTER
************************/

#define JITTER_MIN_OFFSET   (10U)
#define JITTER_MAX_OFFSET   (100U)
#define JITTER_FOCUS (100 * MS_PER_SEC) /* which interval result to record */

struct sleep_jitter_params {
    TIMER_T *timer;
    uint32_t duration;
} sleep_jitter_params_t;

static struct sleep_jitter_params jitter_params[TEST_MAX_TIMERS];
static volatile bool jitter_end;

void cleanup_jitter(void)
{
    for (unsigned i = 0; i < TEST_MAX_TIMERS; ++i) {
        TIMER_REMOVE(jitter_params->timer);
    }
}

static void _sleep_jitter_cb(void *arg)
{
    if (!jitter_end) {
        struct sleep_jitter_params *params = (struct sleep_jitter_params *)arg;
        TIMER_SET(params->timer, params->duration);
    }
}

int sleep_jitter_cmd(int argc, char **argv)
{
    print_cmd(PARSER_DEV_NUM, "sleep_jitter");

    if (argc < 3) {
        print_data_str(PARSER_DEV_NUM, "Not enough arguments");
        print_result(PARSER_DEV_NUM, TEST_RESULT_ERROR);
        return -1;
    }

    jitter_end = false;
    unsigned bg_timers = atoi(argv[1]);     /* no. of timers to run in background */
    unsigned divisor = atoi(argv[2]);       /* background timer divisor */
    DEBUG("divisor: %u; bg_timers: %u\n", divisor, bg_timers);

    if (bg_timers > ARRAY_SIZE(jitter_params)) {
        print_data_str(PARSER_DEV_NUM,
                       "bg_timers exceeded allocated jitter_params");
        print_result(PARSER_DEV_NUM, TEST_RESULT_ERROR);
        return -1;
    }

    sprintf(printbuf, "%lu", JITTER_FOCUS);
    print_data_dict_str(PARSER_DEV_NUM, "focus", printbuf);

    DEBUG("size jitter_params: %d\n", ARRAY_SIZE(jitter_params));

    /* setup the background timers, if any */
    for (unsigned i = 0; i < bg_timers; i++) {
        jitter_params[i].timer = &test_timers[i];
        jitter_params[i].duration = random_uint32_range(
            JITTER_MIN_OFFSET  * MS_PER_SEC,
            (JITTER_MAX_OFFSET + 1) * MS_PER_SEC) / divisor;
        sprintf(printbuf, "%" PRIu32 "", (uint32_t)jitter_params[i].duration);
        print_data_dict_str(PARSER_DEV_NUM, "interval", printbuf);

        TIMER_T *timer = jitter_params[i].timer;
        timer->callback = _sleep_jitter_cb;
        timer->arg = &jitter_params[i];
        TIMER_SET(timer, jitter_params[i].duration);
    }

    /* now start the timer that we gonna record */
#ifndef MODULE_ZTIMER
    xtimer_ticks32_t now = xtimer_now();
#else
    uint32_t now = ztimer_now(ZTIMER_CLOCK);
#endif
    TIMER_PERIODIC_WAKEUP(&now, 3 * US_PER_SEC);

    for (unsigned i = 0; i < TEST_REPEAT; i++) {
        START_TIMER();
        TIMER_PERIODIC_WAKEUP(&now, JITTER_FOCUS);
        STOP_TIMER();
        DEBUG("FOCUS TIMER WOKE UP\n");
    }
    DEBUG("\n");

    jitter_end = true;

    cleanup_jitter();

    print_result(PARSER_DEV_NUM, TEST_RESULT_SUCCESS);
    return 0;
}

/************************
* DRIFT
************************/

int drift_cmd(int argc, char **argv)
{
    if (argc < 2) {
        print_data_str(PARSER_DEV_NUM, "Not enough arguments");
        print_result(PARSER_DEV_NUM, TEST_RESULT_ERROR);
        return -1;
    }

    uint32_t duration = atoi(argv[1]);  /* duration in microseconds */
    sprintf(printbuf, "drift: %" PRIu32 " us", duration);
    print_cmd(PARSER_DEV_NUM, printbuf);

    uint32_t start = TIMER_NOW();
    START_TIMER();
    TIMER_SLEEP(duration);
    uint32_t diff = TIMER_NOW() - start;
    STOP_TIMER();

    uint32_t us = diff % US_PER_SEC;
    uint32_t sec = diff / US_PER_SEC;

    sprintf(printbuf, "%" PRIu32 ".%06" PRIu32 "", sec, us);
    print_data_str(PARSER_DEV_NUM, printbuf);

    print_result(PARSER_DEV_NUM, TEST_RESULT_SUCCESS);
    return 0;
}

int cmd_get_timer_version(int argc, char **argv)
{
    (void)argv;
    (void)argc;

#ifdef MODULE_ZTIMER
    sprintf(printbuf, "ztimer");
#else
    sprintf(printbuf, "xtimer");
#endif
    print_data_str(PARSER_DEV_NUM, printbuf);
    print_result(PARSER_DEV_NUM, TEST_RESULT_SUCCESS);
    return 0;
}

int cmd_get_metadata(int argc, char **argv)
{
    (void)argv;
    (void)argc;

    print_data_str(PARSER_DEV_NUM, RIOT_BOARD);
    print_data_str(PARSER_DEV_NUM, RIOT_VERSION);
    print_data_str(PARSER_DEV_NUM, RIOT_APPLICATION);
    print_result(PARSER_DEV_NUM, TEST_RESULT_SUCCESS);

    return 0;
}

static const shell_command_t shell_commands[] = {
    { "overhead_gpio", "Benchmark the gpio toggling overhead",
      overhead_gpio_cmd },
    { "overhead_timer_now", "timer now overhead",
      overhead_timer_now },
    { "overhead_timer", "timer set/remove overhead",
      timer_overhead_timer_cmd },
    { "sleep_accuracy_timer_sleep", "Sleep for specified time",
      sleep_accuracy_timer_sleep_cmd },
    { "sleep_accuracy_timer_set", "Sleep for specified time",
      sleep_accuracy_timer_set_cmd },
    { "sleep_jitter", "sleep jitter", sleep_jitter_cmd },
    { "drift", "Drift Simple benchmark", drift_cmd },
    { "get_metadata", "Get the metadata of the test firmware",
      cmd_get_metadata },
    { "get_timer_version", "Get timer version", cmd_get_timer_version },
    { NULL, NULL, NULL }
};

int main(void)
{
    (void)puts("Welcome to RIOT!");

    gpio_init(TEST_GPIO, GPIO_OUT);

    random_init(0);

    char line_buf[SHELL_DEFAULT_BUFSIZE];
    shell_run(shell_commands, line_buf, SHELL_DEFAULT_BUFSIZE);

    return 0;
}
