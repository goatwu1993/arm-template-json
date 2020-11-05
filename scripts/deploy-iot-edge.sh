#!/bin/bash

# This script generates a deployment manifest template and deploys it to an existing IoT Edge device

# =========================================================
# Variables
# =========================================================
MANIFAST_REPO="https://github.com/goatwu1993/arm-template-json.git"
MANIFAST_BRANCH="master"
MANIFAST_PATH="arm-template-json.git/manifast"

IOTEDGE_DEV_VERSION="2.1.0"


# =========================================================
# Define helper function for logging
# =========================================================
info() {
    echo "$(date +"%Y-%m-%d %T") [INFO]"
}

# Define helper function for logging. This will change the Error text color to red
error() {
    echo "$(tput setaf 1)$(date +"%Y-%m-%d %T") [ERROR]"
}

exitWithError() {
    # Reset console color
    tput sgr0
    exit 1
}

# =========================================================
# Login Azure
# =========================================================
echo "Logging in with Managed Identity"
az login --identity --output "none"
# =========================================================
# Download the latest manifest-bundle.zip from storage account
# =========================================================
apt-get update
apt-get install -y git jq
git clone "${MANIFAST_REPO}" --single-branch --branch "${MANIFAST_BRANCH}"

# =========================================================
# Install packages
# =========================================================
echo "Installing packages"
echo "Installing iotedgedev"
pip install iotedgedev=="${IOTEDGE_DEV_VERSION}"

echo "Updating az-cli"
pip install --upgrade azure-cli
pip install --upgrade azure-cli-telemetry

echo "installing azure iot extension"
az extension add --name azure-iot

pip3 install --upgrade jsonschema
apk add coreutils
echo "Installation complete"

# =========================================================
# IoT Hub Create IoTHub/Edge device if not exists
# =========================================================
# We're enabling exit on error after installation steps as there are some warnings and error thrown in installation steps which causes the script to fail
set -e


# Check for existence of IoT Hub and Edge device in Resource Group for IoT Hub,
# and based on that either throw error or use the existing resources
if [ -z "$(az iot hub list --query "[?name=='$IOTHUB_NAME'].name" --resource-group "$RESOURCE_GROUP" -o tsv)" ]; then
    echo "$(error) IoT Hub \"$IOTHUB_NAME\" does not exist."
    exit 1
else
    echo "$(info) Using existing IoT Hub \"$IOTHUB_NAME\""
fi

if [ -z "$(az iot hub device-identity list --hub-name "$IOTHUB_NAME" --resource-group "$RESOURCE_GROUP" --query "[?deviceId=='$DEVICE_NAME'].deviceId" -o tsv)" ]; then
    echo "$(error) Device \"$DEVICE_NAME\" does not exist in IoT Hub \"$IOTHUB_NAME\""
    exit 1
else
    echo "$(info) Using existing Edge Device \"$IOTHUB_NAME\""
fi

# =========================================================
# ENV template replacement
# =========================================================
ENV_TEMPLATE_PATH="env-template"
ENV_PATH=".env"

cp ${ENV_TEMPLATE_PATH} ${ENV_PATH}
IOTHUB_CONNECTION_STRING=$(az iot hub show-connection-string --name ${IOTHUB_NAME} | jq ".connectionString")
CUSTOM_VISION_TRAINING_KEY=$(az cognitiveservices account keys list --name ${CUSTOMVISION_NAME} -g ${RESOURCE_GROUP} | jq ".key1")
CUSTOM_VISION_ENDPOINT=$(az cognitiveservices account show --name ${CUSTOMVISION_NAME} -g ${RESOURCE_GROUP} | jq ".properties.endpoint")
SUBSCRIPTION_ID=$(az account show | jq ".id")
TENANT_ID=$(az account show | jq ".managedByTenants[0].tenantId")
SERVICE_NAME=$()

# =========================================================
# Choosing IoTHub Deployment template
# =========================================================
printf "\n%60s\n" " " | tr ' ' '-'
echo "Configuring IoT Hub"
printf "%60s\n" " " | tr ' ' '-'


MANIFEST_TEMPLATE_BASE_NAME="deployment"
MANIFEST_ENVIRONMENT_VARIABLES_FILENAME=".env"

if [ "$DETECTOR_MODULE_RUNTIME" == "CPU" ]; then
    MANIFEST_TEMPLATE_NAME="${MANIFEST_TEMPLATE_BASE_NAME}.cpu"
elif [ "$DETECTOR_MODULE_RUNTIME" == "NVIDIA" ]; then
    MANIFEST_TEMPLATE_NAME="${MANIFEST_TEMPLATE_BASE_NAME}.gpu"
elif [ "$DETECTOR_MODULE_RUNTIME" == "MOVIDIUS" ]; then
    MANIFEST_TEMPLATE_NAME="${MANIFEST_TEMPLATE_BASE_NAME}.vpu"
fi

# Update the value of RUNTIME variable in environment variable file
sed -i 's#^\(RUNTIME[ ]*=\).*#\1\"'"$MODULE_RUNTIME"'\"#g' "$MANIFEST_ENVIRONMENT_VARIABLES_FILENAME"

if [ "$EDGE_DEVICE_ARCHITECTURE" == "ARM64" ]; then
    MANIFEST_TEMPLATE_NAME="${MANIFEST_TEMPLATE_BASE_NAME}.arm64v8"
fi

if [ "$VIDEO_CAPTURE_MODULE" == "opencv" ]; then
    MANIFEST_TEMPLATE_NAME="${MANIFEST_TEMPLATE_BASE_NAME}.opencv"
fi

MANIFEST_TEMPLATE_NAME="${MANIFEST_TEMPLATE_BASE_NAME}.json"

# =========================================================
# Generate Deployment Manifast
# =========================================================
echo "$(info) Generating manifest file from template file"
# Generate manifest file
iotedgedev genconfig --file "$MANIFEST_TEMPLATE_NAME" --platform "$PLATFORM_ARCHITECTURE"

echo "$(info) Generated manifest file"

#Construct file path of the manifest file by getting file name of template file and replace 'template.' with '' if it has .json extension
#iotedgedev service used deployment.json filename if the provided file does not have .json extension
#We are prefixing ./config to the filename as iotedgedev service creates a config folder and adds the manifest file in that folder

# if .json then remove template. if present else deployment.json
if [[ "$MANIFEST_TEMPLATE_NAME" == *".json"* ]]; then
    # Check if the file name is like name.template.json, if it is construct new name as name.json
    # Remove last part (.json) from file name
    TEMPLATE_FILE_NAME="${MANIFEST_TEMPLATE_NAME%.*}"
    # Get the last part form file name and check if it is template
    IS_TEMPLATE="${TEMPLATE_FILE_NAME##*.}"
    if [ "$IS_TEMPLATE" == "template" ]; then
        # Get everything but the last part (.template) and append .json to construct new name
        TEMPLATE_FILE_NAME="${TEMPLATE_FILE_NAME%.*}.json"
        PRE_GENERATED_MANIFEST_FILENAME="./config/$(basename "$TEMPLATE_FILE_NAME")"
    else
        PRE_GENERATED_MANIFEST_FILENAME="./config/$(basename "$MANIFEST_TEMPLATE_NAME")"
    fi
else
    PRE_GENERATED_MANIFEST_FILENAME="./config/deployment.json"
fi

if [ ! -f "$PRE_GENERATED_MANIFEST_FILENAME" ]; then
    echo "$(error) Manifest file \"$PRE_GENERATED_MANIFEST_FILENAME\" does not exist. Please check config folder under current directory: \"$PWD\" to see if manifest file is generated or not"
fi


# This step deploys the configured deployment manifest to the edge device. After completed,
# the device will begin to pull edge modules and begin executing workloads (including sending
# messages to the cloud for further processing, visualization, etc).
# Check if a deployment with given name, already exists in IoT Hub. If it doesn't exist create a new one.
# If it exists, append a random number to user given deployment name and create a deployment.

# =========================================================
# IoT Hub Deploy
# =========================================================
az iot edge deployment create --deployment-id "$DEPLOYMENT_NAME" --hub-name "$IOTHUB_NAME" --content "$PRE_GENERATED_MANIFEST_FILENAME" --target-condition "deviceId='$DEVICE_NAME'" --output "none"

echo "$(info) Deployed manifest file to IoT Hub. Your modules are being deployed to your device now. This may take some time."
