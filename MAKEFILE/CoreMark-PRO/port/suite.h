#ifndef COREMARK_PRO_SUITE_H
#define COREMARK_PRO_SUITE_H
struct suite_settings {
    unsigned long cpu_hz;
    unsigned iterations, runs, min_seconds;
};
const volatile struct suite_settings *coremark_suite_get_config(void);
void coremark_suite_record(double median);
void coremark_suite_finish(int status) __attribute__((noreturn));
#endif
