server {
    server_name server.example.com;

    location / {

        # Preflighted requests
        if ($request_method = OPTIONS ) {
            add_header "Access-Control-Allow-Origin"  https://client.example.com;
            add_header "Access-Control-Allow-Methods" "GET, POST, OPTIONS, HEAD, PATCH";
            add_header "Access-Control-Allow-Credentials" true;
            add_header "Access-Control-Allow-Headers" "Authorization, Origin, X-Client-Info, X-Requested-With, Content-Type, Content-Profile, Accept, Apikey, Accept-Profile, Prefer, X-Supabase-Api-Version";
            return 200;
        }

        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_set_header Host $host;
        proxy_hide_header "Access-Control-Allow-Origin";
        add_header "Access-Control-Allow-Origin"  https://client.example.com always;
        add_header "Access-Control-Allow-Credentials" true always;
    }

}