#!/bin/bash

# fail fast if the config is broken before pretending to serve
nginx -t

exec nginx -g "daemon off;"
