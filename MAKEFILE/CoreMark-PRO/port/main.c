#include "board.h"
#include "th_lib.h"
#include "mith_workload.h"
#include <stdio.h>
#include <limits.h>
#ifdef BENCH_SUITE_PAYLOAD
#include "suite.h"
#endif
extern int coremark_workload_main(int argc, char **argv);
extern int __real_mith_main(ee_workload *, unsigned, unsigned, Bool, unsigned);

/* Writable by GDB at the ELF entry before continue. */
volatile unsigned long bench_cpu_hz = BENCH_CPU_HZ;
volatile unsigned bench_iterations = BENCH_ITERATIONS;
volatile unsigned bench_runs = BENCH_RUNS;
volatile unsigned bench_min_seconds = BENCH_MIN_SECONDS;
uint64_t bench_last_cycles, bench_last_instructions;
unsigned bench_failed, bench_completed;

/* Observe the original harness results without changing its workload sources. */
int __wrap_mith_main(ee_workload *wl, unsigned iters, unsigned contexts,
                     Bool oversubscribe, unsigned workers) {
    int result = __real_mith_main(wl, iters, contexts, oversubscribe, workers);
    bench_failed = bench_completed = 0;
    for (unsigned i = 0; i < wl->max_idx; ++i) {
        bench_failed += wl->load[i]->failed;
        bench_completed += wl->load[i]->finished;
    }
    return result;
}
static void invoke(unsigned iters, int validation) {
    char iteration_arg[32];
    snprintf(iteration_arg, sizeof(iteration_arg), "-i%u", iters);
    char *args[] = { BENCH_WORKLOAD, "-c1", "-w1", "-b1", iteration_arg,
                     validation ? "-v1" : "-v0", NULL };
    bench_last_cycles = bench_last_instructions = 0;
    bench_failed = bench_completed = 0;
    int rc = coremark_workload_main(6, args);
    if (rc || bench_failed || !bench_completed || !bench_last_cycles || !bench_last_instructions) {
        printf("RESULT_ERROR workload=%s rc=%d fails=%u completed=%u\n",
               BENCH_WORKLOAD, rc, bench_failed, bench_completed);
        board_exit(1);
    }
}
int main(void) {
#ifdef BENCH_SUITE_PAYLOAD
    const volatile struct suite_settings *settings = coremark_suite_get_config();
    bench_cpu_hz = settings->cpu_hz;
    bench_iterations = settings->iterations;
    bench_runs = settings->runs;
    bench_min_seconds = settings->min_seconds;
#endif
    board_init();
    setvbuf(stdout, NULL, _IONBF, 0);
    if (!bench_cpu_hz || !bench_iterations || !bench_runs || bench_runs > 100 ||
        bench_min_seconds > 3600) board_exit(3);
    unsigned long mhcr, mxstatus, mccr2, mhint;
    __asm__ volatile ("csrr %0,0x7c1" : "=r"(mhcr));
    __asm__ volatile ("csrr %0,0x7c0" : "=r"(mxstatus));
    __asm__ volatile ("csrr %0,0x7c3" : "=r"(mccr2));
    __asm__ volatile ("csrr %0,0x7c5" : "=r"(mhint));
    printf("\nCOREMARK_PRO_BEGIN workload=%s cpu_hz=%lu hart=0 contexts=1\n",
           BENCH_WORKLOAD, bench_cpu_hz);
    printf("BUILD compiler=%s flags=%s upstream=%s\n", __VERSION__, BENCH_FLAGS, BENCH_UPSTREAM);
    printf("CONFIG mhcr=0x%lx mxstatus=0x%lx mccr2=0x%lx mhint=0x%lx code=data=heap=stack=DDR\n",
           mhcr, mxstatus, mccr2, mhint);
    printf("MEASURE runs=%u min_seconds=%u timer=mcycle units=cycles\n", bench_runs, bench_min_seconds);
    printf("VALIDATION_BEGIN\n");
    invoke(1, 1);
    printf("VALIDATION_PASS workload=%s\n", BENCH_WORKLOAD);

    unsigned iters = bench_iterations;
    uint64_t minimum_cycles = (uint64_t)bench_cpu_hz * bench_min_seconds;
    printf("CALIBRATION_BEGIN min_seconds=%u\n", bench_min_seconds);
    for (;;) {
        invoke(iters, 0); /* This also warms caches using the original workload. */
        /* Leave duration headroom for variation between measured runs. */
        if (bench_last_cycles >= minimum_cycles + minimum_cycles / 4) break;
        if (iters > UINT_MAX / 2) board_exit(4);
        iters *= 2;
    }
    printf("CALIBRATION_DONE iterations=%u\n", iters);
    double rates[100];
    for (unsigned run = 1; run <= bench_runs; ++run) {
        invoke(iters, 0);
        if (bench_completed != iters) board_exit(5);
        if (bench_last_cycles < minimum_cycles) {
            printf("RESULT_ERROR workload=%s measurement shorter than min_seconds\n", BENCH_WORKLOAD);
            board_exit(6);
        }
        double seconds = (double)bench_last_cycles / bench_cpu_hz;
        rates[run - 1] = (double)iters / seconds;
        printf("RESULT,%s,%u,%u,%llu,%llu,%.9f,%.9f,%.6f,PASS\n",
               BENCH_WORKLOAD, run, iters,
               (unsigned long long)bench_last_cycles,
               (unsigned long long)bench_last_instructions, seconds,
               rates[run - 1],
               (double)bench_last_instructions / bench_last_cycles);
    }
    printf("POST_VALIDATION_BEGIN\n");
    invoke(1, 1);
    printf("POST_VALIDATION_PASS workload=%s\n", BENCH_WORKLOAD);
    for (unsigned i = 1; i < bench_runs; ++i) {
        double value = rates[i];
        unsigned j = i;
        while (j && rates[j - 1] > value) { rates[j] = rates[j - 1]; --j; }
        rates[j] = value;
    }
    double median = rates[bench_runs / 2];
    if (!(bench_runs & 1)) median = (median + rates[bench_runs / 2 - 1]) / 2;
    printf("SUMMARY,%s,%u,%.9f,PASS\n", BENCH_WORKLOAD, bench_runs, median);
#ifdef BENCH_SUITE_PAYLOAD
    coremark_suite_record(median);
#endif
    board_exit(0);
}
