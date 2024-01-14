# Copyright (c) 2020, Indy Ray. All rights reserved.
$ErrorActionPreference = "Stop"
Import-Module -Force (Join-Path $PSScriptRoot 'CFN.psm1')

function New-CloudFrontDist {
    param(
        $BucketRef,
        $OriginDomain,
        $OriginHttpPort,
        $Domain,
        $DomainZoneId,
        $AcmArn,
        $ViewerRequestFunction,
        $DefaultRootObject,
        [switch] $AccessLogging
    )

    $BucketPolicy = "PackageBucketPolicy"
    $OAI = "CFOriginAccessIdentity"
    $Dist = "CloudFrontDist"
    $LoggingBucket = "CloudFrontLoggingBucket"
    $LoggingBucketName = "$Domain-accesslogs"
    $RecordSet = "RecordSet"
    $DefaultOrigin = "DefaultCFOrigin"

    if([string]::IsNullOrEmpty($DefaultRootObject)) {
        if($BucketRef) {
            $DefaultRootObject = "index.html"
        }
        else {
            $DefaultRootObject = ""
        }
    }

    $AWSTemplate = New-AWSTemplate -Resources @{
        $Dist = @{
            Type = "AWS::CloudFront::Distribution"
            Properties = @{
                DistributionConfig = @{
                    Aliases = @(
                        $Domain
                    )
                    ViewerCertificate = @{
                        AcmCertificateArn = $AcmArn
                        SslSupportMethod = "sni-only"
                    }
                    Enabled = $True
                    DefaultRootObject = $DefaultRootObject
                    DefaultCacheBehavior = @{
                        AllowedMethods = @( "GET", "HEAD", "OPTIONS" )
                        CachedMethods = @( "GET", "HEAD", "OPTIONS" )
                        ForwardedValues = @{
                            Cookies = @{
                                Forward = "all"
                            }
                            Headers = @( "Origin", "Access-Control-Request-Headers", "Access-Control-Request-Method", "x-forwarded-host", "authorization" )
                            QueryString = $True
                        }
                        TargetOriginId = $Null
                        ViewerProtocolPolicy = "redirect-to-https"
                        MinTTL = 0
                        MaxTTL = 0
                        #DefaultTTL = 1
                        DefaultTTL = 0
                    }
                }
            }
        }
        $RecordSet = @{
            Type = "AWS::Route53::RecordSet"
            Properties = @{
                Name = "$Domain."
                HostedZoneId = $DomainZoneId
                Type = "A"
                AliasTarget = @{
                    DNSName = @{ "Fn::GetAtt" = @( $Dist, "DomainName" ) }
                    HostedZoneId = "Z2FDTNDATAQYW2"
                }
            }
        }
    }

    if($BucketRef) {
        $AWSTemplate.Resources.$OAI = @{
            Type = "AWS::CloudFront::CloudFrontOriginAccessIdentity"
            Properties = @{
                CloudFrontOriginAccessIdentityConfig = @{
                    Comment = "CFN Origin Access"
                }
            }
        }

        $AWSTemplate.Resources.$BucketPolicy = @{
            Type = "AWS::S3::BucketPolicy"
            Properties = @{
                Bucket = @{ Ref = $BucketRef }
                PolicyDocument = @{
                    Version = "2012-10-17"
                    Statement = @{
                        Effect = "Allow"
                        Action = "s3:GetObject"
                        Resource = @(
                            @{ "Fn::Join" = @("", @( @{ "Fn::GetAtt" = @( $BucketRef, "Arn" ) }, "/*" ) ) }
                        )
                        Principal = @{
                            CanonicalUser = @{ "Fn::GetAtt" = @( $OAI, "S3CanonicalUserId" ) }
                        }
                    }
                }
            }
        }

        $AWSTemplate.Resources.$Dist.Properties.DistributionConfig.Origins = @()
        $AWSTemplate.Resources.$Dist.Properties.DistributionConfig.Origins += @{
            DomainName = @{ "Fn::GetAtt" = @( $BucketRef, "RegionalDomainName" ) }
            Id = "BucketOrigin"
            S3OriginConfig = @{
                OriginAccessIdentity = @{ "Fn::Join" = @( "/", @( "origin-access-identity", "cloudfront", @{ Ref = $OAI } ) ) }
            }
        }

        $AWSTemplate.Resources.$Dist.Properties.DistributionConfig.DefaultCacheBehavior.TargetOriginId = "BucketOrigin"
    }

    if($OriginDomain) {
        $Origin = @{
            DomainName = $OriginDomain
            Id = "DomainOrigin"
            CustomOriginConfig = @{
                OriginProtocolPolicy = "https-only"
            }
        }
        $AWSTemplate.Resources.$Dist.Properties.DistributionConfig.Origins = @()
        $AWSTemplate.Resources.$Dist.Properties.DistributionConfig.Origins += $Origin
        $AWSTemplate.Resources.$Dist.Properties.DistributionConfig.DefaultCacheBehavior.TargetOriginId = "DomainOrigin"

        if($OriginHttpPort) {
            $Origin.CustomOriginConfig.OriginProtocolPolicy = "http-only"
            $Origin.CustomOriginConfig.HttpPort = $OriginHttpPort
        }
    }

    if($ViewerRequestFunction) {
        $DefaultCacheBehavior = $AWSTemplate.Resources.$Dist.Properties.DistributionConfig.DefaultCacheBehavior
        $DefaultCacheBehavior.LambdaFunctionAssociations = @(
            @{
                EventType = "viewer-request"
                LambdaFunctionARN = $ViewerRequestFunction
            }
        )
    }

    if($AccessLogging) {
        # I guess we just need permissions to this bucket from the whole account?
        $AWSTemplate.Resources.$LoggingBucket = @{
            Type = "AWS::S3::Bucket"
            Properties = @{
                BucketName = $LoggingBucketName
                OwnershipControls = @{
                    Rules = @(
                        @{
                            ObjectOwnership = "BucketOwnerPreferred"
                        }
                    )
                }
            }
        }

        $AWSTemplate.Resources.$Dist.Properties.DistributionConfig.Logging = @{
            Bucket = (Get-CFNAtt $LoggingBucket DomainName)
            IncludeCookies = $True
            Prefix = "$Domain/"
        }
    }

    return $AWSTemplate
}


function New-LambdaBucket {
    Param(
        $BucketRef,
        $BucketName
    )

    $Bucket = New-AWSTemplate -Resources @{
        $BucketRef = @{
            Type = "AWS::S3::Bucket"
            Properties = @{
                BucketName = $BucketName
                PublicAccessBlockConfiguration = @{
                    BlockPublicAcls = $True
                    BlockPublicPolicy = $True
                    IgnorePublicAcls = $True
                    RestrictPublicBuckets = $True
                }
            }
        }
    }

    return $Bucket
}

function New-Lambda {
    Param(
        $BucketName,
        $RefPrefix,
        $FunctionVersionOutputRef,
        $ZipPath,
        $FunctionPolicy,
        $VPCSubnet,
        $SecurityGroup,
        [switch] $CreateUrl,
        $Timeout = 60
    )

    $ZipName = (Get-Item $ZipPath).Name

    $FunctionRef = "${RefPrefix}Function$(get-date -f "yyyyMMddHHmmss")"
    # We seem to need to change the version to get an update
    $FunctionVersionRef = "${RefPrefix}FunctionVersion$(get-date -f "yyyyMMddHHmmss")"
    $FunctionRoleRef = "${RefPrefix}FunctionRole"
    $FunctionInvokePermissionRef = "${RefPrefix}FunctionInvokePermission"
    #$FunctionLogGroupRef = "${RefPrefix}LogGroup"
    $FunctionUrlRef = "${RefPrefix}FunctionUrl"
    $FunctionUrlOutputRef = "${RefPrefix}FunctionUrl"

    $Template = New-AWSTemplate -Resources @{
        $FunctionRef = @{
            Type = "AWS::Lambda::Function"
            Properties = @{
                Code = @{
                    S3Bucket = $BucketName
                    S3Key = $ZipName
                }
                Role = @{ "Fn::GetAtt" = @($FunctionRoleRef, "Arn") }
                Runtime = "nodejs14.x"
                Handler = "index.handler"
                VpcConfig = @{}
                Timeout = $Timeout
            }
        }
        $FunctionVersionRef = @{
            Type = "AWS::Lambda::Version"
            Properties = @{
                FunctionName = @{ "Ref" = $FunctionRef }
            }
        }
        #$FunctionLogGroupRef = @{
        #    Type = "AWS::Logs::LogGroup"
        #    DependsOn = $FunctionRef
        #    Properties = @{
        #        LogGroupName = @{ "Fn::Join" = @("", @("/aws/lambda", @{"Ref" = $FunctionRef})) }
        #        RetentionInDays = 30
        #    }
        #}
        $FunctionRoleRef = @{
            Type = "AWS::IAM::Role"
            Properties = @{
                AssumeRolePolicyDocument = @{
                    Version = "2012-10-17"
                    Statement = @{
                        Sid = "AllowLambdaServiceToAssumeRole"
                        Effect = "Allow"
                        Action = "sts:AssumeRole"
                        Principal = @{
                            Service = @(
                                "lambda.amazonaws.com",
                                "edgelambda.amazonaws.com" # TODO: Could remove this on regular lambdas
                            )
                        }
                    }
                }
                Policies = @(
                    @{
                        PolicyName = "${RefPrefix}FunctionPolicy"
                        PolicyDocument = @{
                            Version = "2012-10-17"
                            Statement = @(
                                @{
                                    Effect = "Allow"
                                    Action = "logs:CreateLogGroup"
                                    Resource = "arn:aws:logs:*:*:*"
                                },
                                @{
                                    Effect = "Allow"
                                    Action = @(
                                        "logs:CreateLogGroup",
                                        "logs:CreateLogStream",
                                        "logs:PutLogEvents"
                                    )
                                    Resource = @(
                                        "arn:aws:logs:*:*:*"
                                    )
                                }
                            )
                        }
                    }
                )
            }
        }
    }  -Outputs @{
        $FunctionVersionOutputRef = @{
            Description = "Lambda Version ARN"
            Value = @{ "Ref" = $FunctionVersionRef }
        }
    }

    if($VPCSubnet) {
        $Template.Resources.$FunctionRef.Properties.VpcConfig.SubnetIds = @($VPCSubnet)
    }

    if($SecurityGroup) {
        $Template.Resources.$FunctionRef.Properties.VpcConfig.SecurityGroupIds = @($SecurityGroup)
    }

    if($VPCSubnet -or $SecurityGroup) {
        $Template.Resources.$FunctionRoleRef.Properties.Policies[0].PolicyDocument.Statement += @{
            Effect = "Allow"
            Action = @(
                "ec2:CreateNetworkInterface",
                "ec2:DescribeNetworkInterfaces",
                "ec2:DeleteNetworkInterface",
                "ec2:AssignPrivateIpAddresses",
                "ec2:UnassignPrivateIpAddresses"
            )
            Resource = "*"
        }
    }

    if($CreateUrl) {
        $Template.Resources.$FunctionUrlRef = @{
            Type = "AWS::Lambda::Url"
            Properties = @{
                AuthType = "NONE"
                TargetFunctionArn = @{ "Fn::GetAtt" = @( $FunctionRef, "Arn" ) }
            }
        }

        # For AuthType None we need to give permissions.
        $Template.Resources.$FunctionInvokePermissionRef = @{
            Type = "AWS::Lambda::Permission"
            Properties = @{
                Action = "lambda:InvokeFunctionUrl"
                FunctionName = @{ "Fn::GetAtt" = @( $FunctionRef, "Arn" ) }
                FunctionUrlAuthType = "NONE"
                Principal = "*"
            }
        }

        $Template.Outputs.$FunctionUrlOutputRef = @{
            Description = "Lambda invocation url."
            Value = @{ "Fn::GetAtt" = @( $FunctionUrlRef, "FunctionUrl" ) }
        }
    }

    if($FunctionPolicy) {
        $Template.Resources.$FunctionRoleRef.Properties.Policies[0].PolicyDocument.Statement += $FunctionPolicy
    }

    return $Template
}

function New-LambdaEdge {
    Param(
        $BucketName,
        $RefPrefix,
        $FunctionVersionOutputRef,
        $ZipPath,
        $FunctionPolicy
    )
    return New-Lambda -BucketName $BucketName -RefPrefix $RefPrefix -FunctionVersionOutputRef $FunctionVersionOutputRef -ZipPath $ZipPath -FunctionPolicy $FunctionPolicy -Timeout 5
}

function Invoke-LambdaUpdate {
    Param(
        $StackName,
        $BucketName,
        $BucketTemplate,
        $LambdaTemplate,
        $ZipPath,
        $Credential,
        $AWSProfile,
        $AWSRegion
    )

    if(!(Test-S3Bucket -BucketName $BucketName -Credential $Credential)) {
        # If the bucket is missing (Stack not run?) We need to create it so we can upload before we try to create the lambda
        Write-Host "Bucket $BucketName missing. Bootstrapping CFN template."
        [void](Invoke-CFNUpdate -AWSTemplate $BucketTemplate -StackName $StackName -AWSProfile $AWSProfile -AWSRegion $AWSRegion)
    }

    $AWSTemplate = Merge-AWSTemplates $BucketTemplate $LambdaTemplate

    $ZipName = (Get-Item $ZipPath).Name

    Write-Host "Uploading Lambda Function."
    [void](Write-S3Object -File $ZipPath -BucketName $Bucketname -Key $ZipName -Region $AWSRegion -Credential $Credential)

    $Outputs = Get-CFNUpdateOutputs (Invoke-CFNUpdate -AWSTemplate $AWSTemplate -StackName $StackName -AWSProfile $env:AWS_PROFILE -AWSRegion $AWSRegion -IAMCapability)

    return $Outputs
}

function Invoke-LambdaEdgeUpdate {
    Param(
        $StackName,
        $BucketName,
        $BucketTemplate,
        $LambdaTemplate,
        $ZipPath,
        $Credential,
        $AWSProfile
    )
    return Invoke-LambdaUpdate -StackName $StackName -BucketName $BucketName -BucketTemplate $BucketTemplate -LambdaTemplate $LambdaTemplate -ZipPath $ZipPath -Credential $Credential -AWSProfile $AWSProfile -AWSRegion "us-east-1"
}

function Invoke-NpmLambdaBuild {
    Param(
        $LambdaDir,
        $Prefix
    )

    $ZipName = "${Prefix}_$(get-date -f "yyyy-MM-dd_HH-mm-ss").zip"

    Write-Host "Building Auth Function."

    [void](Push-Location $LambdaDir)

    [void](npm install)
    Assert-LastExitCode
    [void](npm run build)
    Assert-LastExitCode

    $BuildDir = Join-Path $LambdaDir "build"
    $ZipPath = Join-Path $BuildDir $ZipName
    [void](Compress-Archive -Path (Join-Path $BuildDir "index.js") -DestinationPath $ZipPath)

    [void](Pop-Location)

    return $ZipPath
}