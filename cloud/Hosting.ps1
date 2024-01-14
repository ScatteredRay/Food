$ErrorActionPreference = "Stop"
Import-Module -Force (Join-Path $PSScriptRoot 'CFN.psm1')
Import-Module -Force (Join-Path $PSScriptRoot 'CloudFront.psm1')
Import-Module -Force (Join-Path $PSScriptRoot 'CloudUtil.psm1')

$Credential = Get-AWSCredential -ProfileName $env:AWS_PROFILE
$Region = $env:AWS_REGION

$StackName = "DocsSiteCFNStack"
$Domain = "docssite.nd.gl"
$DocsBucket = "docssite-document-bucket"

$AcmArn = Get-ACMCertificate -ProfileName $env:AWS_PROFILE -Domain $Domain

$AWSTemplate = @{
    AWSTemplateFormatVersion = "2010-09-09"
    Description = ""
    Parameters = @{
    }
    Resources = @{
        UploadBucket = @{
            Type = "AWS::S3::Bucket"
            Properties = @{
                BucketName = $DocsBucket
            }
        }
        WebBucket = @{
            Type = "AWS::S3::Bucket"
            Properties = @{
                BucketName = $Domain
            }
        }
        HostedZone = @{
            Type = "AWS::Route53::HostedZone"
            Properties = @{
                Name = $Domain
            }
        }
        WebUser = @{
            Type = "AWS::IAM::User"
            Properties = @{
                UserName = "WebBucketAccessUser"
                Policies = @(
                    @{
                        PolicyName = "WebBucketPolicy"
                        PolicyDocument = @{
                            Version = "2012-10-17"
                            Statement = @{
                                Effect = "Allow"
                                Action = @(
                                    "s3:DeleteObject",
                                    "s3:GetBucketLocation",
                                    "s3:GetObject",
                                    "s3:ListBucket",
                                    "s3:PutObject"
                                )
                                Resource = @(
                                    @{"Fn::GetAtt" = @( "WebBucket", "Arn" ) }
                                    @{"Fn::Join" = @( "/", @( @{"Fn::GetAtt" = @( "WebBucket", "Arn" ) }, "*" ) ) }
                                )
                            }
                        }
                    }
                )
            }
        }
    }
    Outputs = @{
    }
}

$CFDist = New-CloudFrontDist -BucketRef "WebBucket" -Domain $Domain -DomainZoneId (Get-CFNRef "HostedZone") -AcmArn $AcmArn -AccessLogging

$AWSTemplate = Merge-AWSTemplates $AWSTemplate $CFDist

Invoke-CFNUpdate -AWSTemplate $AWSTemplate -StackName $StackName -AWSProfile $env:AWS_PROFILE -AWSRegion $Region -IAMCapability

