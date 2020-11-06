#!/bin/bash

# =========================================================
# ENV template replacement
# =========================================================
. .env

MANIFAST_REPO="https://github.com/goatwu1993/arm-template-json.git"
MANIFAST_REPO_BRANCH="main"
REPO_OUTPUT_DIR="manifast-iot-hub"
MANIFAST_PATH="${REPO_OUTPUT_DIR}/manifast"
ENV_TEMPLATE_PATH="${MANIFAST_PATH}/env-template"
ENV_PATH="${MANIFAST_PATH}/.env"

git clone "${MANIFAST_REPO}" --single-branch --branch "${MANIFAST_REPO_BRANCH}" ${REPO_OUTPUT_DIR}
cp ${ENV_TEMPLATE_PATH} ${ENV_PATH}

IOTHUB_CONNECTION_STRING=$(az iot hub show-connection-string --name ${IOTHUB_NAME} | jq ".connectionString")
CUSTOM_VISION_TRAINING_KEY=$(az cognitiveservices account keys list --name ${CUSTOMVISION_NAME} -g ${RESOURCE_GROUP} | jq ".key1")
CUSTOM_VISION_ENDPOINT=$(az cognitiveservices account show --name ${CUSTOMVISION_NAME} -g ${RESOURCE_GROUP} | jq ".properties.endpoint")
SUBSCRIPTION_ID=$(az account show | jq ".id")
TENANT_ID=$(az account show | jq ".managedByTenants[0].tenantId")

# App/sp not yet created. Create now
az ams account sp create -a ${AMS_NAME} -g ${RESOURCE_GROUP} -n ${AMS_SP_NAME} -p ${AMS_SP_SECRET} --role Owner > /dev/null 2>&1

AMS_SP_JSON=$(az ams account sp reset-credentials -a ${AMS_NAME} -g ${RESOURCE_GROUP} -n ${AMS_SP_NAME} -p ${AMS_SP_SECRET} --role Owner)
echo $AMS_SP_JSON
AMS_SP_SECRET=$(echo ${AMS_SP_JSON} | jq ".AadSecret")
AMS_SP_ID=$(echo ${AMS_SP_JSON} | jq ".AadClientId")
AMS_NAME="\"${AMS_NAME}\""

echo "IOTHUB_CONNECTION_STRING:   ${IOTHUB_CONNECTION_STRING}"
echo "CUSTOM_VISION_TRAINING_KEY: ${CUSTOM_VISION_TRAINING_KEY}"
echo "CUSTOM_VISION_ENDPOINT:     ${CUSTOM_VISION_ENDPOINT}"
echo "SUBSCRIPTION_ID:            ${SUBSCRIPTION_ID}"
echo "TENANT_ID:                  ${TENANT_ID}"
echo "AMS_NAME:                   ${AMS_NAME}"
echo "AMS_SP_ID:                  ${AMS_SP_ID}"
echo "AMS_SP_SECRET:              ${AMS_SP_SECRET}"

echo "Gening .env ${ENV_PATH}"

sed -i -e "s|^IOTHUB_CONNECTION_STRING=.*$|IOTHUB_CONNECTION_STRING=$IOTHUB_CONNECTION_STRING|g" ${ENV_PATH}
sed -i -e "s/^SUBSCRIPTION_ID=.*$/SUBSCRIPTION_ID=${SUBSCRIPTION_ID}/g" ${ENV_PATH}
sed -i -e "s/^RESOURCE_GROUP=.*$/RESOURCE_GROUP=\"${RESOURCE_GROUP}\"/g" ${ENV_PATH}
sed -i -e "s/^TENANT_ID=.*$/TENANT_ID=${TENANT_ID}/g" ${ENV_PATH}
sed -i -e "s/^SERVICE_NAME=.*$/SERVICE_NAME=${AMS_NAME}/g" ${ENV_PATH}
sed -i -e "s/^SERVICE_PRINCIPAL_APP_ID=.*$/SERVICE_PRINCIPAL_APP_ID=${AMS_SP_ID}/g" ${ENV_PATH}
sed -i -e "s/^SERVICE_PRINCIPAL_SECRET=.*$/SERVICE_PRINCIPAL_SECRET=${AMS_SP_SECRET}/g" ${ENV_PATH}
sed -i -e "s|^CUSTOM_VISION_ENDPOINT=.*$|CUSTOM_VISION_ENDPOINT=${CUSTOM_VISION_ENDPOINT}|g" ${ENV_PATH}
sed -i -e "s/^CUSTOM_VISION_TRAINING_KEY.*$/CUSTOM_VISION_TRAINING_KEY=${CUSTOM_VISION_TRAINING_KEY}/g" ${ENV_PATH}
