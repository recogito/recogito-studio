# Recogito Studio

## RecogitoStudio is ready for self-hosting! 

[Documentation](https://recogitostudio.org/guides/self-hosting/)

## Upgrade Recogito Studio

### Manual upgrade

To upgrade your self-hosted instance, you can follow the [manual upgrade guide](https://recogitostudio.org/guides/self-hosting/#upgrading).

### Automatic upgrade via shell script

For a faster, hands-off upgrade process, you can use the provided `upgrade.sh` script. This script automatically pulls the latest code, applies your custom configurations, builds the new Docker image, updates the database schema, and restarts your containers.

Make sure you are in the root of this repo, `recogito-studio`, and pull the latest version.
```sh
cd /path/to/recogito-studio
git pull
```

Before upgrading, compare your live `.env` file against the latest `.env.example` to ensure you aren't missing any newly required variables.
```sh
cat ./docker/.env.example
```

Before you can run the script for the first time, you will need to grant it execution permissions.
```sh
chmod +x upgrade.sh
```

Finally, execute the script.
```sh
./upgrade.sh
```

> Note: The upgrade process builds a new Docker image from scratch and pushes schema changes to your database. Depending on your server's resources, this process usually takes a few minutes to complete.
