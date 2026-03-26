#!/bin/bash
Y="\033[33m" C="\033[36m" G="\033[32m" R="\033[31m" B="\033[1m" D="\033[2m" N="\033[0m"
HOST="bookinfo.spoke.aws-apac.mobb.cloud"
S1_HOST="istio-ingress-istio-system.apps.rosa.dev-spoke-1.261c.p3.openshiftapps.com"
S2_HOST="istio-ingress-istio-system.apps.rosa.dev-spoke-2.z3u5.p3.openshiftapps.com"
S1_NLB="a21ad0c91dd424ca4ae8ce8d00e798b0-2031152092.ap-southeast-4.elb.amazonaws.com"
S2_NLB="ae7e617de479444d0ab6612864f96ce2-2101777276.ap-southeast-4.elb.amazonaws.com"

hit() {
  local body=$(mktemp)
  local r=$(curl -k -s -o "$body" -w "%{remote_ip} | %{http_code} | %{time_total}s" "$2" 2>&1)
  local c=$(echo "$r" | cut -d'|' -f2 | tr -d ' ')
  [ "$c" -ge 200 ] && [ "$c" -lt 300 ] 2>/dev/null && k="$G" || k="$R"
  printf "${Y}${B}%-14s${N}\n" "$1"
  printf "${D}%s${N}\n" "$(cat "$body" | python3 -c 'import sys,json;print(json.dumps(json.load(sys.stdin)))' 2>/dev/null || cat "$body")"
  printf "  ${k}%s${N}\n" "$r"
  rm -f "$body"
}

echo -e "\n${D}$(date)${N}"
echo -e "${D}Flushing DNS cache...${N}\n"
sudo dscacheutil -flushcache 2>/dev/null; sudo killall -HUP mDNSResponder 2>/dev/null; sleep 1
dig +short "$HOST" @8.8.8.8 > /tmp/dns_main &
dig +short "$S1_NLB" @8.8.8.8 > /tmp/dns_s1 &
dig +short "$S2_NLB" @8.8.8.8 > /tmp/dns_s2 &
wait
dns_all=$(cat /tmp/dns_main)
dns_ips=$(echo "$dns_all" | grep -E '^[0-9]' | sort)
dns_elb=$(echo "$dns_all" | grep elb | head -1)
s1_ips=$(grep -E '^[0-9]' /tmp/dns_s1 | sort)
s2_ips=$(grep -E '^[0-9]' /tmp/dns_s2 | sort)
match="unknown"
if [ -n "$dns_elb" ]; then
  echo "$dns_elb" | grep -q "a21ad0c91dd42" && match="Spoke-1"
  echo "$dns_elb" | grep -q "ae7e617de4794" && match="Spoke-2"
else
  first_ip=$(echo "$dns_ips" | head -1)
  [ -n "$first_ip" ] && echo "$s1_ips" | grep -qF "$first_ip" && match="Spoke-1"
  [ -n "$first_ip" ] && [ "$match" = "unknown" ] && echo "$s2_ips" | grep -qF "$first_ip" && match="Spoke-2"
fi

echo -e "${Y}${HOST} resolves to:${N} ${C}$(echo $dns_ips | tr '\n' ' ')${N} ${B}${G}-> ${match}${N}"
echo -e "${Y}  Spoke-1 NLB IPs =${N} ${C}$(echo $s1_ips | tr '\n' ' ')${N}"
echo -e "${Y}  Spoke-2 NLB IPs =${N} ${C}$(echo $s2_ips | tr '\n' ' ')${N}\n"
hit "DNS-Weighted" "https://${HOST}/api/v1/products/0/reviews"
hit "Spoke-1 Direct" "http://${S1_HOST}/api/v1/products/0/reviews"
hit "Spoke-2 Direct" "http://${S2_HOST}/api/v1/products/0/reviews"
echo ""
