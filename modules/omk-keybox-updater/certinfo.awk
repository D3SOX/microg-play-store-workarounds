# Reads one DER certificate as hex bytes (od -An -v -tx1) and prints:
#   <serial hex> <serial decimal> <notBefore> <notAfter> <state>
# Serials have no leading zeros, like the keys in Google's revocation list.
# Times are UTC YYYYMMDDHHMMSS. state is valid, expired, or future, compared
# with -v now=YYYYMMDDHHMMSS. Prints "error" for anything it cannot parse.

function hv(x) {
    return (index(HEX, substr(x, 1, 1)) - 1) * 16 + index(HEX, substr(x, 2, 1)) - 1
}

# Reads the TLV header at p into T (tag), L (content length), H (header size).
function header(p,    first, k, j) {
    if (p + 1 > n) return 0
    T = b[p]
    first = hv(b[p + 1])
    if (first < 128) {
        L = first
        H = 2
    } else {
        k = first - 128
        if (k < 1 || k > 4 || p + 1 + k > n) return 0
        L = 0
        for (j = 1; j <= k; j++) L = L * 256 + hv(b[p + 1 + j])
        H = 2 + k
    }
    return p + H + L - 1 <= n
}

function expect(p, tag) {
    if (!header(p) || T != tag) failed = 1
    return !failed
}

function time_at(p,    s, j, v) {
    if (!header(p) || (T != "17" && T != "18")) { failed = 1; return "" }
    s = ""
    for (j = 0; j < L; j++) {
        v = hv(b[p + H + j])
        if (v >= 48 && v <= 57) s = s (v - 48)
    }
    if (T == "17" && length(s) == 12) return (substr(s, 1, 2) + 0 < 50 ? "20" : "19") s
    if (T == "18" && length(s) == 14) return s
    failed = 1
    return ""
}

# Big-number hex to decimal, because serials exceed awk's number precision.
function decimal(hex,    nd, d, i, j, x, carry, s) {
    nd = 1
    d[1] = 0
    for (i = 1; i <= length(hex); i++) {
        carry = index(HEX, substr(hex, i, 1)) - 1
        for (j = 1; j <= nd; j++) {
            x = d[j] * 16 + carry
            d[j] = x % 10
            carry = int(x / 10)
        }
        while (carry > 0) {
            d[++nd] = carry % 10
            carry = int(carry / 10)
        }
    }
    s = ""
    for (j = nd; j >= 1; j--) s = s d[j]
    return s
}

BEGIN { HEX = "0123456789abcdef" }

{ for (i = 1; i <= NF; i++) b[++n] = tolower($i) }

END {
    p = 1
    if (expect(p, "30")) p += H                     # Certificate
    if (!failed && expect(p, "30")) p += H          # TBSCertificate
    if (!failed && b[p] == "a0" && header(p)) p += H + L  # version
    serial = ""
    if (!failed && expect(p, "02")) {
        for (j = 0; j < L; j++) serial = serial b[p + H + j]
        p += H + L
    }
    if (!failed && expect(p, "30")) p += H + L      # signature algorithm
    if (!failed && expect(p, "30")) p += H + L      # issuer
    if (!failed && expect(p, "30")) p += H          # validity
    if (!failed) {
        before = time_at(p)
        p += H + L
    }
    if (!failed) after = time_at(p)
    sub(/^0+/, "", serial)
    if (failed || serial == "") {
        print "error"
        exit
    }
    state = "valid"
    if (now + 0 < before + 0) state = "future"
    else if (now + 0 >= after + 0) state = "expired"
    print serial, decimal(serial), before, after, state
}
