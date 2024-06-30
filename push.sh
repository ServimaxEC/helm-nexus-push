#!/usr/bin/env bash

set -ueo pipefail

usage() {
cat << EOF
Push Helm Chart to Nexus repository

This plugin provides ability to push a Helm Chart directory or package to a
remote Nexus Helm repository.

Usage:
  helm nexus-push [repo] login [flags]        Setup login information for repo
  helm nexus-push [repo] logout [flags]       Remove login information for repo
  helm nexus-push [repo] [CHART] [flags]      Pushes chart to repo

Flags:
  -u, --username string                 Username for authenticated repo (assumes anonymous access if unspecified)
  -p, --password string                 Password for authenticated repo (prompts if unspecified and -u specified)
EOF
}

declare USERNAME
declare PASSWORD
declare APPVERSION

declare -a POSITIONAL_ARGS=()
while [[ $# -gt 0 ]]
do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        -u|--username)
            if [[ -z "${2:-}" ]]; then
                echo "Must specify username!"
                echo "---"
                usage
                exit 1
            fi
            shift
            USERNAME=$1
            ;;
        -p|--password)
            if [[ -n "${2:-}" ]]; then
                shift
                PASSWORD=$1
            else
                PASSWORD=
            fi
            ;;
		-av|--app-version)
            if [[ -n "${2:-}" ]]; then
                shift
                APPVERSION=$1
            else
                APPVERSION=
            fi
            ;;
        *)
            POSITIONAL_ARGS+=("$1")
            ;;
   esac
   shift
done
[[ ${#POSITIONAL_ARGS[@]} -ne 0 ]] && set -- "${POSITIONAL_ARGS[@]}" # restore positional parameters

if [[ $# -lt 2 ]]; then
  echo "Missing arguments!"
  echo "---"
  usage
  exit 1
fi

indent() { sed 's/^/  /'; }

declare HELM3_VERSION="$(helm version --client --short | grep "v3\.")"

declare REPO=$1
declare REPO_URL="$(helm repo list | grep "^$REPO" | awk '{print $2}')/"

if [[ -n $HELM3_VERSION ]]; then
declare REPO_AUTH_FILE="$HOME/.config/helm/auth.$REPO"
else
declare REPO_AUTH_FILE="$(helm home)/repository/auth.$REPO"
fi

if [[ -z "$REPO_URL" ]]; then
    echo "Invalid repo specified!  Must specify one of these repos..."
    helm repo list
    echo "---"
    usage
    exit 1
fi

declare CMD
declare AUTH
declare CHART

# Add repos 
declare REPO_NAME_RELEASE="cf-helm-releases"
declare REPO_NAME_SNAPSHOT="cf-helm-snapshots"
declare REPO_URL_RELEASE="https://cf1hlmnxs.servimaxec.com/repository/helm-releases/"
declare REPO_URL_SNAPSHOT="https://cf1hlmnxs.servimaxec.com/repository/helm-snapshots/"

case "$2" in
    login)
        if [[ -z "$USERNAME" ]]; then
            read -p "Username: " USERNAME
        fi
        if [[ -z "$PASSWORD" ]]; then
            read -s -p "Password: " PASSWORD
            echo
        fi
        echo "$USERNAME:$PASSWORD" > "$REPO_AUTH_FILE"
        ;;
    logout)
        rm -f "$REPO_AUTH_FILE"
        ;;
    *)
        CMD=push
        CHART=$2

        if [[ -z "$USERNAME" ]] || [[ -z "$PASSWORD" ]]; then
            if [[ -f "$REPO_AUTH_FILE" ]]; then
                echo "Using cached login creds..."
                AUTH="$(cat $REPO_AUTH_FILE)"
            else
                if [[ -z "$USERNAME" ]]; then
                    read -p "Username: " USERNAME
                fi
                if [[ -z "$PASSWORD" ]]; then
                    read -s -p "Password: " PASSWORD
                    echo
                fi
                AUTH="$USERNAME:$PASSWORD"
            fi
		else
			AUTH="$USERNAME:$PASSWORD"
        fi

        if [[ -d "$CHART" ]]; then 
			if [ -z ${APPVERSION+x} ]; then 				
				echo "APPVERSION is not set"; 
				CHART_PACKAGE="$(helm package "$CHART" | cut -d":" -f2 | tr -d '[:space:]')"				
			else 
				echo "APPVERSION is set to '$APPVERSION'";
				
				{
					helm plugin uninstall pack
				} || { 
					echo "No existe plugin pack previamente instalado.";
				}	
				
				helm plugin install https://github.com/thynquest/helm-pack.git
				CHART_PACKAGE="$(helm pack "$CHART" --version "${APPVERSION,,}" --app-version "${APPVERSION^^}" --set global.appVersion="${APPVERSION^^}" | cut -d":" -f2 | tr -d '[:space:]')"
				helm plugin uninstall pack
			fi		
		else
            CHART_PACKAGE="$CHART"
        fi

        helm repo add $REPO_NAME_RELEASE $REPO_URL_RELEASE --username $USERNAME --password $PASSWORD
        helm repo add $REPO_NAME_SNAPSHOT $REPO_URL_SNAPSHOT --username $USERNAME --password $PASSWORD

        if [[ "$REPO" == "." ]]; then
            if [[ "$CHART_PACKAGE" == *"release"* ]]; then
                REPO_URL=$REPO_URL_RELEASE
            else
                REPO_URL=$REPO_URL_SNAPSHOT
            fi
        fi

        echo "Pushing $CHART to repo $REPO_URL..."
        curl -is -u "$AUTH" "$REPO_URL" --upload-file "$CHART_PACKAGE" | indent
        echo "Done"
        ;;
esac

exit 0
