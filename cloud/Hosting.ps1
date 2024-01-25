$ErrorActionPreference = "Stop"
Import-Module -Name AWSPowerShell.NetCore
Import-Module -Force (Join-Path $PSScriptRoot 'CFN.psm1')
Import-Module -Force (Join-Path $PSScriptRoot 'CloudFront.psm1')
Import-Module -Force (Join-Path $PSScriptRoot 'CloudUtil.psm1')

$Credential, $Region = Get-AWSCredentialAndRegion

$Config = Get-SetupConfig

$StackName = $Config.Hosting.StackName
$Domain = $Config.Hosting.Domain
$DomainBucketName = $Config.Hosting.HostingBucket
$MediaBucketName = $Config.Hosting.MediaBucket
$BucketUserName = $Config.Hosting.BucketUserName

$AcmArn = Get-ACMCertificate -Credential $Credential -Domain $Domain

$AWSTemplate = @{
    AWSTemplateFormatVersion = "2010-09-09"
    Description = ""
    Parameters = @{
    }
    Resources = @{
        MediaBucket = @{
            Type = "AWS::S3::Bucket"
            Properties = @{
                BucketName = $MediaBucketName
            }
        }
        WebBucket = @{
            Type = "AWS::S3::Bucket"
            Properties = @{
                BucketName = $DomainBucketName
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
                UserName = $BucketUserName
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
                                    @{"Fn::GetAtt" = @( "MediaBucket", "Arn" ) }
                                    @{"Fn::Join" = @( "/", @( @{"Fn::GetAtt" = @( "MediaBucket", "Arn" ) }, "*" ) ) }
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

Invoke-CFNUpdate -AWSTemplate $AWSTemplate -StackName $StackName -Credential $Credential -AWSRegion $Region -IAMCapability

