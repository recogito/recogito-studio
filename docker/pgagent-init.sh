#!/bin/bash

apt-get update && apt-get install pgagent

pgagent hostaddr=localhost dbname=postgres user=postgres -s pgagent_log.log