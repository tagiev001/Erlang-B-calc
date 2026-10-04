#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <math.h>

#define MAX_CHANNELS 1000000
#define BISECT_ITERS 200

double lost_tickets(double a, int v);
double average_number_of_busy_channels(double E, double a);
int required_number_of_channels(double E, double a);
double required_load(double E, int v);
double find_lost_via_m(double a, double m);
double find_a_from_v_m(int v, double m);
double find_a_for_m_e(double m, double E);
int help_message(void);

/* Поиск опции name в argv. 1 - найдена и значение корректное,
   0 - не найдена, -1 - значение отсутствует или не число. */
static int get_opt(int argc, char **argv, const char *name, double *out) {
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], name) == 0) {
            if (i + 1 >= argc) return -1;
            char *end;
            double val = strtod(argv[i + 1], &end);
            if (end == argv[i + 1] || *end != '\0') return -1;
            *out = val;
            return 1;
        }
    }
    return 0;
}

static int invalid_input(void) {
    printf("Invalid input\n");
    help_message();
    return 1;
}

int main(int argc, char **argv) {
    if (argc == 1 || (argc == 2 && strcmp(argv[1], "-h") == 0)) {
        help_message();
        return 0;
    }

    double a = 0, E = 0, m = 0, vd = 0;
    int ra = get_opt(argc, argv, "-a", &a);
    int rv = get_opt(argc, argv, "-v", &vd);
    int rE = get_opt(argc, argv, "-E", &E);
    int rm = get_opt(argc, argv, "-m", &m);

    if (ra < 0 || rv < 0 || rE < 0 || rm < 0) return invalid_input();

    /* Ровно две различные опции, и больше в командной строке ничего нет */
    if (argc != 5 || ra + rv + rE + rm != 2) return invalid_input();

    int v = 0;
    if (rv) {
        if (vd < 1 || vd > MAX_CHANNELS || vd != floor(vd)) return invalid_input();
        v = (int)vd;
    }
    if (ra && a <= 0) return invalid_input();
    if (rm && m <= 0) return invalid_input();
    if (rE && (E <= 0 || E >= 1)) return invalid_input();

    // 1: a v -> E m
    if (ra && rv) {
        double Ereal = lost_tickets(a, v);
        double M = average_number_of_busy_channels(Ereal, a);
        printf("Percentage of lost %f\n", Ereal);
        printf("Average number of busy channels: %f\n", M);
        return 0;
    }
    // 2: a E -> v m
    if (ra && rE) {
        int vr = required_number_of_channels(E, a);
        if (vr < 0) return invalid_input();
        double Ereal = lost_tickets(a, vr);   /* реальные потери при целом v */
        double M = average_number_of_busy_channels(Ereal, a);
        printf("Required number of channels: %d\n", vr);
        printf("Real percentage of lost: %f\n", Ereal);
        printf("Average number of busy channels: %f\n", M);
        return 0;
    }
    // 5: v E -> a m
    if (rv && rE) {
        double ar = required_load(E, v);
        double M = average_number_of_busy_channels(E, ar);
        printf("Load: %f\n", ar);
        printf("Average number of busy channels: %f\n", M);
        return 0;
    }
    // 3: a m -> v E
    if (ra && rm) {
        if (m >= a) return invalid_input();
        double Er = find_lost_via_m(a, m);
        int vr = required_number_of_channels(Er, a);
        if (vr < 0) return invalid_input();
        printf("Percentage of lost: %f\n", Er);
        printf("Required number of channels: %d\n", vr);
        return 0;
    }
    // 4: v m -> a E
    if (rv && rm) {
        if (m >= v) return invalid_input();
        double ar = find_a_from_v_m(v, m);
        double Er = lost_tickets(ar, v);
        printf("Percentage of lost: %f\n", Er);
        printf("Load: %f\n", ar);
        return 0;
    }
    // 6: E m -> a v
    if (rE && rm) {
        double ar = find_a_for_m_e(m, E);
        int vr = required_number_of_channels(E, ar);
        if (vr < 0) return invalid_input();
        printf("Load: %f\n", ar);
        printf("Required number of channels: %d\n", vr);
        return 0;
    }

    return invalid_input();
}

double find_a_for_m_e(double m, double E) {
    return m / (1.0 - E);
}

/* Формула Эрланга B через устойчивую рекуррентную форму:
   B(0) = 1, B(k) = a*B(k-1) / (k + a*B(k-1)) */
double lost_tickets(double a, int v) {
    double b = 1.0;
    for (int k = 1; k <= v; k++) {
        b = a * b / (k + a * b);
    }
    return b;
}

double average_number_of_busy_channels(double E, double a) {
    return a * (1.0 - E);
}

/* m = a * (1 - E)  =>  E = 1 - m / a, бисекция не нужна */
double find_lost_via_m(double a, double m) {
    return 1.0 - m / a;
}

/* Бинарный поиск наименьшего v с потерями <= E.
   Верхняя граница расширяется удвоением. -1, если не нашли. */
int required_number_of_channels(double E, double a) {
    int left = 1;
    int right = 1;

    while (lost_tickets(a, right) > E) {
        left = right + 1;
        if (right > MAX_CHANNELS / 2) return -1;
        right *= 2;
    }

    while (left < right) {
        int mid = left + (right - left) / 2;
        if (lost_tickets(a, mid) > E) {
            left = mid + 1;
        } else {
            right = mid;
        }
    }
    return left;
}

/* Потери растут с нагрузкой: ищем a, при котором потери = E (бисекция) */
double required_load(double E, int v) {
    double left = 0.0;
    double right = 1.0;

    while (lost_tickets(right, v) <= E) {
        right *= 2.0;
    }
    for (int i = 0; i < BISECT_ITERS; i++) {
        double mid = (left + right) / 2.0;
        if (lost_tickets(mid, v) <= E) {
            left = mid;
        } else {
            right = mid;
        }
    }
    return (left + right) / 2.0;
}

/* Обслуженная нагрузка a*(1-B(a,v)) растёт с a и стремится к v (при m < v) */
double find_a_from_v_m(int v, double m) {
    double left = 0.0;
    double right = 1.0;

    while (right * (1.0 - lost_tickets(right, v)) < m) {
        right *= 2.0;
    }
    for (int i = 0; i < BISECT_ITERS; i++) {
        double mid = (left + right) / 2.0;
        double m_calc = mid * (1.0 - lost_tickets(mid, v));
        if (m_calc < m) {
            left = mid;
        } else {
            right = mid;
        }
    }
    return (left + right) / 2.0;
}

int help_message(void) {
    printf("erlangb is Erlang B calculator, it accepts the following arguments and their values as input:\n");
    printf("-h show this message\n");
    printf("-a Load > 0, (a > m)\n");
    printf("-v Number of channels, integer (v > m)\n");
    printf("-m Average number of busy channels, m > 0\n");
    printf("-E Percentage of lost tickets 0 < E < 1\n");
    printf("Here is all supported cases of use:\n");
    printf("-a <number> -v <number> -> E, m\n");
    printf("-a <number> -E <number> -> v, m\n");
    printf("-a <number> -m <number> -> v, E\n");
    printf("-v <number> -m <number> -> a, E\n");
    printf("-E <number> -m <number> -> a, v\n");
    printf("-v <number> -E <number> -> a, m\n");
    printf("Example:\n");
    printf("Input:\n    -a 10 -v 5\n");
    printf("Output:\n");
    printf("    Percentage of lost 0.563952\n");
    printf("    Average number of busy channels: 4.360478\n");
    return 0;
}