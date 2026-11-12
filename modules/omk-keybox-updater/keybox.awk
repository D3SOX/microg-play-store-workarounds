# Reads a keybox.xml and prints one item per line for update.sh:
#   KEY <algorithm>     start of a <Key> entry
#   COUNT <n>           its <NumberOfCertificates>
#   PRIVATE             it has a PEM private key
#   CERT <base64>       one certificate, whitespace removed
#   END                 end of the entry
# Works on the whole file, so line breaks inside the XML do not matter.

{
    gsub(/\r/, "")
    text = text $0 "\n"
}

END {
    pattern = "<Key[ \t\n]+algorithm=\"[^\"]*\"[^>]*>|</Key>|<NumberOfCertificates>[^<]*</NumberOfCertificates>|-----BEGIN [A-Z ]*PRIVATE KEY-----|-----BEGIN CERTIFICATE-----[^-]*-----END CERTIFICATE-----"
    while (match(text, pattern)) {
        token = substr(text, RSTART, RLENGTH)
        text = substr(text, RSTART + RLENGTH)
        if (token ~ /^<Key/) {
            sub(/^[^"]*"/, "", token)
            sub(/".*$/, "", token)
            print "KEY", token
        } else if (token == "</Key>") {
            print "END"
        } else if (token ~ /^<NumberOfCertificates>/) {
            gsub(/<[^>]*>|[ \t\n]/, "", token)
            print "COUNT", token
        } else if (token ~ /PRIVATE KEY/) {
            print "PRIVATE"
        } else {
            gsub(/-----[A-Z ]*-----|[ \t\n]/, "", token)
            print "CERT", token
        }
    }
}
