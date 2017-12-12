#!/bin/bash

#ak=$ADMIN_ACCESS_KEY_ID                     # admin user access key
#sk=$ADMIN_SECRET_ACCESS_KEY                 # admin user secret key
ak=${AWS_ACCESS_KEY_ID:?"has a invalid value"}
sk=${AWS_SECRET_ACCESS_KEY:?"has a invalid value"}

zone0_endpoint=172.16.1.4:7480
zone2_endpoint=oss-bj2.cloudin.cn
zone3_endpoint=oss-bj3.cloudin.cn
aws_endpoint=s3.ap-northeast-1.amazonaws.com

# bucket policy list
bucket_policy_list=(
"{\"Version\": \"2012-10-17\", \"Statement\": [{\"Action\": [\"s3:GetObject\"], \"Principal\": \"*\", \"Resource\": [\"arn:aws:s3:::lyb/*\"], \"Effect\": \"Allow\", \"Sid\": \"AnonymousRead\"}]}"
"{\"Version\": \"2012-10-17\", \"Id\": \"PreventHotLinking\", \"Statement\": [{\"Resource\": [\"arn:aws:s3:::lyb/*\"], \"Effect\": \"Allow\", \"Sid\": \"Allow get requests referred by 192.168.63.233\", \"Action\": [\"s3:GetObject\"], \"Condition\": {\"StringLike\": {\"aws:Referer\": [\"http://192.168.63.23*\"]}}, \"Principal\": \"*\"}, {\"Resource\": \"arn:aws:s3:::lyb/*\", \"Effect\": \"Deny\", \"Sid\": \"Explicit deny to ensure requests are allowed only from specific referer\", \"Action\": \"s3:GetObject\", \"Condition\": {\"StringNotLikeIfExists\": {\"aws:Referer\": [\"http://192.168.63.23*\"]}}, \"Principal\": \"*\"}]}"
"{\"Version\": \"2012-10-17\", \"Id\": \"PreventHotLinking\", \"Statement\": [{\"Resource\": [\"arn:aws:s3:::lyb/*\"], \"Effect\": \"Allow\", \"Sid\": \"Allow get requests referred by 192.168.63.233\", \"Action\": [\"s3:GetObject\"], \"Condition\": {\"StringLike\": {\"aws:Referer\": [\"http://192.168.63.23*\"]}}, \"Principal\": \"*\"}, {\"Resource\": \"arn:aws:s3:::lyb/*\", \"Effect\": \"Deny\", \"Sid\": \"Explicit deny to ensure requests are allowed only from specific referer\", \"Action\": \"s3:GetObject\", \"Condition\": {\"Null\": {\"aws:Referer\": \"true\"}}, \"Principal\": \"*\"}]}"
"{\"Version\": \"2012-10-17\", \"Id\": \"PreventHotLinking\", \"Statement\": [{\"Resource\": [\"arn:aws:s3:::lyb/*\"], \"Effect\": \"Allow\", \"Sid\": \"Allow get requests referred by 192.168.63.233\", \"Action\": [\"s3:GetObject\"], \"Condition\": {\"StringNotLike\": {\"aws:Referer\": [\"http://192.168.63.233*\"]}, \"StringLike\": {\"aws:Referer\": [\"http://192.168.63.23*\"]}}, \"Principal\": \"*\"}, {\"Resource\": \"arn:aws:s3:::lyb/*\", \"Effect\": \"Deny\", \"Sid\": \"Explicit deny to ensure requests are allowed only from specific referer\", \"Action\": \"s3:*\", \"Condition\": {\"StringNotLike\": {\"aws:Referer\": [\"http://192.168.63.23*\"]}}, \"Principal\": \"*\"}]}"
"{\"Version\": \"2012-10-17\", \"Id\": \"SpecificIPv4\", \"Statement\": [{\"Resource\": \"arn:aws:s3:::lyb/*\", \"Effect\": \"Allow\", \"Sid\": \"IPAllow\", \"Action\": \"s3:GetObject\", \"Condition\": {\"NotIpAddress\": {\"aws:SourceIp\": \"10.3.0.101/32\"}, \"IpAddress\": {\"aws:SourceIp\": [\"10.3.0.0/24\", \"172.16.1.5/32\"]}}, \"Principal\": \"*\"}]}"
)

DATE() {
    date -u "+%a, %d %b %Y %H:%M:%S %Z"
}

prepare_parameters() {
    local array=($@)
    local param=""

    for i in ${array[@]}
    do
        if [ -z "$param" ]; then
            param="uid=$i"
        else
            param="$param&$i"
        fi
    done

    echo $param
}

get_user_info() {
    local uri=admin/user
    local date=$(DATE)
    local method=GET content_md5 content_type
    local header="${method}\n${content_md5}\n${content_type}\n${date}\n/${uri}"
    local sig=$(echo -en ${header} | openssl sha1 -hmac ${sk} -binary | base64)
    local query="uid=$1"

    curl -v -H "Date: ${date}" -H "Authorization: AWS ${ak}:${sig}" "http://${endpoint}/${uri}?format=json&${query}" | python -m json.tool
}

get_bucket_info() {
    local uri=admin/bucket
    local date=$(DATE)
    local method=GET content_md5 content_type
    local header="${method}\n${content_md5}\n${content_type}\n${date}\n/${uri}"
    local sig=$(echo -en ${header} | openssl sha1 -hmac ${sk} -binary | base64)
    local query="bucket=$1&stats=True"

    curl -v -H "Date: ${date}" -H "Authorization: AWS ${ak}:${sig}" "http://${endpoint}/${uri}?format=json&${query}" | python -m json.tool
}

get_usage() {
    local uri=admin/usage
    local date=$(DATE)
    local method=GET content_md5 content_type
    local header="${method}\n${content_md5}\n${content_type}\n${date}\n/${uri}"
    local sig=$(echo -en ${header} | openssl sha1 -hmac ${sk} -binary | base64)
    local query=$(prepare_parameters $@)

    curl -v -H "Date: ${date}" -H "Authorization: AWS ${ak}:${sig}" "http://${endpoint}/${uri}?format=json&${query}" | python -m json.tool
}

_bucket_action() {
    local uri=$2/
    local date=$(DATE)
    local method=$1 content_md5 content_type
    local header="${method}\n${content_md5}\n${content_type}\n${date}\n/${uri}"
    local sig=$(echo -en ${header} | openssl sha1 -hmac ${sk} -binary | base64)

    curl -v -H "Date: ${date}" -H "Authorization: AWS ${ak}:${sig}" -X ${method} "http://${endpoint}/${uri}"
}

create_bucket() {
    _bucket_action PUT $1
}

delete_bucket() {
    _bucket_action DELETE $1
    echo
}

_policy_action() {
    local uri=$2?policy
    local content_type=application/xml
    local date=$(DATE)
    local method=$1 content_md5
    local header="${method}\n${content_md5}\n${content_type}\n${date}\n/${uri}"
    local sig=$(echo -en ${header} | openssl sha1 -hmac ${sk} -binary | base64)

    case $1 in
        PUT)
            curl -v -H "Content-Type: ${content_type}" -H "Date: ${date}" -H "Authorization: AWS ${ak}:${sig}" \
                "http://${endpoint}/${uri}" -X ${method} -d "${bucket_policy_list[$3]}"
            ;;
        GET)
            curl -v -H "Content-Type: ${content_type}" -H "Date: ${date}" -H "Authorization: AWS ${ak}:${sig}" \
                "http://${endpoint}/${uri}" | python -m json.tool
            ;;
        DELETE)
            curl -v -H "Content-Type: ${content_type}" -H "Date: ${date}" -H "Authorization: AWS ${ak}:${sig}" \
                "http://${endpoint}/${uri}" -X ${method}
            ;;
    esac
}

put_bucket_policy() {
    _policy_action PUT $1 $2 $3
}

get_bucket_policy() {
    _policy_action GET $1
}

del_bucket_policy() {
    _policy_action DELETE $1
}

put_bucket_acl() {
    local uri=$1/?acl
    local date=$(DATE)
    local method=PUT acl=$2 content_md5 content_type
    local header="${method}\n${content_md5}\n${content_type}\n${date}\nx-amz-acl:${acl}\n/${uri}"
    local sig=$(echo -en ${header} | openssl sha1 -hmac ${sk} -binary | base64)

    curl -v -H "Date: ${date}" -H "X_AMZ_ACL: ${acl}" -H "Authorization: AWS ${ak}:${sig}" -X ${method} "http://${endpoint}/${uri}"
}

get_bucket_acl() {
    local uri=$1/?acl
    local date=$(DATE)
    local method=GET content_md5 content_type
    local header="${method}\n${content_md5}\n${content_type}\n${date}\n/${uri}"
    local sig=$(echo -en ${header} | openssl sha1 -hmac ${sk} -binary | base64)

    curl -v -H "Date: ${date}" -H "Authorization: AWS ${ak}:${sig}" "http://${endpoint}/${uri}"
    echo
}

_tag_action() {
    local uri=$2/$3?tagging
    local content_type=application/xml
    local date=$(DATE)
    local method=$1 content_md5
    local header="${method}\n${content_md5}\n${content_type}\n${date}\n/${uri}"
    local sig=$(echo -en ${header} | openssl sha1 -hmac ${sk} -binary | base64)

    case $1 in
        PUT)
            curl -v -H "Content-Type: ${content_type}" -H "Date: ${date}" -H "Authorization: AWS ${ak}:${sig}" "http://${endpoint}/${uri}" \
                 -X ${method} -d "$4"
            ;;
        GET)
            curl -v -H "Content-Type: ${content_type}" -H "Date: ${date}" -H "Authorization: AWS ${ak}:${sig}" "http://${endpoint}/${uri}"
            echo
            ;;
        DELETE)
            curl -v -H "Content-Type: ${content_type}" -H "Date: ${date}" -H "Authorization: AWS ${ak}:${sig}" "http://${endpoint}/${uri}" -X ${method}
            ;;
    esac
}

put_object_tag() {
    _tag_action PUT $1 $2 $3
}

get_object_tag() {
    _tag_action GET $1 $2
}

del_object_tag() {
    _tag_action DELETE $1 $2
}

get_all_keys() {
    # Equals to bucket.get_all_keys() in boto
    #FIXME Only get MaxKeys keys at most, how to get the next batch?
    local uri=$1/
    local date=$(DATE)
    local method=GET content_md5 content_type
    local header="${method}\n${content_md5}\n${content_type}\n${date}\n/${uri}"
    local sig=$(echo -en ${header} | openssl sha1 -hmac ${sk} -binary | base64)

    curl -v -H "Date: ${date}" -H "Authorization: AWS ${ak}:${sig}" "http://${endpoint}/${uri}?format=json" | python -m json.tool
}

get_object() {
    local uri=$1/$2
    local date=$(DATE)
    local method=GET content_md5 content_type
    local header="${method}\n${content_md5}\n${content_type}\n${date}\n/${uri}"
    local sig=$(echo -en ${header} | openssl sha1 -hmac ${sk} -binary | base64)

    if [ $# -eq 3 ]; then
        curl -v -H "Date: ${date}" -H "Authorization: AWS ${ak}:${sig}" "http://${endpoint}/${uri}" -H "range: bytes=$3"
    else
        curl -v -H "Date: ${date}" -H "Authorization: AWS ${ak}:${sig}" "http://${endpoint}/${uri}"
    fi
}

case $1 in
    0)
        endpoint=$zone0_endpoint
        shift
        ;;
    2)
        endpoint=$zone2_endpoint
        shift
        ;;
    3)
        endpoint=$zone3_endpoint
        shift
        ;;
    aws)
        endpoint=$aws_endpoint
        shift
        ;;
    *)
        printf "Usage:\n\tbash %s <0|2|3|aws> <operator> [<arg>...]\n" "$0"
        printf "Example:\n"
        printf "\tbash %s 0 get_bucket_info <bucket>\n" "$0"
        printf "\tbash %s 0 get_user_info <uid>\n" "$0"
        printf "\tbash %s 0 get_usage <uid> [start=YYYY-mm-dd%%20HH:MM:SS] [end=YYYY-mm-dd%%20HH:MM:SS]\n" "$0" # 不传start和end就是list全部
        printf "\tbash %s 0 get_object <bucket> <object> [<start>-<end>]\n" "$0"
        printf "\tbash %s 0 get_all_keys <bucket>\n" "$0"
        printf "\tbash %s 0 create_bucket <bucket>\n" "$0"
        printf "\tbash %s 0 delete_bucket <bucket>\n" "$0"
        printf "\tbash %s 0 put_bucket_acl <bucket> <private|public-read|public-read-write|authenticated-read>\n" "$0"
        printf "\tbash %s 0 get_bucket_acl <bucket>\n" "$0"
        printf "\tbash %s 0 put_bucket_policy <bucket> <0-4>\n" "$0"
        printf "\tbash %s 0 get_bucket_policy <bucket>\n" "$0"
        printf "\tbash %s 0 del_bucket_policy <bucket>\n" "$0"
        printf "\tbash %s 0 put_object_tag <bucket> <object> <tag>\n" "$0"
        printf "\tbash %s 0 get_object_tag <bucket> <object>\n" "$0"
        printf "\tbash %s 0 del_object_tag <bucket> <object>\n" "$0"
        exit 1
esac

$@