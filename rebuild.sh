#!/bin/bash


#### 
echo "● Killing process 3proxy"
kill -9 $(pidof 3proxy)

rm ~/3proxy/3proxy.cfg
rm -rf ip.list
rm -rf tunnels.txt

PROXY_NETWORK="$(grep -oP '[0-9].*?(?=::)' v_network.txt)" 
echo "● Network = $PROXY_NETWORK"
PROXY_NET_MASK="$(grep -oP '(?<=::/).*' v_network.txt)"
#PROXY_NET_MASK="$(cat v_netmask.txt)"
echo "● Netmask = $PROXY_NET_MASK"
PROXY_COUNT="$(cat v_count.txt)"
echo "● Proxy Count = $PROXY_COUNT"
#PROXY_AUTH_IP="$(cat v_authip.txt)"
#echo "Proxy Authenticated IPs = $PROXY_AUTH_IP"
HOST_IPV4_ADDR=$(hostname -I | awk '{print $1}')
echo "● Host IPv4 = $HOST_IPV4_ADDR"
PROXY_AUTHORISATION="$(cat v_authmode.txt)"
echo "● Proxy auth mode = $PROXY_AUTHORISATION"

echo "● Proxy Authenticated IPs:"
cat ~/v_authip.txt | while read line; do echo $line; done

#### Authorization method
echo "↓ Proxies authorisation mode 0 or 1 or 2 : (0 = log;pass / 1 = ip / 2 = no auth)"
#read PROXY_AUTHORISATION

if [[ $PROXY_AUTHORISATION == *"0"* ]]; then
    PROXY_AUTH_TYPE="auth strong"
elif [[ $PROXY_AUTHORISATION == *"1"* ]]; then
    PROXY_AUTH_TYPE="auth iponly"
elif [[ $PROXY_AUTHORISATION == *"2"* ]]; then
    PROXY_AUTH_TYPE="auth none"
else
    echo "● Unsupported auth format: $PROXY_AUTHORISATION"
    exit 1
fi
echo "● Selected auth method: $PROXY_AUTHORISATION"

#### Generate log;pass
gen_logpass() {
echo "↓ Set proxies login & password:"
read PROXY_LOGIN

if [[ -n "$PROXY_LOGIN" ]]; then
    echo "● Selected: $PROXY_LOGIN"

    echo "↓ Proxies password:"
    read PROXY_PASS
    echo "● Selected: $PROXY_PASS"
else
    echo "● Login can't be empty"
    exit 1

fi
}
#gen_logpass

#### Generate ip
gen_auth_ip() {
echo "↓ Enter your authorized ip (eg: 1.2.3.4.5):"
read PROXY_AUTH_IP

if [[ -n "$PROXY_AUTH_IP" ]]; then
    echo "● Selected: $PROXY_AUTH_IP"
else
    echo "field can't be empty"
    exit 1
fi
}
#gen_auth_ip

gen_conf() {
echo "↓ Writing main 3proxy config"
cat >~/3proxy/3proxy.cfg <<END
#!/bin/bash
daemon
maxconn 10000
nserver 1.1.1.1
nserver [2606:4700:4700::1111]
nserver [2606:4700:4700::1001]
nserver [2001:4860:4860::8888]
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
setgid 65535
setuid 65535
stacksize 6000
flush
END
}

gen_conf

#### Select authorization method
echo "●  Configuring proxy authorisation"
if [[ $PROXY_AUTHORISATION == *"0"* ]]; then
    #gen_logpass
    cat >>~/3proxy/3proxy.cfg <<END
auth strong
users ${PROXY_LOGIN}:CL:${PROXY_PASS}
allow ${PROXY_LOGIN}
END
    echo "↓ Chosen auth type: ($PROXY_AUTH_TYPE) proxy credentials:  Login = $PROXY_LOGIN Pass = $PROXY_PASS"
elif [[ $PROXY_AUTHORISATION == *"1"* ]]; then
    #gen_auth_ip
    cat >>~/3proxy/3proxy.cfg <<END
auth iponly
END
    echo "↓ Chosen auth type: ($PROXY_AUTH_TYPE)"
elif [[ $PROXY_AUTHORISATION == *"2"* ]]; then
    cat >>~/3proxy/3proxy.cfg <<END
$PROXY_AUTH_TYPE
END
    echo "↓ Chosen auth type: ($PROXY_AUTH_TYPE) anyone can access to proxy!"
else
    echo "● Unsupported auth format: $PROXY_AUTHORISATION"
    exit 1
fi
####

####
echo "↓ Port numbering start (default 30000):"
#read PROXY_START_PORT
if [[ ! "$PROXY_START_PORT" ]]; then
    PROXY_START_PORT=30000
fi


####
echo "↓ Proxies protocol (http, socks5; default http):"
#read PROXY_PROTOCOL
if [[ PROXY_PROTOCOL != "socks5" ]]; then
    PROXY_PROTOCOL="http"
fi
echo "● Selected: $PROXY_PROTOCOL"


####
echo "● Generating $PROXY_COUNT IPv6 addresses"
touch ~/ip.list
touch ~/tunnels.txt

P_VALUES=(1 2 3 4 5 6 7 8 9 0 a b c d e f)
PROXY_GENERATING_INDEX=1
GENERATED_PROXY=""

generate_proxy() {
    a=${P_VALUES[$RANDOM % 16]}${P_VALUES[$RANDOM % 16]}${P_VALUES[$RANDOM % 16]}${P_VALUES[$RANDOM % 16]}
    b=${P_VALUES[$RANDOM % 16]}${P_VALUES[$RANDOM % 16]}${P_VALUES[$RANDOM % 16]}${P_VALUES[$RANDOM % 16]}
    c=${P_VALUES[$RANDOM % 16]}${P_VALUES[$RANDOM % 16]}${P_VALUES[$RANDOM % 16]}${P_VALUES[$RANDOM % 16]}
    d=${P_VALUES[$RANDOM % 16]}${P_VALUES[$RANDOM % 16]}${P_VALUES[$RANDOM % 16]}${P_VALUES[$RANDOM % 16]}
    e=${P_VALUES[$RANDOM % 16]}${P_VALUES[$RANDOM % 16]}${P_VALUES[$RANDOM % 16]}${P_VALUES[$RANDOM % 16]}

    echo "$PROXY_NETWORK:$a:$b:$c:$d$([ $PROXY_NET_MASK == 48 ] && echo ":$e" || echo "")" >>~/ip.list

}

while [ "$PROXY_GENERATING_INDEX" -le $PROXY_COUNT ]; do
    generate_proxy
    let "PROXY_GENERATING_INDEX+=1"
done

CURRENT_PROXY_PORT=${PROXY_START_PORT}
for e in $(cat ~/ip.list); do
    echo "$([ $PROXY_PROTOCOL == "socks5" ] && echo "socks" || echo "proxy") -6 -s0 -n -a -p$CURRENT_PROXY_PORT -i$HOST_IPV4_ADDR -e$e" >>~/3proxy/3proxy.cfg
    echo "$PROXY_PROTOCOL://$HOST_IPV4_ADDR:$CURRENT_PROXY_PORT$([ "$PROXY_LOGIN" ] && echo ":$PROXY_LOGIN:$PROXY_PASS" || echo "")" >>~/tunnels.txt
    let "CURRENT_PROXY_PORT+=1"
done

generate_auth_ip() {
for i in $(cat ~/v_authip.txt); do
    echo "$(sed -i "/auth iponly/a allow * $i" ~/3proxy/3proxy.cfg)">>~/3proxy/3proxy.cfg
done
}

generate_auth_ip

####
~/3proxy/bin/3proxy ~/3proxy/3proxy.cfg
echo "● Finishing"
