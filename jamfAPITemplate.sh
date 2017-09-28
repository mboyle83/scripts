#!/bin/bash
####################################################################################################
#
#   Purpose: Create functions for JSS API commands to use repeatedly in a bash script
#   Matthew Boyle - mboyle1983@gmail.com
#   Version 0.00 /// Created - 08.02.17
#   Version 0.00 /// Updated - 08.09.17
#   Version 0.00 /// Updated - 08.10.17
#   Version 1.01 /// Updated - 08.21.17 Error checking
#   Version 1.02 /// Updated - 08.29.17 More -debug functionality and opts
#   Version 1.03 /// Updated - 08.29.17 Option Arguments Added
#   Version 1.04 /// Updated - 08.30.17 changes to storage locations
version="1.04"
#
####################################################################################################
#
# HowToUse: Predefined functions and Variables to quickly create a script desinged around the JSS API.
#
# ----------------------  Variables ----------------------
#
# runAsBash: 1 = force the script to run as Bash
# scriptFile: Exracts the name of the script to be used to create files of same name
# csvFile: Default location to save a CSV File To
# logFile: When enabling debug sets a location to write the log file to
# limit: Sets the amount of background proccesses that the script is allowed to have open
# cloudServer: if the URL contains jamfcloud.com cloudServer variable is true
#
# ---------------------- Functions ----------------------
#
# getJSSInfo |||||||||||||||||||||||||||||| Error checks JSS API and User information
# getXML "APIEndPoint" |||||||||||||||||||| Returns raw unformated XML
# getJSON "APIEndPoint" ||||||||||||||||||| Returns raw unformated JSON
# getCode "APIEndPoint" ||||||||||||||||||| Returns HTTP Response Code
# postXML "APIEndPoint" "XMLData" ||||||||| creates an xml file in /tmp then uploads to the JSS
# uploadFile "APIEndPoint" "FileLocation" | if file is hosted will download to tmp then upload
# difuseFork |||||||||||||||||||||||||||||| Helps manage the amount of BG Processes
#
####################################################################################################
batchSize=1
runAsBash=1
#Script Dialogues
infoDia="
      -- ${0##*/} v.${version} --
        This is just a template.
      "
helpDia="
      This script was written on and for MacOS using bash.
      Bash will be used if ran as shell.
      Considerations have been made for JamfPro Cloud Servers and the script may run slower.
          -h : [Help] Displays this Dialog
          -d : this flag will hide all output and push it into ${logFile}
          -l n : [Limit N]setting this will raise or lower the background process limit. Default 10
          -i : [Information] will display additional information about the script.
          -v : [Version] Displays Script version
      "
userAs=$(echo $LOGNAME)
scriptFile=$(echo ${0##*/} | sed 's/.sh//g')
scriptDir="scriptResults"
if [ "$userAs" == "root" ]
  then
    scriptDataPath="/Users/${userAs}/Desktop/${scriptDir}"
  else
    scriptDataPath="/Users/Shared/${scriptDir}"
  fi
tmpStore="${scriptDataPath}/tmp"
if [ ! -d "$tmpStore" ]
  then
    mkdir -p $tmpStore
  fi
csvFile="${scriptDataPath}/${scriptFile}.csv"
logFile="${scriptDataPath}/${scriptFile}.log"
#1MB default
maxSize=1000000
##Lower the limit if terminal sends a spam message about fork
limit=10
#JSS Script Testing Vars
jssurl=""
jssuser=""
jsspassword=""
###Functions###
shellCheck() {
  shellCheck=$(ps -aef | grep $0 | grep bash)
  if [ -z "$shellCheck" ]
  then
    bash $0 $@
    exit
  fi
}
while getopts ':htdivl:' option; do
    case "$option" in
      [h]) echo "$helpDia"
         exit 0
         ;;
      [t]) skipCheck="1"
        ;;
      [i]) echo "$infoDia" >&2
        exit 0
        ;;
      [l]) while true
             do
               if [ -z $OPTARG ] || [[ $OPTARG =~ [^[:digit:]] ]]
                then
                  limit=10
                  echo "${OPTARG} not a valid Number"
                  read -r -p "Enter Background Process Limit or Skip: [S/#]: " response
                    case "$response" in
                      [sS][kK[iI][pP]|[sS])
                        break
                        ;;
                        *)
                        OPTARG=$response
                        ;;
                      esac
                else
                  limit=$OPTARG
                  break
              fi
          done
        ;;
      [v]) echo "${0##*/} Version ${version}"
          exit 0
          ;;
      [d]) echo "Enabling Debug"
          debug=1
          ;;
      \?) printf "illegal option: -%s\n" "$OPTARG" >&2
          echo "$helpDia" >&2
          exit 1
          ;;
    esac
    echo ""
    echo "   -- Executing ${0##*/} Version ${version} --"
    echo "  --- Background Process Limit = ${limit} ---"
    if [[ $debug -eq 1 ]]
      then
        echo "  --- Debug Enabled ---"
      fi
    echo ""
  done
getJSSInfo () {
  # Prompt the user for information to connect to the JSS with
  if [ "$jssInfo" != "completed" ]
    then
      while true
      do
        if [ "$skipCheck" != "1" ]
        then
          read -p "JSS URL: " jssurl
          read -p "JSS Username: " jssuser
          read -s -p "JSS Password: " jsspassword
          echo ""
        fi
      validJSS=`curl -s -o /dev/null -w "%{http_code}" -k -u $jssuser:$jsspassword $jssurl/JSSResource/activationcode -X GET`
      if [ "$validJSS" = "200" ]
        then
          jssInfo="completed"
          break
        else
          echo "Please Re-Enter JSS information."
          echo "$validJSS"
          let breakPoint=breakPoint+1
          if [ "$breakPoint" -gt "2" ]
            then
              echo "Too many failed attempts, please check JSS Permissions."
              exit 1
          fi
     fi
   done
  fi
  apiUrl="${jssurl}/JSSResource"
}
uploadFile () {
 postURI="$1"
 postData="$2"
 if [[ $postData == *"http"* ]]
  then
    fileName=`echo $postData | sed 's/.*\///g'`
    echo "Retriving file ${postData}"
    curl -sk $postData -o $tmpStore/$fileName
    echo "Uploading ${fileName}"
    uploadData=`curl -s -o /dev/null -w "%{http_code}" -k -u ${jssuser}:${jsspassword} ${apiUrl}/$postURI -F name=@$tmpStore/$fileName`
    rm -rf $tmpStore/$fileName
  else
    echo "Uploading ${postData}"
    uploadData=`curl -s -o /dev/null -w "%{http_code}" -k -u ${jssuser}:${jsspassword} ${apiUrl}/$postURI -F name=@$postData`
 fi
 if [ "$uploadData" != "201" ]
  then
   echo "Error Uploading ${uploadData}"
  else
   echo "Upload Successfull"
 fi
}
cloudServer=$(echo $jssurl | grep 'jamfcloud')
  if [ -z $cloudServer ]
      then
        cloudServer=0
      else
        cloudServer=1
  fi
getXML () {
 curl -H 'Accept: text/xml' -sku ${jssuser}:${jsspassword} $apiUrl/$1 -X GET
}
getJSON () {
 curl -H 'Accept: application/json' -sku ${jssuser}:${jsspassword} $apiUrl/$1 -X GET
}
getCode () {
 curl -s -o /dev/null -w '%{http_code}' -k -u ${jssuser}:${jsspassword} $apiUrl/$1 -X GET
}
difuseFork () {
  procs=$(ps -aef | grep $0 | grep -v 'grep' | wc -l)
  while [ $procs -gt $limit ]
    do
      sleep 1
      procs=$(ps -aef | grep $0 | grep -v 'grep' | wc -l)
    done
}
postXML () {
  postURI="$1"
  postData="$2"
  echo $postData > $tmpStore/upload.xml
  echo "Creating New ${postURI}"
  postRes=`curl -s -o /dev/null -w '%{http_code}' -H 'Content-Type: text/xml' -T $tmpStore/upload.xml -ku ${jssuser}:${jsspassword} $apiUrl/$postURI/id/0 -X POST`
  if [ "$postRes" == "201" ]
    then
      echo "Success"
      ID=`curl -sku ${jssuser}:${jsspassword} $apiUrl/$postURI | xmllint --format - | grep '<id>' | sed 's/\///g;s/<id>//g' | sort | tail -n 1`
    else
      echo "Error"
  fi
  rm -rf $tmpStore/upload.xml
}
if [ $runAsBash -eq 1 ]
  then
    shellCheck
  fi
getJSSInfo
if [[ $debug -eq 1 ]]
  then
    while true
    do
    echo "Script Debug invoked"
    echo "If Script does not finish"
    echo "Password will be written in clear text"
    read -r -p "Continue? [y/N]: " response
      case "$response" in
        [yY][eE][sS]|[yY])
        echo "Please Wait... "
        break
        ;;
        [nN][oO]|[nN])
        exit 1
        ;;
        *)
        ;;
      esac
    done
    exec 5> $logFile
    #exec > >(tee -i $tmpStore/${0##*/}.log)
    exec >> $logFile 2>&1
    BASH_XTRACEFD="5"
    PS4='$LINENO: '
    set -x
    debug=1
  else
    debug=0
  fi
#Do Work
#
#
#
#
#
#Work Done
if [ $debug -eq 1 ]
  then
    set +x
    exec &>/dev/tty
    perl -pi -e "s/${jsspassword}/PASSWORD/"  $logFile
    echo "Done, please see log file"
    echo $logFile
  fi
exit 0
