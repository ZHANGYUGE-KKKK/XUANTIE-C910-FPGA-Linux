#include "board.h"
#include "suite.h"
#include "suite_entries.h"
#include <setjmp.h>
#include <math.h>
#include <stdio.h>

/* These may be changed through GDB before continuing at _start. */
volatile struct suite_settings bench_suite_settings = {
    BENCH_CPU_HZ, BENCH_ITERATIONS, BENCH_RUNS, BENCH_MIN_SECONDS
};
static jmp_buf suite_return;
static unsigned current_workload, passed;
static int workload_status;
static double medians[9];

const volatile struct suite_settings *coremark_suite_get_config(void) {
    return &bench_suite_settings;
}
void coremark_suite_record(double median) {
    if (current_workload >= 9 || !isfinite(median) || median <= 0) board_exit(7);
    medians[current_workload] = median;
}
void coremark_suite_finish(int status) {
    workload_status = status;
    longjmp(suite_return, 1);
}
int main(void) {
    board_init();
    setvbuf(stdout, NULL, _IONBF, 0);
    printf("\nCOREMARK_PRO_SUITE_BEGIN workloads=9\n");
    printf("SUITE_CONFIG cpu_hz=%lu runs=%u min_seconds=%u entry=0x200000000\n",
           bench_suite_settings.cpu_hz, bench_suite_settings.runs, bench_suite_settings.min_seconds);
    /* All state modified between setjmp/longjmp is static, never an automatic local. */
    for (current_workload = 0; current_workload < 9; ++current_workload) {
        workload_status = -1;
        printf("SUITE_WORKLOAD index=%u/9 name=%s\n",
               current_workload + 1, suite_entries[current_workload].name);
        __asm__ volatile ("csrw fcsr,zero" ::: "memory");
        if (!setjmp(suite_return)) {
            suite_entries[current_workload].run();
            /* A module must finish through its checked board_exit path. */
            workload_status = 8;
        }
        if (!workload_status && medians[current_workload] > 0) ++passed;
        else printf("SUITE_WORKLOAD_FAILED name=%s status=%d\n",
                    suite_entries[current_workload].name, workload_status);
    }
    if (passed == 9) {
        double log_sum = 0;
        for (unsigned i = 0; i < 9; ++i) {
            printf("SUITE_SUMMARY,%s,%.9f,PASS\n", suite_entries[i].name, medians[i]);
            log_sum += log(medians[i] / suite_entries[i].reference_rate);
        }
        if (bench_suite_settings.min_seconds) {
            printf("COREMARK_PRO_RESEARCH_SCORE=%.6f contexts=1 workloads=9 runs=%u cpu_hz=%lu\n",
                   1000 * exp(log_sum / 9), bench_suite_settings.runs, bench_suite_settings.cpu_hz);
        } else {
            printf("COREMARK_PRO_SCORE_SKIPPED reason=min_seconds_zero\n");
        }
        printf("COREMARK_PRO_SUITE_DONE workloads=9 passed=9 failed=0\n");
    } else {
        printf("COREMARK_PRO_SUITE_FAILED workloads=9 passed=%u failed=%u\n", passed, 9 - passed);
    }
    for (;;) __asm__ volatile ("wfi");
}
