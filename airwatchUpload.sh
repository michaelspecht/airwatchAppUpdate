
#!/bin/bash
# ------------------------------------------------------------------
#          AirWatch Upload and Install
#          Upload an iOS App Binary to the AirWatch catalog, then
#          install the app on all eligible devices
#
#
#   $1  - Authentication: Base 64 encoded username:password
#   $2  - TenantCode
#   $3  - BinaryFilePath
#   $4  - Application Name
#   $5  - File Name
#   $6  - Application ID in AirWatch
#   $7  - VSTS Version String (For example, 20170312.10) Airwatch has limitations on the number of characters in a version, so we need to break this apart
#   $8  - iPhone/iPod touch enabled (1 or 0)
#   $9  - iPad enabled (1 or 0)
#   $10 - AirWatch URL (e.g. https://cn000.awmdm.com)
#
# ------------------------------------------------------------------

VERSION=0.1.0
SUBJECT=some-unique-id
USAGE="Usage: createUploadJson.sh [Base64 Encoded Authentication] [AirWatch Tenant Code] [BinaryFilePath] [Application Name] [File Name] [Application ID in AirWatch] [Versioning String] [iPhone/iPod Touch enabled {1:0}] [iPad enabled {1:0}] [AirWatch URL]"

# --- Options processing -------------------------------------------
if [ $# == 0 ] ; then
echo $USAGE
exit 1;
fi

# ------------------------------------------------------------------
# Create all the temporary files (with traps to release them if they crash)
# ------------------------------------------------------------------

# The binary in base64 format
base64Binary=$(mktemp /tmp/airwatchBase64.XXXXXXXX)
trap 'rm -f $base64Binary' INT TERM HUP EXIT

# The JSON used for the upload request
uploadJson=$(mktemp /tmp/uploadJson.XXXXXXXX)
trap 'rm -f $uploadJson' INT TERM HUP EXIT

# The result of the upload request
uploadResult=$(mktemp /tmp/uploadResult.XXXXXXXX)
trap 'rm -f $uploadResult' INT TERM HUP EXIT

# The JSON used for the begin install request
beginInstallJson=$(mktemp /tmp/beginInstallJson.XXXXXXXX)
trap 'rm -f $beginInstallJson' INT TERM HUP EXIT

# The result of the begin install request
installResult=$(mktemp /tmp/installResult.XXXXXXXX)
trap 'rm -f $installResult' INT TERM HUP EXIT

airwatchUrl="${10}"

# ------------------------------------------------------------------
# Put the BASE64 version of the app binary into a file
# ------------------------------------------------------------------
openssl base64 -in $3 -out ${base64Binary}

# ------------------------------------------------------------------
# Form the Upload Request's JSON
# ------------------------------------------------------------------

# Put the base64 data in the ChunkData json value
echo -n "{ \"ChunkData\": \"" > ${uploadJson}
cat ${base64Binary} >> ${uploadJson}

# Use a ChunkSequenceNumber of 1 to indicate this is the first upload chunk (and in this case, only upload chunk)
echo -n "\",\"ChunkSequenceNumber\": 1,\"TotalApplicationSize\":" >> ${uploadJson}

# Get the total size of the app binary, and use for both TotalApplicationSize and ChunkSize since we upload it all at once
cat ${base64Binary} | wc -c >> ${uploadJson}
echo -n ",\"ChunkSize\": " >> ${uploadJson}
cat ${base64Binary} | wc -c >> ${uploadJson}
echo -n "}" >> ${uploadJson}

# Make the POST Request to upload the binary to AirWatch. This will only put the artifact in airwatch, and not make it visible to any users
curl -vX POST -H "Authorization: Basic $1" -H "aw-tenant-code: $2" "${airwatchUrl}/api/mam/apps/internal/uploadchunk" -d @${uploadJson} --header "Content-Type: application/json" > ${uploadResult}

# Verify the upload succeeded
grep -q "\"UploadSuccess\":true" ${uploadResult} &> /dev/null
if [ $? != 0 ]; then
    >&2 echo "Retrying upload..."
    sleep 5

    # Make the POST Request to upload the binary to AirWatch. This will only put the artifact in airwatch, and not make it visible to any users
    curl -vX POST -H "Authorization: Basic $1" -H "aw-tenant-code: $2" "${airwatchUrl}/api/mam/apps/internal/uploadchunk" -d @${uploadJson} --header "Content-Type: application/json" > ${uploadResult}

    grep -q "\"UploadSuccess\":true" ${uploadResult} &> /dev/null
    if [ $? != 0 ]; then
        >&2 echo "Error uploading app binary"
        exit 1
    fi
fi

>&2 echo "Successfully uploaded binary"
# Add variable groups, error handling, version numbers (and put version number in the app)

# Use the TransactionId from the upload request to associate the install with that uploaded binary
echo -n "{\"TransactionId\": \"" > ${beginInstallJson}
cat ${uploadResult} | grep -o '"TranscationId":"[a-zA-Z0-9-]*' | awk '{print substr($0,18,length())}' >> ${beginInstallJson}

# Set the device types, file name,
echo -n "\",\"DeviceType\": \"2\",\"ApplicationName\": \"$4\",\"SupportedModels\": {\"Model\": [" >> ${beginInstallJson}

# Model 1 is iPhone, 3 is iPod Touch
if [ "$8" = "1" ]; then
echo -n "{\"ApplicationId\": $6,\"ModelId\": 1},{\"ApplicationId\": $6,\"ModelId\": 3}" >> ${beginInstallJson}
fi

# Model 2 is iPad
if [ "$9" = "1" ]; then
echo -n ",{\"ApplicationId\": $6,\"ModelId\": 2}" >> ${beginInstallJson}
fi

# Set push mode (auto)
echo -n "]},\"PushMode\": \"Auto\",\"AutoUpdateVersion\": true,\"FileName\": \"$5\",\"AppVersion\": \"" >> ${beginInstallJson}

# Add the app version
echo -n $7 | awk '{printf substr($0,3,4); printf "."; printf substr($0,7,7)}' >> ${beginInstallJson}

echo -n \"\} >> ${beginInstallJson}
cat ${beginInstallJson}

# ------------------------------------------------------------------
# Form the Install request's JSON
# ------------------------------------------------------------------
curl -vX POST -H "Authorization: Basic $1" -H "aw-tenant-code: $2" "${airwatchUrl}/api/mam/apps/internal/begininstall" -d @${beginInstallJson}  --header "Content-Type: application/json" > ${installResult}

# Verify the upload succeeded
grep -q "ApplicationName" ${installResult} &> /dev/null
if [ $? != 0 ]; then
    sleep 5

    curl -vX POST -H "Authorization: Basic $1" -H "aw-tenant-code: $2" "${airwatchUrl}/api/mam/apps/internal/begininstall" -d @${beginInstallJson}  --header "Content-Type: application/json" > ${installResult}

    grep -q "ApplicationName" ${installResult} &> /dev/null
    if [ $? != 0 ]; then
        >&2 echo "Error creating install for app binary"
        exit 1
    fi
fi


>&2 echo "Successfully sent install request"
