#!/bin/bash
set -ex
rm -rf docker
rm -rf release
docker system prune -a -f

