#!/bin/bash

if [ -z "$1" ]; then
	echo "Error: No version number provided."
	echo "Usage: $0 <version_number>"
	exit 1
fi

VERSION=$1
DOWNLOAD_URL="https://updates.jenkins.io/download/war/${VERSION}/jenkins.war"
TARGET_DIR="$HOME/jenkins/jenkins-${VERSION}"
WAR_FILE="${TARGET_DIR}/jenkins.war"
LOG_FILE="$HOME/jenkins/update_log.txt"
SYMLINK_PATH="/usr/share/java/jenkins.war"

echo "----------------------------------------" | tee -a "$LOG_FILE"

if [ -e "${SYMLINK_PATH}" ]; then
	CURRENT_VERSION=$(java -jar "${SYMLINK_PATH}" --version)
	echo "Current Jenkins version: $CURRENT_VERSION" | tee -a "$LOG_FILE"
else
	echo "No existing Jenkins WAR file found at ${SYMLINK_PATH}." | tee -a "$LOG_FILE"
fi

echo "Stopping Jenkins service..."
service jenkins stop
kill $(ps aux | grep '[j]enkins' | awk '{print $2}')

mkdir -p "${TARGET_DIR}"

rm -f "${WAR_FILE}"

echo "Downloading Jenkins WAR version ${VERSION}..."
wget -O "${WAR_FILE}" "${DOWNLOAD_URL}" || {
	echo "Download failed"
	exit 1
}

if [ -e "${SYMLINK_PATH}" ]; then
	echo "Removing existing Jenkins WAR file."
	rm -f "${SYMLINK_PATH}"
fi

cp "${WAR_FILE}" "${SYMLINK_PATH}"

echo "Starting Jenkins service..."
service jenkins start

UPDATED_VERSION=$(java -jar "${SYMLINK_PATH}" --version)
echo "Updated Jenkins to version: $UPDATED_VERSION" | tee -a "$LOG_FILE"

echo "Jenkins has been updated to version ${VERSION}."
echo "WAR file copied to ${SYMLINK_PATH}."
echo "All details logged in ${LOG_FILE}."

echo "----------------------------------------" | tee -a "$LOG_FILE"
