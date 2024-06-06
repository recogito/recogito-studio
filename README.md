# recogito-studio

Recogito-Studio is ready for self-hosting and these instructions detail the steps necessary for deployment on Ubuntu Linux, v24 (although many earlier versions will also work as well). The deployment strategy utilizes [Docker](https://www.docker.com/), [Docker Compose](https://docs.docker.com/compose/), and [Nginx](https://nginx.org).

In the example below we will install Recogito Studio on a [Digital Ocean Droplet](https://docs.digitalocean.com/products/droplets/). Digital Ocean is a well-regarded cloud hosting platform known for its ease of use and competitive pricing, but the instructions are easily translated to other cloud platforms or on-premises data centers.

These instructions assume that you have an available domain, with access to create new DNS records.

## Digital Ocean Example

If you do not have an account on Digital Ocean, create one and then proceed as below.

### Create new droplet (Ubuntu, latest version)

![Creating a DO Droplet](./assets/images/create-droplet-1.png)

Choose an appropriate region and the recommended datacenter. For this demo we will be using the Ubuntu image and the latest version.

![Choose OS](./assets/images/create-droplet-2.png)

Here we choose a Basic shared CPU, Regular SSD, and a 4GB Memory, 2 CPUs, and 80GB SSD drive. In general a Recogito Studio instance should have at least 4GB memory. Recommend 50GB or more of storage.

![Droplet Spec](./assets/images/create-droplet-3.png)

For a Production level installation, it is recommended that you enable automatic backups.

Choose your preferred Authentication Method (Here we are using Password)

![Choose Auth Method](./assets/images/create-droplet-4.png)

Give the instance an appropriate name and the Create Droplet.

![Create Droplet](./assets/images/create-droplet-5.png)

Once created navigate to your new droplet. Make note of the ipv4 address.

![All Created](./assets/images/secure-droplet-1.png)
 
### Setup droplet with a non-root user and firewall

It is recommended that you do not use the root user for the installation. The instructions are detailed [here](https://www.digitalocean.com/community/tutorials/initial-server-setup-with-ubuntu) and summarized below.

#### SSH to your instance

~~~bash
ssh root@your_server_ip
~~~

When you first login to your instance you may see a message about available updates.  

~~~
Expanded Security Maintenance for Applications is not enabled.

67 updates can be applied immediately.
16 of these updates are standard security updates.
To see these additional updates run: apt list --upgradable

Enable ESM Apps to receive additional future security updates.
See https://ubuntu.com/esm or run: sudo pro status



The programs included with the Ubuntu system are free software;
the exact distribution terms for each program are described in the
individual files in /usr/share/doc/*/copyright.

Ubuntu comes with ABSOLUTELY NO WARRANTY, to the extent permitted by
applicable law.
~~~

It is a good practice to go ahead and update your instance with the latest packages. Run apt update.  apt is the general package manager for the Ubuntu OS.

~~~
apt update
~~~

#### Create a new user with sudo privileges.

~~~
adduser recogito
~~~

Specify a secure password.

~~~
info: Adding user `recogito' ...
info: Selecting UID/GID from range 1000 to 59999 ...
info: Adding new group `recogito' (1000) ...
info: Adding new user `recogito' (1000) with group `recogito (1000)' ...
info: Creating home directory `/home/recogito' ...
info: Copying files from `/etc/skel' ...
New password:
Retype new password:
passwd: password updated successfully
Changing the user information for recogito
Enter the new value, or press ENTER for the default
	Full Name []: Recogito User
	Room Number []:
	Work Phone []:
	Home Phone []:
	Other []:
Is the information correct? [Y/n] y
info: Adding new user `recogito' to supplemental / extra groups `users' ...
info: Adding user `recogito' to group `users' ...
~~~

Give user administrative privileges.

~~~
usermod -aG sudo recogito
~~~

#### Setup Firewall

Always secure your instances with firewall rules.  Ubuntu servers can utilize the UFW Firewall although other methods are available.  Here we will utilize UFW.

List the current firewall rules:

~~~
ufw app list
~~~

Output:

~~~
Available applications:
  OpenSSH
~~~

Allow SSH connections:

~~~
ufw allow OpenSSH
~~~

Go ahead and enable the firewall:

~~~
ufw enable
~~~

Type 'y' and press enter.

Confirm the firewall is active.

~~~
ufw status
~~~

Output:

~~~
Status: active

To                         Action      From
--                         ------      ----
OpenSSH                    ALLOW       Anywhere
OpenSSH (v6)               ALLOW       Anywhere (v6)
~~~

Follow the rest of the instructions based on how you setup authentication for your instance.

### Login with non-root user or user with sudo privledges

~~~
ssh recogito@your_server_ip
~~~

### Install Nginx

Nginx is a capable, well tested HTTP and reverse proxy server.  Here we will utilize Nginx to route traffic correctly to our recogito-studio client and server.


The instructions and details on installing Nginx on Ubuntu are detailed [here](https://www.digitalocean.com/community/tutorials/how-to-install-nginx-on-ubuntu-22-04) and summarized below.

#### Install Nginx

~~~
sudo apt update
sudo apt install nginx
~~~

#### Adjust the firewall settings

Now that we have a web server, we need to update our firewall to allow HTTP and HTTPS connections to out instance.

List the available services:

~~~
sudo ufw app list
~~~

Output:

~~~
Available applications:
  Nginx Full
  Nginx HTTP
  Nginx HTTPS
  OpenSSH
~~~

As you can see we now have new options for our firewall settings with the added Nginx applications.

We are going to go ahead and allow the Nginx Full applications, which will allow HTTP and HTTPS.

~~~
sudo ufw allow 'Nginx Full'
~~~

Check the status again to ensure we have successfully enabled access:

~~~
sudo ufw status
~~~

Output:

~~~
Status: active

To                         Action      From
--                         ------      ----
OpenSSH                    ALLOW       Anywhere
Nginx Full                 ALLOW       Anywhere
OpenSSH (v6)               ALLOW       Anywhere (v6)
Nginx Full (v6)            ALLOW       Anywhere (v6)
~~~

Check that Nginx is running:

~~~
systemctl status nginx
~~~

Output:

~~~
● nginx.service - A high performance web server and a reverse proxy server
     Loaded: loaded (/usr/lib/systemd/system/nginx.service; enabled; preset: enabled)
     Active: active (running) since Thu 2024-06-06 14:27:21 UTC; 6min ago
       Docs: man:nginx(8)
    Process: 3188 ExecStartPre=/usr/sbin/nginx -t -q -g daemon on; master_process on; (code=exited, status=0/SUCCESS)
    Process: 3190 ExecStart=/usr/sbin/nginx -g daemon on; master_process on; (code=exited, status=0/SUCCESS)
   Main PID: 3191 (nginx)
      Tasks: 3 (limit: 4658)
     Memory: 2.4M (peak: 2.8M)
        CPU: 31ms
     CGroup: /system.slice/nginx.service
             ├─3191 "nginx: master process /usr/sbin/nginx -g daemon on; master_process on;"
             ├─3192 "nginx: worker process"
             └─3193 "nginx: worker process"
~~~

To check that Nginx is properly active, you can go ahead and navigate in a browser to your IP address:

~~~
http://your_server_ip
~~~

You should see the Nginx welcome screen:

![Nginx welcome](./assets/images/nginx-welcome.png)

We are going to do the rest of the Nginx setup after we have installed Recogito Studio.


### Install dependencies

There are a few additional dependencies we need to have installed in order to install Recogito Studio.

#### Git

Git is the industry standard version control system and the installation process requires that it be installed.

Git is often already installed on many Cloud OS instances, which is true for Digital Oceans Ubuntu droplets. Make sure git is installed:

~~~
git --version
~~~

Output:

~~~
git version 2.43.0
~~~

#### Docker

Docker is a container generation and management system. We will install it using the [SNAP](https://snapcraft.io/) packager that is standard on Digital Ocean Linux images.

Install Docker:

~~~
snap install docker
~~~

#### NPM

NPM (Node Package Manager) is a package manager and management tool for [node js](https://nodejs.org/en) which is a Javascript runtime environment. There are a number of tools and applications in the Recogito Studio platform that require NPM and node js.

Installing NPM will also install node js.

~~~
sudo apt install npm
~~~

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
