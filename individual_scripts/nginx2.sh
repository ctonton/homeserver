#!/bin/bash
echo "Setting up NGINX."
apt-get install -y --no-install-recommends curl unzip nginx-extras php-fpm openssl
if [ ! -f /var/www/html/index.bak ]
then
  mv /var/www/html/index* /var/www/html/index.bak
fi
curl -LJO https://github.com/ctonton/homeserver/raw/main/icons.zip
unzip -o icons.zip -d /var/www/html
rm icons.zip
ln -s /srv/NAS/Public /var/www/html/files
ln -s /root/Downloads /var/www/html/egg
mv /etc/nginx/sites-available/default /etc/nginx/sites-available/default.bak
tee /var/www/html/index.html > /dev/null <<'EOT'
<html>
  <head>
    <title>Server</title>
	<style>
    .column {
    float: left;
    width: 50%;
    height: 2160px;
    }
	.row:after {
    content: "";
    display: table;
    clear: both;
    }
    </style>
  </head>
  <body style="background-color:#000000;color:yellow;font-size:125%">
    <div class="row" style="text-align:center">
      <div class="column">
        <h1>File Server</h1>
        <a href="/files/"><img src="fs.png" alt="HTTP Server"></a>
        <br>
        <br>
        <h1>Print Server</h1>
        <a href="/print/"><img src="ps.png" alt="Print Server"></a>
        <br>
        <br>
      </div>
      <div class="column" style="text-align:center">
        <h1>Torrent Server</h1>
        <a href="/torrents/"><img src="qb.png" alt="Qbittorrent"></a>
        <br>
        <br>
        <h1>Web Browser</h1>
        <a href="/novnc/vnc.html?path=novnc/websockify"><img src="ff.png" alt="Firefox"></a>
        <br>
        <br>
	  </div>
    </div>
  </body>
  <footer>
    <a href="/egg/"><img align="right" src="ee.png"></right></a>
  </footer>
</html>
EOT
mkdir /var/www/html/print
tee /var/www/html/print/index.html > /dev/null <<'EOT'
<html>
<body>
<form action="print.php" method="post" enctype="multipart/form-data">
	Select PDF to print:
	<input type="file" name="fileToUpload" id="fileToUpload">
	<input type="submit" value="Upload PDF" name="submit">
</form>
</body>
</html>
EOT
tee /var/www/html/print/print.php > /dev/null <<'EOT'
<?php
   if(isset($_FILES['fileToUpload'])){
      $file_name = $_FILES['fileToUpload']['name'];
      $file_size =$_FILES['fileToUpload']['size'];
      $file_tmp =$_FILES['fileToUpload']['tmp_name'];
      $file_type=$_FILES['fileToUpload']['type'];
      $file_ext=strtolower(end(explode('.',$_FILES['fileToUpload']['name'])));
      $extensions= array("pdf","PDF");
      if(in_array($file_ext,$extensions)=== false){
         exit("File type not allowed, please choose a PDF file.");
      }
      if($file_size > 10485760){
         exit("Maximum PDF size is 10MB, choose a smaller file.");
      }
      exec("lp $file_tmp");
      echo "PDF sent to printer.";
   }
?>
EOT
chown -R www-data:www-data /var/www/html
tee /etc/nginx/sites-available/default > /dev/null <<'EOT'
##
map $http_upgrade $connection_upgrade {
	default upgrade;
	''      close;
}
upstream novnc-firefox {
	server 127.0.0.1:5800;
}
##
server {
listen 80 default_server;
listen [::]:80 default_server;
	location / {
	return 301 https://$host$request_uri;
	}
}
##
server {
	listen 443 ssl http2;
	listen [::]:443 ssl http2;
	ssl_certificate /etc/nginx/nginx-selfsigned.crt;
	ssl_certificate_key /etc/nginx/nginx-selfsigned.key;
	ssl_session_timeout  10m;
	ssl_session_cache shared:SSL:10m;
	ssl_session_tickets off;
	ssl_dhparam /etc/nginx/dhparam.pem;
	ssl_protocols TLSv1.2 TLSv1.3;
	ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
	ssl_prefer_server_ciphers off;
	resolver 8.8.8.8 8.8.4.4 valid=300s;
	resolver_timeout 5s;
	add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
	add_header X-Frame-Options DENY;
	add_header X-Content-Type-Options nosniff;
	add_header X-XSS-Protection "1; mode=block";
	client_max_body_size 10M;
	root /var/www/html;
	index index.html;
	autoindex on;
	location /files/ {
		try_files $uri $uri/ =404;
		auth_basic "Restricted Content";
		auth_basic_user_file /etc/nginx/.htpasswd;
	}
	location /egg/ {
		try_files $uri $uri/ =404;
	}
	location /torrents/ {
		proxy_pass http://127.0.0.1:8080/;
		proxy_buffering off;
		auth_basic "Restricted Content";
		auth_basic_user_file /etc/nginx/.htpasswd;
	}
	location /print/ {
		auth_basic "Restricted Content";
		auth_basic_user_file /etc/nginx/.htpasswd;
	}
	location /print/print.php {
		include /etc/nginx/fastcgi_params;
		fastcgi_pass unix:/run/php/php-fpm.sock;
		fastcgi_index print.php;
		fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
		fastcgi_intercept_errors on;
		track_uploads uploads 300s;
		auth_basic "Restricted Content";
		auth_basic_user_file /etc/nginx/.htpasswd;
	}
	location /novnc/ {
		proxy_pass http://novnc-firefox/;
		auth_basic "Restricted Content";
		auth_basic_user_file /etc/nginx/.htpasswd;
	}
	location /novnc/websockify {
		proxy_pass http://novnc-firefox/;
		proxy_http_version 1.1;
		proxy_set_header Upgrade $http_upgrade;
		proxy_set_header Connection $connection_upgrade;
		proxy_set_header Host $host;
		auth_basic "Restricted Content";
		auth_basic_user_file /etc/nginx/.htpasswd;
	}
}
EOT
sed -i 's/www-data/root/g' /etc/nginx/nginx.conf
sed -i '/http {/a\\tclient_max_body_size 10M;\n\tupload_progress uploads 1m;' /etc/nginx/nginx.conf
tee /root/webusers.sh > /dev/null <<'EOT'
#!/bin/bash
clear
loo=0
until [ $loo -eq 4 ]
do
  echo
  echo "1 - List users"
  echo "2 - Add user"
  echo "3 - Remove user"
  echo "4 - quit"
  echo
  read -p "Enter selection: :" loo
  if [ $loo -eq 1 ]
  then
    echo
    cat /etc/nginx/.htpasswd
    loo=0
  fi
  if [ $loo -eq 2 ]
  then
    read -p "Enter a user name: " use
    echo -n "${use}:" >> /etc/nginx/.htpasswd
    openssl passwd -apr1 >> /etc/nginx/.htpasswd
    loo=0
  fi
  if [ $loo -eq 3 ]
  then
    read -p "Enter a user name to remove: " use
    sed -i "/$use/d" /etc/nginx/.htpasswd
    loo=0
  fi
  if [ $loo -ne 0 ]
  then
    echo "Invalid selection."
    echo
  fi
done
exit
EOT
chmod +x /root/webusers.sh
echo
echo "A script called webusers.sh has been created in the root directory for modifying users of the web server."
echo "Add a user for the web server now."
loo="y"
until [ $loo != "y" ]
do
  read -p "Enter a user name: " use
  echo -n "${use}:" >> /etc/nginx/.htpasswd
  openssl passwd -apr1 >> /etc/nginx/.htpasswd
  read -p "Add another user? (y/n): " loo
done
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -keyout /etc/nginx/nginx-selfsigned.key -out /etc/nginx/nginx-selfsigned.crt
curl https://ssl-config.mozilla.org/ffdhe4096.txt > /etc/nginx/dhparam.pem
nginx -s reload
exit
