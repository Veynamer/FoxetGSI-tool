#!/bin/bash

# Project OEM-GSI Porter by Erfan Abdi <erfangplus@gmail.com>

PROJECT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
TOOLS_DIR="$PROJECT_DIR/tools"
PARTITIONS="system vendor cust odm oem factory product xrom systemex system_ext reserve india"

AB=true
AONLY=true
MOUNTED=false
CLEAN=false

usage()
{
    echo "Usage: [--help|-h|-?] [--ab|-b] [--aonly|-a] [--mounted|-m] [--cleanup|-c] $0 <Firmware link> <Firmware type> [Other args]"
    echo -e "\tFirmware link: Firmware download link or local path"
    echo -e "\tFirmware type: Firmware mode"
    echo -e "\t--ab: Build only AB"
    echo -e "\t--aonly: Build only A-Only"
    echo -e "\t--cleanup: Cleanup downloaded firmware"
    echo -e "\t--help: To show this info"
}

POSITIONAL=()
while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    --ab|-b)
    AONLY=false
    AB=true
    shift
    ;;
    --aonly|-a)
    AONLY=true
    AB=false
    shift
    ;;
    --cleanup|-c)
    CLEAN=true
    shift
    ;;
    --help|-h|-?)
    usage
    exit
    ;;
    *)
    POSITIONAL+=("$1")
    shift
    ;;
esac
done
set -- "${POSITIONAL[@]}" # restore positional parameters

if [[ ! -n $2 ]]; then
    echo "ERROR: Enter all needed parameters"
    usage
    exit
fi

URL=$1
shift
SRCTYPE=$1
shift

ORIGINAL_URL=$URL

if [[ $SRCTYPE == *":"* ]]; then
    SRCTYPENAME=`echo "$SRCTYPE" | cut -d ":" -f 2`
else
    SRCTYPENAME=$SRCTYPE
fi

DOWNLOAD()
{
    URL="$1"
    ZIP_NAME="$2"
    echo "Downloading firmware to: $ZIP_NAME"
    aria2c -x16 -j$(nproc) -U "Mozilla/5.0" -d "$PROJECT_DIR/input" -o "$ACTUAL_ZIP_NAME" ${URL} || wget -U "Mozilla/5.0" ${URL} -O "$ZIP_NAME"
}

MOUNT()
{
    for p in $PARTITIONS; do
        if [[ -e "$1/$p.img" ]]; then
            mkdir -p "$1/$p"
            printf "$p " >> "$1/mounted.txt"
            if [ $(uname) == Linux ]; then
                sudo mount -o ro "$1/$p.img" "$1/$p"
            elif [ $(uname) == Darwin ]; then
                fuse-ext2 "$1/$p.img" "$1/$p"
            fi
        fi
    done
}

UMOUNT()
{
    for p in $PARTITIONS; do
        if [[ -e "$1/$p.img" ]]; then
            sudo umount "$1/$p"
        fi
    done
}

LEAVE()
{
    UMOUNT "$PROJECT_DIR/working"
    rm -rf "$PROJECT_DIR/working"
    exit 1
}

echo "Updating tools..."
"$PROJECT_DIR"/update.sh

# Create input & working directory if it does not exist
mkdir -p "$PROJECT_DIR/input" "$PROJECT_DIR/working" "$PROJECT_DIR/output"

if [[ -d "$URL" ]]; then
    MOUNTED=true
fi

ZIP_NAME="$PROJECT_DIR/input/dummy"
if [ $MOUNTED == false ]; then
    if [[ "$URL" == "http"* ]]; then
        # URL detected
        RANDOMM=$(echo $RANDOM)
        EXTENSION=""

        if [[ "$URL" == "https://drive.google.com"* ]]; then
            # Google Drive
            FILE_ID=$(echo "$URL" | sed -E 's/.*\/d\/([0-9A-Za-z_-]{33})\/.*/\1/')
            if [[ -z "$FILE_ID" ]]; then
                echo "Invalid Google Drive URL"
                exit 1
            fi
            FILENAME="$PROJECT_DIR/input/$RANDOMM_FIRMWARE$EXTENSION"
            gdown "$FILE_ID" -O "$FILENAME"
            if [[ $? -ne 0 ]]; then
                echo "Error downloading from Google Drive"
                exit 1
            fi
            URL="$FILENAME"
        elif [[ "$URL" == "https://sourceforge.net"* ]]; then
            # SourceForge
            CONTENT_DISPOSITION=$(curl -s -I -L "$URL" | grep "Content-Disposition:" | sed -E 's/.*filename="([^"]+)".*/\1/')
            if [[ -n "$CONTENT_DISPOSITION" ]]; then
                FILENAME="$PROJECT_DIR/input/$CONTENT_DISPOSITION"
                EXTENSION=".$(echo "$FILENAME" | awk -F '.' '{print $NF}')"
            else
                FILENAME="$PROJECT_DIR/input/$RANDOMM_FIRMWARE$EXTENSION"
            fi
            curl -L -o "$FILENAME" "$URL"
            if [[ $? -ne 0 ]]; then
                echo "Error downloading from SourceForge"
                exit 1
            fi
            URL="$FILENAME"
        else
            # Other URL (HTTP/HTTPS)
            CONTENT_TYPE=$(curl -s -I "$URL" | grep "Content-Type:" | awk '{print $2}')
            if [[ "$CONTENT_TYPE" == "application/zip" ]]; then
                EXTENSION=".zip"
            elif [[ "$CONTENT_TYPE" == "application/x-gzip" || "$CONTENT_TYPE" == "application/gzip" ]]; then
                EXTENSION=".tgz"
            elif [[ "$CONTENT_TYPE" == "application/x-xz" ]]; then
              EXTENSION=".xz"
            elif [[ "$CONTENT_TYPE" == "application/octet-stream" ]]; then
                if [[ "$URL" == *.zip ]]; then
                    EXTENSION=".zip"
                elif [[ "$URL" == *.gz ]]; then
                    EXTENSION=".gz"
                elif [[ "$URL" == *.xz ]]; then
                  EXTENSION=".xz"
                elif [[ "$URL" == *.tgz ]]; then
                    EXTENSION=".tgz"
                else
                    echo "Unable to determine file type from URL, Content-Type: $CONTENT_TYPE"
                fi
            else
                echo "Неизвестный Content-Type: $CONTENT_TYPE"
            fi
            FILENAME="$PROJECT_DIR/input/$RANDOMM_FIRMWARE$EXTENSION"
            wget -L "$URL" -O "$FILENAME"
            if [[ $? -ne 0 ]]; then
              echo "File download error"
              exit 1
            fi
            URL="$FILENAME"
        fi
    fi
    $TOOLS_DIR/Firmware_extractor/extractor.sh "$URL" "$PROJECT_DIR/working" || exit 1
    if [ $CLEAN == true ]; then
        rm -rf "$FILENAME"
    fi
    MOUNT "$PROJECT_DIR/working"
    URL="$PROJECT_DIR/working"
fi

if [ $AB == true ]; then
   "$PROJECT_DIR"/make.sh "${URL}" "${SRCTYPE}" AB "$PROJECT_DIR/output" ${@} || LEAVE
fi

if [ $AONLY == true ]; then
    "$PROJECT_DIR"/make.sh "${URL}" "${SRCTYPE}" Aonly "$PROJECT_DIR/output" ${@} || LEAVE
fi

echo "Porting ${SRCTYPENAME} GSI done on: $PROJECT_DIR/output"

if [[ -f "$PROJECT_DIR/private_utils.sh" ]]; then
    . "$PROJECT_DIR/private_utils.sh"
    UPLOAD "$PROJECT_DIR/output" ${SRCTYPENAME} ${AB} ${AONLY} "${ORIGINAL_URL}"
fi

DEBUG=false
if [ $DEBUG == true ]; then
echo "AONLY = ${AONLY}"
echo "AB = ${AB}"
echo "MOUNTED = ${MOUNTED}"
echo "URL = ${URL}"
echo "SRCTYPE = ${SRCTYPE}"
echo "SRCTYPENAME = ${SRCTYPENAME}"
echo "OTHER = ${@}"
echo "ZIP_NAME = ${ZIP_NAME}"
fi

LEAVE
