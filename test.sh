#!/usr/bin/env bash
# Использование: ./test_erlangb.sh [путь_к_бинарнику]
# По умолчанию собирает erlangb.c из текущей папки.

BIN="${1:-}"
if [ -z "$BIN" ]; then
    gcc -Wall -Wextra -O2 erlangb.c -o /tmp/erlangb_test -lm || exit 1
    BIN=/tmp/erlangb_test
fi

PASS=0
FAIL=0

ok()   { PASS=$((PASS+1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL $1 ($2)"; }

# Достаёт число из строки вывода по префиксу
val() { echo "$1" | grep -F "$2" | head -1 | sed 's/.*: *//; s/^[^0-9-]*//' | awk '{print $1}'; }

# close имя фактическое ожидаемое допуск
close() {
    if awk -v a="$2" -v b="$3" -v t="$4" 'BEGIN{d=a-b; if(d<0)d=-d; exit !(a!="" && d<=t)}'; then
        ok "$1"
    else
        fail "$1" "получено '$2', ожидалось $3 ± $4"
    fi
}

# equal имя фактическое ожидаемое
equal() { [ "$2" = "$3" ] && ok "$1" || fail "$1" "получено '$2', ожидалось '$3'"; }

# invalid имя аргументы... : код возврата 1 и сообщение Invalid input
invalid() {
    local name="$1"; shift
    local out; out=$("$BIN" "$@" 2>&1); local rc=$?
    if [ $rc -eq 1 ] && echo "$out" | grep -q "Invalid input"; then
        ok "$name"
    else
        fail "$name" "rc=$rc"
    fi
}

echo "== Прямые расчёты =="

out=$("$BIN" -a 10 -v 5)
close "a=10 v=5: E (пример из справки)" "$(val "$out" 'Percentage of lost')" 0.563952 0.000001
close "a=10 v=5: M (пример из справки)" "$(val "$out" 'Average number')" 4.360478 0.000001

out=$("$BIN" -a 40 -v 53)
close "a=40 v=53: E" "$(val "$out" 'Percentage of lost')" 0.008227 0.000001

out=$("$BIN" -a 40 -v 1)
close "a=40 v=1: E = 40/41" "$(val "$out" 'Percentage of lost')" 0.975610 0.000001

echo "== Случай 2: a, E -> v, M (регрессия на баг 0.4) =="

out=$("$BIN" -a 40 -E 0.99)
equal "a=40 E=0.99: v=1" "$(val "$out" 'Required number')" 1
close "a=40 E=0.99: реальный E" "$(val "$out" 'Real percentage')" 0.975610 0.000001
close "a=40 E=0.99: M=0.9756, а не 0.4" "$(val "$out" 'Average number')" 0.975610 0.000001

out=$("$BIN" -a 40 -E 0.01)
equal "a=40 E=0.01: v=53" "$(val "$out" 'Required number')" 53
close "a=40 E=0.01: M" "$(val "$out" 'Average number')" 39.670915 0.0001

out=$("$BIN" -a 1 -E 0.5)
equal "a=1 E=0.5: v=1" "$(val "$out" 'Required number')" 1

echo "== Случай 5: v, E -> a, M =="

out=$("$BIN" -v 50 -E 0.01)
close "v=50 E=0.01: a" "$(val "$out" 'Load')" 37.901398 0.0001
close "v=50 E=0.01: M = a(1-E)" "$(val "$out" 'Average number')" 37.522384 0.0001

out=$("$BIN" -v 5 -E 0.563952)
close "v=5 E=0.563952: a≈10 (обратная к примеру)" "$(val "$out" 'Load')" 10 0.001

echo "== Случай 3: a, m -> v, E =="

out=$("$BIN" -a 40 -m 39.6)
close "a=40 m=39.6: E=0.01" "$(val "$out" 'Percentage of lost')" 0.01 0.000001
equal "a=40 m=39.6: v=53" "$(val "$out" 'Required number')" 53

echo "== Случай 4: v, m -> a, E =="

out=$("$BIN" -v 50 -m 39.6)
close "v=50 m=39.6: a" "$(val "$out" 'Load')" 40.451283 0.001
close "v=50 m=39.6: E" "$(val "$out" 'Percentage of lost')" 0.021045 0.0001

echo "== Случай 6: E, m -> a, v =="

out=$("$BIN" -E 0.01 -m 39.6)
close "E=0.01 m=39.6: a=40" "$(val "$out" 'Load')" 40 0.0001
equal "E=0.01 m=39.6: v=53" "$(val "$out" 'Required number')" 53

echo "== Порядок аргументов не важен =="

o1=$("$BIN" -a 40 -E 0.01); o2=$("$BIN" -E 0.01 -a 40)
equal "-a -E == -E -a" "$o1" "$o2"
o1=$("$BIN" -a 10 -v 5);    o2=$("$BIN" -v 5 -a 10)
equal "-a -v == -v -a" "$o1" "$o2"

echo "== Справка =="

"$BIN" >/dev/null;    equal "без аргументов: код 0" "$?" 0
"$BIN" -h >/dev/null; equal "-h: код 0" "$?" 0
"$BIN" -h | grep -q "Erlang B"; equal "-h: текст справки" "$?" 0

echo "== Некорректный ввод =="

invalid "нет значения у -a"          -a
invalid "нет второй опции"           -a 40
invalid "нет значения у второй"      -a 40 -v
invalid "не число: -a abc"           -a abc -v 5
invalid "хвост у числа: -a 10x"      -a 10x -v 5
invalid "дубль опции"                -a 1 -a 2
invalid "неизвестная опция"          -a 40 -x 5
invalid "лишние аргументы"           -a 40 -v 5 -E 0.1
invalid "a = 0"                      -a 0 -v 5
invalid "a < 0"                      -a -5 -v 5
invalid "v = 0"                      -a 10 -v 0
invalid "v < 0"                      -a 10 -v -3
invalid "v дробное"                  -a 10 -v 2.5
invalid "E = 0"                      -a 40 -E 0
invalid "E = 1"                      -a 40 -E 1
invalid "E > 1"                      -a 40 -E 1.5
invalid "E < 0"                      -a 40 -E -0.1
invalid "v,E: E = 1 (раньше бесконечный цикл)" -v 5 -E 1
invalid "E,m: E = 1 (раньше деление на 0)"     -E 1 -m 3
invalid "E,m: E = 0"                 -E 0 -m 3
invalid "a,m: m = 0"                 -a 10 -m 0
invalid "a,m: m = a"                 -a 10 -m 10
invalid "a,m: m > a"                 -a 10 -m 11
invalid "v,m: m = v"                 -v 5 -m 5
invalid "v,m: m > v"                 -v 5 -m 6

echo "== Перекрёстная проверка с независимой реализацией (python) =="

if command -v python3 >/dev/null; then
    for pair in "1 1" "5 10" "10 5" "40 50" "40 53" "100 110" "500 520"; do
        set -- $pair
        a=$1; v=$2
        ref=$(python3 - "$a" "$v" <<'EOF'
import sys
from math import factorial
a=float(sys.argv[1]); v=int(sys.argv[2])
# прямая формула через сумму, для умеренных v
from fractions import Fraction
A=Fraction(sys.argv[1])
num=A**v/factorial(v)
den=sum(A**k/factorial(k) for k in range(v+1))
print(float(num/den))
EOF
)
        out=$("$BIN" -a "$a" -v "$v")
        close "a=$a v=$v: E совпадает с точной формулой" "$(val "$out" 'Percentage of lost')" "$ref" 0.000001
    done

    # Минимальность v: потери при v <= E, при v-1 > E
    for pair in "10 0.05" "40 0.01" "40 0.001" "100 0.02" "200 0.005"; do
        set -- $pair
        a=$1; E=$2
        out=$("$BIN" -a "$a" -E "$E")
        v=$(val "$out" 'Required number')
        e_v=$("$BIN" -a "$a" -v "$v" | grep -F 'Percentage of lost' | awk '{print $NF}')
        e_prev=$("$BIN" -a "$a" -v $((v-1)) 2>/dev/null | grep -F 'Percentage of lost' | awk '{print $NF}')
        if awk -v e="$e_v" -v t="$E" 'BEGIN{exit !(e<=t+1e-6)}'; then
            ok "a=$a E=$E: при v=$v потери <= E"
        else
            fail "a=$a E=$E: при v=$v потери <= E" "E(v)=$e_v"
        fi
        if [ "$v" -le 1 ] || awk -v e="$e_prev" -v t="$E" 'BEGIN{exit !(e>t)}'; then
            ok "a=$a E=$E: v минимально (при v-1 потери > E)"
        else
            fail "a=$a E=$E: v минимально" "E(v-1)=$e_prev"
        fi
    done
else
    echo "  python3 не найден, пропуск"
fi

echo "== Круговая проверка (round trip) =="

out=$("$BIN" -v 50 -E 0.01); a=$(val "$out" 'Load')
out2=$("$BIN" -a "$a" -v 50)
close "v=50 E=0.01 -> a -> E обратно" "$(val "$out2" 'Percentage of lost')" 0.01 0.00001

out=$("$BIN" -v 50 -m 39.6); a=$(val "$out" 'Load')
out2=$("$BIN" -a "$a" -v 50)
close "v=50 m=39.6 -> a -> m обратно" "$(val "$out2" 'Average number')" 39.6 0.0001

echo "== Большие значения (устойчивость, без зависаний) =="

out=$(timeout 10 "$BIN" -a 900 -v 1000); rc=$?
equal "a=900 v=1000: завершилась" "$rc" 0
echo "$out" | grep -qi "nan\|inf" && fail "a=900 v=1000: нет nan/inf" "$out" || ok "a=900 v=1000: нет nan/inf"

out=$(timeout 10 "$BIN" -a 900 -E 0.01); rc=$?
equal "a=900 E=0.01: завершилась" "$rc" 0

out=$(timeout 10 "$BIN" -v 1000 -E 0.01); rc=$?
equal "v=1000 E=0.01: завершилась" "$rc" 0

out=$(timeout 10 "$BIN" -a 0.001 -E 0.5); rc=$?
equal "a=0.001 E=0.5: завершилась" "$rc" 0

echo
echo "Итого: пройдено $PASS, провалено $FAIL"
[ "$FAIL" -eq 0 ]