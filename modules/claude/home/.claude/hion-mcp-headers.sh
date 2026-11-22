#!/bin/sh
# Claude Code's headersHelper for the hion MCP server: prints the
# Authorization header from the token lodestar renders out of Bitwarden
# (~/.config/hion/api-token, 0600), so the token never sits in ~/.claude.json.
token=$(tr -d '\n' < "$HOME/.config/hion/api-token")
printf '{"Authorization":"Bearer %s"}\n' "$token"
