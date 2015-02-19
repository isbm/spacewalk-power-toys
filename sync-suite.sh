#!/bin/bash

TARGET_DIR="spacewalk-testsuite-base"
TARGET_HOST=$TESTSUITE_TARGET_HOST
if [ -z "$TARGET_HOST" ]; then
    TARGET_HOST=$1
fi

if [ -z "$TARGET_HOST" ]; then
    echo "Usage: $0 <test-suite-fqdn>"
    echo "You may also set TESTSUITE_TARGET_HOST environment variable"
    exit 1;
fi

printf "SSH access check:"
if [ -z "$(ssh -oBatchMode=yes root@$TARGET_HOST id 2>/dev/null)" ]; then
    echo -e "\tFailed\n\nInfo: Please deploy SSH public key to the \"$TARGET_HOST\" to continue for root ID."
    exit 1;
fi
echo -e "\tOK"

printf "Verifying target:"
if [ -n "$(ssh root@$TARGET_HOST ls -la $TARGET_DIR 2>/dev/null | grep git | grep -v gitignore)" ]; then
    echo -e "\tFailed\n\nInfo: Please backup \"$TARGET_DIR\" prior sync to continue."
    exit 1;
fi
echo -e "\tOK"

# Pre-create target, regardless exists or not
ssh root@$TARGET_HOST mkdir $TARGET_DIR 2>/dev/null

echo "Sync test suite:"
# This will exclude .git* stuff.
# On a target machine there should
# not be Git-related directories.
for DIR in $(ls); do
    RESULT=$(rsync -azP $DIR root@$TARGET_HOST:/root/$TARGET_DIR/ 1>/dev/null)
    if [ -n "$RESULT" ]; then
	echo -e "\tFAIL:\t$DIR"
	echo "--------------"
	echo $RESULT
	echo "--------------"
    else
	echo -e "\tOK:\t$DIR"
    fi
done

echo "Done"
