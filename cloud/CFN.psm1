# Copyright (c) 2020, Indy Ray. All rights reserved.
$ErrorActionPreference = "Stop"
Import-Module -Force (Join-Path $PSScriptRoot "Util.psm1")

function Get-CFNRef {
    Param(
        [Parameter(Mandatory=$True)]
        [ValidateNotNullOrEmpty()]
        $Key
    )
    return @{ Ref = $Key }
}

function Get-CFNAtt {
    Param(
        [Parameter(Mandatory=$True)]
        [ValidateNotNullOrEmpty()]
        $Key,
        [Parameter(Mandatory=$True)]
        [ValidateNotNullOrEmpty()]
        $Attribute
    )
    return @{ "Fn::GetAtt" = @( $Key, $Attribute )}
}

function Get-CFNRefOrId {
    Param(
        [Parameter(Mandatory=$True)]
        [ValidateNotNullOrEmpty()]
        $Key,
        [Parameter(Mandatory=$True)]
        [ValidateNotNullOrEmpty()]
        $IdPrefix
    )
    if($Key.GetType() -ne [string] -or $Key.StartsWith("$IdPrefix-")) {
        return $Key
    }
    else {
        return Get-CFNRef -Key $Key
    }
}

function New-AWSTemplate {
    param(
        $Resources = @{},
        $Description = "",
        $Parameters = @{},
        $Outputs = @{}
    )

    $AWSTemplate = @{
        AWSTemplateFormatVersion = "2010-09-09"
        Description = $Description
        Parameters = $Parameters
        Resources = $Resources
        Outputs = $Outputs
    }
    return $AWSTemplate
}

function Merge-AWSTemplates {
    $Templates = ($Input + $Args)
    $ResourceList = ($Templates | % { $_.Resources })
    $Resources = Merge-HashTables @ResourceList
    $ParameterList = ($Templates | % { $_.Parameters })
    $Parameters = Merge-HashTables @ParameterList
    $OutputList = ($Templates | % { $_.Outputs })
    $Outputs = Merge-HashTables @OutputList
    return New-AWSTemplate -Description "" -Resources $Resources -Parameters $Parameters -Outputs $Outputs
}

Function Invoke-CFNUpdate {
    Param(
        $AWSTemplate,
        $StackName,
        $Credential,
        $AWSRegion,
        [switch]$IAMCapability,
        [switch]$UseEnhancedDeploy
    )
    $AWSTemplateJson = $AWSTemplate | ConvertTo-Json -Depth 22
    $CloudBuildRoot = Confirm-Dir (Join-Path $PSScriptRoot "..\Build\CFNTemplates\")
    $AWSTemplateFile = (Join-Path $CloudBuildRoot "$StackName.template")
    Set-Content -Path $AWSTemplateFile -Value $AWSTemplateJson -Force


    # Do not love setting these here, since they don't dissapear nicely, but the aws cli doesn't seem to accept them on the cli.
    # Perhaps spawn a subshell:?
    $env:AWS_ACCESS_KEY_ID = $Credential.GetCredentials().AccessKey
    $env:AWS_SECRET_ACCESS_KEY = $Credential.GetCredentials().SecretKey

    if($UseEnhancedDeploy) {
        # TODO
    }
    else {
        Write-Host (aws cloudformation validate-template --template-body file://$AWSTemplateFile)
        if($LastExitCode -ne 0) {
            throw "CFN Validate Error"
        }
    }

    $DeployArgs = $()
    if($IAMCapability) {
        $DeployArgs = $("--capabilities", "CAPABILITY_IAM", "--capabilities", "CAPABILITY_NAMED_IAM")
    }

    $Success = $False
    if($UseEnhancedDeploy) {
        # aws deploy only seems to support templates up to 51200 bytes, so we need to upload to a bucket
        # and deploy from there for larger templates.
        # We use the bucket deployed in CloudFormationBucket.ps1
        $ConfigFile = (Join-Path $PSScriptRoot '..\config\prod.json')
        $Config = Get-Content $ConfigFile | ConvertFrom-Json
        $CloudFormationTemplateBucket = $Config.CloudFormationTemplateBucket

        # An alternative process we can run:
        # run describe-stacks for "does not exist"
        # create-change-set with -change-set-type CREATE or UPDATE
        # wait change-set-create-complete
        # describe-stacks "The submitted information didn't contain changes"
        # execute-change-set
        # wait change-set-create-complete

        Write-Host (aws --region $AWSRegion cloudformation deploy --no-fail-on-empty-changeset --template-file $AWSTemplateFile --s3-bucket $CloudFormationTemplateBucket --s3-prefix "templates-$StackName/" --stack-name $StackName @DeployArgs)
        $Success = $LastExitCode -eq 0
    }
    else {
        Write-Host (aws  --region $AWSRegion cloudformation deploy --no-fail-on-empty-changeset --template-file $AWSTemplateFile --stack-name $StackName @DeployArgs)
        $Success = $LastExitCode -eq 0
    }

    if(!$Success) {
        Write-Host ((aws --region $AWSRegion cloudformation describe-stack-events --stack-name $StackName | ConvertFrom-Json).StackEvents | Where-Object -Property ResourceStatus -match '_FAILED' | Select -First 1)
        throw "CFN Deploy Error"
    }

    $Desc = aws --region $AWSRegion cloudformation describe-stacks --stack-name $StackName | ConvertFrom-Json

    $Desc.Stacks
}

Function Get-CFNUpdateOutputs {
    Param($Stack)
    $Outputs = $Stack.Outputs | % { if($_ -and $_.OutputKey) { @{ $_.OutputKey = $_.OutputValue } } }
    return $Outputs
}