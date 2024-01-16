$ErrorActionPreference = "Stop"
Import-Module -Force (Join-Path $PSScriptRoot 'CloudUtil.psm1')

$Credential, $Region = Get-AWSCredentialAndRegion

#TODO: Move to config
$BucketUserName = "snapecast-WebBucketAccessUser"

$AccessKey = New-IAMAccessKey -Credential $Credential -Region $Region -UserName $BucketUserName

$AccessKeyId = $AccessKey.AccessKeyId
$SecretAccessKey = $AccessKey.SecretAccessKey

# TODO: Upload to github secrets : https://docs.github.com/en/rest/actions/secrets?apiVersion=2022-11-28#create-or-update-a-repository-secret
# /repos/{owner}/{repo}/actions/secrets/{secret_name}
# First need to get a repo key https://docs.github.com/en/rest/actions/secrets?apiVersion=2022-11-28#get-a-repository-public-key then
# encrypt with lib sodium

#AWS_ACCESS_KEY_ID
#AWS_SECRET_ACCESS_KEY

$AccessKey

