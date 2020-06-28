#!/bin/bash

if [[ $EUID -ne 0 ]]; then
	echo -e "Sorry, you need to run this as root"
	exit 1
fi

# get response codes
responseipv4=$(curl --head --write-out %{http_code} --silent --output /dev/null https://www.cloudflare.com/ips-v4)
responseipv6=$(curl --head --write-out %{http_code} --silent --output /dev/null https://www.cloudflare.com/ips-v6)

# do only, if both adresses are reachable
if [ "$responseipv4" == "200" ] && [ "$responseipv6" == "200" ]; then
	CURRENT_TIME="$(date +%d.%m.%Y) $(date +%X)"
	curl https://www.cloudflare.com/ips-v4 -o /tmp/cf_ipv4
	curl https://www.cloudflare.com/ips-v6 -o /tmp/cf_ipv6
	cat /tmp/cf_ipv4 /tmp/cf_ipv6 > /tmp/cf_ips

	# Nginx
	if type "nginx" &> /dev/null; then
		CLOUDFLARE_FILE_PATH=/etc/nginx/conf.d/cloudflare_realip.conf
		echo "# Cloudflare" > $CLOUDFLARE_FILE_PATH;
		echo "# Last Change: $CURRENT_TIME" >> $CLOUDFLARE_FILE_PATH;

		echo $'\n'"# - IPv4" >> $CLOUDFLARE_FILE_PATH;
		for i in `cat /tmp/cf_ipv4`; do
			echo "set_real_ip_from $i;" >> $CLOUDFLARE_FILE_PATH;
		done

		echo $'\n'"# - IPv6" >> $CLOUDFLARE_FILE_PATH;
		for i in `cat /tmp/cf_ipv6`; do
			echo "set_real_ip_from $i;" >> $CLOUDFLARE_FILE_PATH;
		done

		echo $'\n'"real_ip_header CF-Connecting-IP;" >> $CLOUDFLARE_FILE_PATH;

		# test configuration and reload nginx
		nginx -t && systemctl reload nginx
	fi

	# Apache2
	if type "apache2ctl" &> /dev/null; then
		CLOUDFLARE_FILE_PATH=/etc/apache2/conf-available/cloudflare_realip.conf

		echo "# Cloudflare" > $CLOUDFLARE_FILE_PATH;
		echo "# Last Change: $CURRENT_TIME" >> $CLOUDFLARE_FILE_PATH;

		echo $'\n'"# - IPv4" >> $CLOUDFLARE_FILE_PATH;
		for i in `cat /tmp/cf_ipv4`; do
			echo "RemoteIPTrustedProxy $i" >> $CLOUDFLARE_FILE_PATH;
		done

		echo $'\n'"# - IPv6" >> $CLOUDFLARE_FILE_PATH;

		for i in `cat /tmp/cf_ipv6`; do
			echo "RemoteIPTrustedProxy $i" >> $CLOUDFLARE_FILE_PATH;
		done

		echo $'\n'"RemoteIPHeader CF-Connecting-IP" >> $CLOUDFLARE_FILE_PATH;

		# enable modul
		if [ ! -f /etc/apache2/mods-enabled/remoteip.load ]; then
			a2enmod remoteip
		fi

		if [ ! -f /etc/apache2/conf-enabled/cloudflare_realip.conf ]; then
			a2enconf cloudflare_realip
		fi

		# test configuration and reload apache
		apache2ctl configtest && systemctl reload apache2
	fi

	# ufw if avaiable and active
	if type "ufw" &> /dev/null && ! ufw status | grep -q inactive$; then
		# delete old rules which are commented clearly with "Cloudflare IP". Don't ever comment an ufw rule with that. Otherwise it will get deleted too.
		for NUM in $(ufw status numbered | grep 'Cloudflare IP' | awk -F"[][]" '{print $2}' | tr --delete [:blank:] | sort -rn); do
			yes | ufw delete $NUM;
		done

		# add new ip rules for ufw
		for cfip in `cat /tmp/cf_ips`; do
			ufw allow proto tcp from $cfip to any port 80,443 comment 'Cloudflare IP';
		done

		# reload firewall
		ufw reload
	fi
fi
