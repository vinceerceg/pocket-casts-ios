#!/bin/bash -eu

"$(dirname "${BASH_SOURCE[0]}")/shared_setup.sh"

echo "--- :closed_lock_with_key: Installing Secrets"
bundle exec fastlane run configure_apply

echo "--- :hammer_and_wrench: Building"
bundle exec fastlane build_and_upload_app_store_connect \
  skip_confirm:true \
  create_release:true \
  skip_prechecks:true \
  beta_release:${1:-true} # use first call param, default to true for safety
