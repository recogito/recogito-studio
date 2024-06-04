# recogito-studio

Self hosting code for Recogito-Studio

## Digital Ocean Example

### Create new droplet (ubuntu, latest version)

Droplet should have at least 4GB memory. Recommend 50GB storage

### Setup droplet with a non-root user and firewall

Follow the instructions [here](https://www.digitalocean.com/community/tutorials/initial-server-setup-with-ubuntu)

### Login with non-root user or user with sudo privledges

### Install Nginx

Follow the instructions [here](https://www.digitalocean.com/community/tutorials/how-to-install-nginx-on-ubuntu-22-04)

### Install dependencies

#### Git

Make sure git is installed (it is usually installed by default on ubuntu)

```
git --version
```

#### Docker

```
snap install docker
```

#### NPM

```
apt install npm
```

### Clone Recogito Studio (This repository)

```
git clone --depth 1 https://github.com/recogito/recogito-studio.git
```

```
cd ./recogito-studio
```

### Update ./docker/.env

Update the .env file in ./docker with appropriate variables

### Run the installation script

From the recogito-studio directory run the install script

```
bash ./install-self-hosted-docker.sh
```
