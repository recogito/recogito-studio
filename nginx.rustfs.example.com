server {
    server_name rustfs.example.com;

    location / {
        proxy_pass http://127.0.0.1:9011;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_set_header Host $host;
        proxy_hide_header "Access-Control-Allow-Origin";
        add_header "Access-Control-Allow-Origin"  https://rustfs.example.com always;
        add_header "Access-Control-Allow-Credentials" true always;
    }

}