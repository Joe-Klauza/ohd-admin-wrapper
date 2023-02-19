#!/usr/bin/env bash

wrapper_root="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

cd "$wrapper_root"/admin-interface

while true; do
  bundle && bundle exec ruby "$wrapper_root"/admin-interface/lib/webapp.rb "$@"
  CODE=$?
  [ $CODE -eq 2 ] || exit $CODE # Restart if exit code 2
done

