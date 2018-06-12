#!/bin/bash

# Goals: logging + performance (execution time & as few disk calls as possible)
# Please change the workDir before running the script
# Tested on MacOS 
# uname -a
# Darwin StefanMac13.local 17.5.0 Darwin Kernel Version 17.5.0: Fri Apr 13 19:32:32 PDT 2018; root:xnu-4570.51.2~1/RELEASE_X86_64 x86_64
# Example run: 
#     sh netcentric.sh -u http://www.netcentric.biz/
#     sh netcentric.sh -u http://www.facebook.com/

# A named pipe (aka fifo) lasts as long as the system is up, beyond the life of the process. 
# It can be deleted if no longer used. 
# # Processes attach to it for IPC.
# I've used 2 named pipes, htmlPage and htmlPageNetworking
# htmlPage stores the html data from the curl 
# htmlPageNetworking stores the stderr of the curl (containing status code also)

# At line 162, the curl sends data to both fifos
# For each fifo there's a background process that uses the stdin from it
# checkString uses htmlPage
# check200 uses htmlPageNetworking

# Look in $workDir/log/script.log to see script runtime info


# Set the working directory
workDir="/Users/macbook/Desktop/AppDev/netcentric"

display_help() {
    echo
    echo "Usage: $0 [option...] {URL}" >&2
    echo
    echo "   -i, --info             Show script info "
    echo "   -u, --url              URL where to look for careers string "
    echo
    echo "For future improvements, send a job offer to Stefan Raducan" 
    exit 0
}

# Validate input params
if [ $# -ne 1 ] && [ $# -ne 2 ]; then

    echo "$(date '+%Y_%m_%d %H:%M:%S') [ERROR]  >>>Wrong number of parameters provided<<<" >> "$workDir/log/script.log" 
    exit 1
elif [ $# -eq 1 ]; then

    if [ "$1" == "--info" ] || [ "$1" == "-i" ]; then

        echo "$(date '+%Y_%m_%d %H:%M:%S') [INFO]  Showing script how-to" >> "$workDir/log/script.log"
        display_help
        exit 0
    else 
        echo "$(date '+%Y_%m_%d %H:%M:%S') [ERROR]  >>>Wrong option provided: $1<<<" >> "$workDir/log/script.log" 
        exit 2
    fi
else 
    if [ "$1" == "--url" ] || [ "$1" == "-u" ]; then 
        url=$2
    else
        echo "$(date '+%Y_%m_%d %H:%M:%S') [ERROR]  >>>Script called with 2 parameters, but wrong option is provided: $1<<<" >> "$workDir/log/script.log" 
        exit 3
    fi
fi

# create directories for fifo and logs
if [ ! -d "$workDir/fifo" ]; then mkdir "$workDir/fifo"; fi
if [ ! -d "$workDir/log" ]; then mkdir "$workDir/log"; fi

# clear data in fifo or create new fifo if it doesn't exist
if [ -p "$workDir/fifo/htmlPage" ]; then
    rm "$workDir/fifo/htmlPage" && mkfifo -m 0666 "$workDir/fifo/htmlPage"
else
    mkfifo -m 0666 "$workDir/fifo/htmlPage"
fi

if [ -p "$workDir/fifo/htmlPageNetworking" ]; then
    rm "$workDir/fifo/htmlPageNetworking" && mkfifo -m 0666 "$workDir/fifo/htmlPageNetworking"
else
    mkfifo -m 0666 "$workDir/fifo/htmlPageNetworking"
fi


# archive the log if it is greater than 100mb or create new file if it doesnt exist
if [ -f "$workDir/log/script.log" ]; then   
    if [ $(wc -c "$workDir/log/script.log" | sed "s# ##g; s#$workDir/log/script.log##g") -gt 100000000 ]; then 
        tar -czvf "script.$(date '+%Y_%m_%d').log.tar.gz" "$workDir/script.log" && cat /dev/null > "$workDir/script.log"
    fi
else 
    # I use install because it allows me to set user permissions and create the file (which touch can't do)
    install -m 0644 /dev/null "$workDir/log/script.log";
fi

# create a log for checksums of html pages containing careers string
if [ ! -f "$workDir/log/acceptedCksum.log" ]; then
    install -m 0644 /dev/null "$workDir/log/acceptedCksum.log";
fi


# cksum is way faster than a cryptographic hash and faster than grep, and the difference increases exponentially with filesize
function checkString() {

    htmlPage=$(cat "$workDir/fifo/htmlPage") #this will free the stdin to the htmlPage pipe 
    newSum=$(echo "$htmlPage" | cksum | sed "s#$workDir/fifo/htmlPage##")  

    #check if newSum is in the list of accepted checksums
    if [ $(grep "$newSum" "$workDir/log/acceptedCksum.log" | wc -l) -gt 0 ]; then

        echo "$(date '+%Y_%m_%d %H:%M:%S') [INFO]  >>>Match found for careers string<<<" >> "$workDir/log/script.log"
        echo "$(date '+%Y_%m_%d %H:%M:%S') [INFO]  >>>Checksum: $newSum found in acceptedCksum.log for current html page!<<<" >> "$workDir/log/script.log"
        exit 100

    #check with grep if the careers string is in the html page and store new checksum
    elif [ $(echo "$htmlPage" | grep careers | wc -l) -gt 0 ]; then

        echo "$(date '+%Y_%m_%d %H:%M:%S') [INFO]  >>>Match found for careers string<<<" >> "$workDir/log/script.log"
        echo "$(date '+%Y_%m_%d %H:%M:%S') [INFO]  >>>Appending new checksum: $newSum to acceptedCksum.log<<<" >> "$workDir/log/script.log"
        echo "$newSum" >> "$workDir/log/acceptedCksum.log"
        exit 101

    else 

        echo "$(date '+%Y_%m_%d %H:%M:%S') [ERROR]  >>>NO match found for careers string in the html page<<<" >> "$workDir/log/script.log"
        exit 102

    fi
}

function check200() {

    networkInfo=$(cat "$workDir/fifo/htmlPageNetworking")  #this will free the stdin to the htmlPageNetworking pipe
    #Depending on the type of logged data, ANSI escape codes (non-printable chars) should also be removed
    statusCode=$(echo "$networkInfo" | grep "< HTTP/1.1" | sed "s/< HTTP\/1.1//" | sed 's/^ //' | sed 's/.\{1\}$//') #get the response status

    #append cURL stderr to persistent memory log; sed cannot call a shell, that's why I use the debugPrefix variable
    debugPrefix="$(date '+%Y_%m_%d %H:%M:%S') [DEBUG]  "
    echo "$networkInfo" | sed -e "s/^/$debugPrefix/" >> "$workDir/log/script.log"
    #append status code to log

    if [ "$statusCode" == "200 OK" ]; then
        echo "$(date '+%Y_%m_%d %H:%M:%S') [INFO]  >>>HTTP status $statusCode received from $url<<<" >> "$workDir/log/script.log"
        exit 200
    else 
        echo "$(date '+%Y_%m_%d %H:%M:%S') [ERROR]  >>>HTTP status $statusCode received from $url<<<" >> "$workDir/log/script.log"
        exit 201
        #because a diffrent http status has been found we could kill -9 $checkStringPID but I won't implement it atm
    fi
}

#Start running the functions as background processes a  nd keep their PIDs 
checkString &
checkStringPID=$!
check200 &
check200PID=$!

echo "$(date '+%Y_%m_%d %H:%M:%S') [INFO]  Looking for careers string in $url" >> "$workDir/log/script.log"
echo "$(date '+%Y_%m_%d %H:%M:%S') [INFO]  Sending cURL request to $url" >> "$workDir/log/script.log"

#curl -vso "$workDir/fifo/htmlPage" "http://www.netcentric.biz/" 2>&1 | bash -c "tee >(sed -e \"s/^/$debugPrefix/\" >> $workDir/log/script.log)"

#redirect html page to one pipe and error output to another one
curl -sv "$url" 1>"$workDir/fifo/htmlPage" 2>"$workDir/fifo/htmlPageNetworking"

#get exit codes of background functions
wait "$check200PID"
check200ExitCode=$?
wait "$checkStringPID"
checkStringExitCode=$?

echo "$(date '+%Y_%m_%d %H:%M:%S') [DEBUG]  check200PID: $check200PID check200ExitCode: $check200ExitCode" >> "$workDir/log/script.log"
echo "$(date '+%Y_%m_%d %H:%M:%S') [DEBUG]  checkStringPID: $checkStringPID check200ExitCode: $checkStringExitCode" >> "$workDir/log/script.log"



