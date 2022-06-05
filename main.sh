#!/bin/bash

if ping6 -c3 google.com &>/dev/null; then
    echo "Your server is ready to set up IPv6 proxies!"
else
    echo "Your server can't connect to IPv6 addresses"
    exit 1
fi

####
echo "======UPDATE SYS PACKAGES======"
echo "● Updating packages and installing dependencies"
apt-get update
apt-get -y install gcc g++ make bc pwgen git

sleep 2

####
echo "======TUNING SYSCTL======"
echo "● Setting up /etc/sysctl.conf"
cat >>/etc/sysctl.conf <<END
net.ipv6.conf.eth0.proxy_ndp=1
net.ipv6.conf.all.proxy_ndp=1
net.ipv6.conf.default.forwarding=1
net.ipv6.conf.all.forwarding=1
net.ipv6.ip_nonlocal_bind=1
net.ipv4.ip_local_port_range=1024 64000
net.ipv6.route.max_size=409600
net.ipv4.tcp_max_syn_backlog=4096
net.ipv6.neigh.default.gc_thresh3=102400
kernel.threads-max=1200000
kernel.max_map_count=6000000
vm.max_map_count=6000000
kernel.pid_max=2000000
END

sleep 1

####
echo "======TUNING logind======"
echo "● Setting up /etc/systemd/logind.conf"
echo "UserTasksMax=1000000" >>/etc/systemd/logind.conf

sleep 2

####
echo "======TUNING FILELIMITS======"
echo '* hard nofile 999999' >> /etc/security/limits.conf
echo '* soft nofile 999999' >> /etc/security/limits.conf
echo 'root hard nofile 1048576' >> /etc/security/limits.conf
echo 'root soft nofile 1048576' >> /etc/security/limits.conf

sleep 2

####
echo "======TUNING SYSTEM.CONF======"
echo "● Setting up /etc/systemd/system.conf"
cat >>/etc/systemd/system.conf <<END
UserTasksMax=1000000
DefaultMemoryAccounting=no
DefaultTasksAccounting=no
DefaultTasksMax=1000000
UserTasksMax=1000000
END

sleep 2

####
echo "======SETTING UP #PROXY====="
echo "● Setting up 3proxy"
cd ~
git clone https://github.com/z3APA3A/3proxy.git
cd 3proxy/
touch ~/3proxy/src/define.txt
echo "#define ANONYMOUS 1" > ~/3proxy/src/define.txt
make -f Makefile.Linux

sleep 1

####
echo "======CONFIGURE IPv6 PREFIX======"
echo "↓ Routed IPv6 Prefix (*:*:*::/*): (enter full prefix eg: 2001:470:7ac7::/48 or 2001:470:1f15:3c4::/64)"
read PROXY_NETWORK

if [[ $PROXY_NETWORK == *"::/48"* ]]; then
    PROXY_NET_MASK=48
elif [[ $PROXY_NETWORK == *"::/64"* ]]; then
    PROXY_NET_MASK=64
else
    echo "● Unsupported IPv6 prefix format: $PROXY_NETWORK"
    exit 1
fi
echo "● Selected: $PROXY_NETWORK"

sleep 1

####
echo "======INSTALL NDPPD======"
echo "● Setting up ndppd"
cd ~
git clone https://github.com/DanielAdolfsson/ndppd.git
cd ~/ndppd
make all
make install
cat >~/ndppd/ndppd.conf <<END
route-ttl 30000
proxy he-ipv6 {
   router no
   timeout 500
   ttl 30000
   rule ${PROXY_NETWORK}::/${PROXY_NET_MASK} {
      static
   }
}
END

sleep 1

####
echo "======CONFIGURE BROKER ENDPOINT======"
echo "↓ IPv4 endpoint of your Tunnel Server: (see in tunnelbroker tunnel conf"
read TUNNEL_IPV4_ADDR
if [[ ! "$TUNNEL_IPV4_ADDR" ]]; then
    echo "IPv4 endpoint can't be emty"
    exit 1
fi
echo "● Selected: $TUNNEL_IPV4_ADDR"

sleep 1

####
echo "======CHOOSE AUTHORIZATION METHOD======"
echo "↓ Proxies authorisation mode 0 or 1 or 2 : (0 = log;pass / 1 = ip / 2 = no auth)"
read PROXY_AUTHORISATION

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

sleep 1

####
echo "======CONFIGURE PROXY LOGIN:PASS======"
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

sleep 1

####
echo "======SETTINGS UP YOU AUTHORIZED IPs======"
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

sleep 1

####
echo "======SETTINGS UP 3PROXY CONFIG======"
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

sleep 1

#### Select authorization method
echo "======SETTINGS UP PROXY AUTHORIZATION======"
echo "↓ Configuring proxy authorization"
if [[ $PROXY_AUTHORISATION == *"0"* ]]; then
    gen_logpass
    cat >>~/3proxy/3proxy.cfg <<END
auth strong
users ${PROXY_LOGIN}:CL:${PROXY_PASS}
allow ${PROXY_LOGIN}
END
    echo "Chosen auth type: ($PROXY_AUTH_TYPE) proxy credentials:  Login = $PROXY_LOGIN Pass = $PROXY_PASS"
elif [[ $PROXY_AUTHORISATION == *"1"* ]]; then
    gen_auth_ip
    cat >>~/3proxy/3proxy.cfg <<END
auth iponly
allow * ${PROXY_AUTH_IP}
END
    echo "Chosen auth type: ($PROXY_AUTH_TYPE) && authorized ip = $PROXY_AUTH_IP"
elif [[ $PROXY_AUTHORISATION == *"2"* ]]; then
    cat >>~/3proxy/3proxy.cfg <<END
$PROXY_AUTH_TYPE
END
    echo "Chosen auth type: ($PROXY_AUTH_TYPE) anyone can access to proxy!"
else
    echo "● Unsupported auth format: $PROXY_AUTHORISATION"
    exit 1
fi
#echo "● Selected: $PROXY_AUTHORISATION"

sleep 1

####
echo "======SET PROXY PORT NUMBER======"
echo "↓ Port numbering start (default 30000):"
read PROXY_START_PORT
if [[ ! "$PROXY_START_PORT" ]]; then
    PROXY_START_PORT=30000
fi
echo "● Selected: $PROXY_START_PORT"

sleep 1

####
echo "======SET PROXY COUNT======"
echo "↓ Proxies count (default 1):"
read PROXY_COUNT
if [[ ! "$PROXY_COUNT" ]]; then
    PROXY_COUNT=1
fi
echo "● Selected: $PROXY_COUNT"

sleep 1

####
echo "======CONFIGURE PROXY PROTOCOL======"
echo "↓ Proxies protocol (http, socks5; default http):"
read PROXY_PROTOCOL
if [[ PROXY_PROTOCOL != "socks5" ]]; then
    PROXY_PROTOCOL="http"
fi
echo "● Selected: $PROXY_PROTOCOL"

sleep 1

####
echo "======CONFIGURE VAR FILES======"
echo $PROXY_NETWORK >>~/v_network.txt
echo $PROXY_COUNT >>~/v_count.txt
echo $PROXY_NET_MASK >>~/v_netmask.txt
echo $PROXY_AUTHORISATION >>~/v_authmode.txt
echo $PROXY_AUTH_IP >>~/v_authip.txt

echo "Writing data $PROXY_NETWORK to v_network.txt"
echo "Writing data $PROXY_COUNT to v_count.txt"
echo "Writing data $PROXY_NET_MASK to v_netmask.txt"
echo "Writing data $PROXY_AUTHORISATION to v_authmode.txt"
echo "Writing data $PROXY_AUTH_IP to v_authip.txt"

sleep 1

####
echo "======GET SERVER IP && CONFIGURE NET======"
PROXY_NETWORK=$(echo $PROXY_NETWORK | awk -F:: '{print $1}')
echo "● Selected: Network=$PROXY_NETWORK"
echo "● Selected: Network Mask=$PROXY_NET_MASK"
HOST_IPV4_ADDR=$(hostname -I | awk '{print $1}')
echo "● Selected: Host IPv4 address=$HOST_IPV4_ADDR"

sleep 1

####
echo "======CONFIGURE && GEN PROXY======"
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

sleep 1

####
echo "======CONFIGURE AUTORUN======"
echo "● Setting up /etc/rc.local"
cat >/etc/rc.local <<END
#!/bin/bash

ulimit -n 600000
ulimit -u 600000
ulimit -i 1200000
ulimit -s 1000000
ulimit -l 200000
/sbin/ip addr add ${PROXY_NETWORK}::/${PROXY_NET_MASK} dev he-ipv6
sleep 5
/sbin/ip -6 route add default via ${PROXY_NETWORK}::1
/sbin/ip -6 route add local ${PROXY_NETWORK}::/${PROXY_NET_MASK} dev lo
/sbin/ip tunnel add he-ipv6 mode sit remote ${TUNNEL_IPV4_ADDR} local ${HOST_IPV4_ADDR} ttl 255
/sbin/ip link set he-ipv6 up
/sbin/ip -6 route add 2000::/3 dev he-ipv6
~/ndppd/ndppd -d -c ~/ndppd/ndppd.conf
sleep 2
~/3proxy/bin/3proxy ~/3proxy/3proxy.cfg
exit 0

END
/bin/chmod +x /etc/rc.local

sleep 1

####
echo "======CONFIGURE REBUILD SCRIPT======"
cd ~
wget https://raw.githubusercontent.com/avcvv/IPv6ProxyInstaller/main/rebuild.sh
chmod +x rebuild.sh

sleep 1

####
echo "======REBOOT======"
echo "● Finishing and rebooting"
#reboot now
reboot
