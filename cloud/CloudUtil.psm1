Import-Module -Force (Join-Path $PSScriptRoot 'Util.psm1')

Function Get-ConfigPath {
    return Confirm-Dir (Join-Path $PSScriptRoot "..\config\")
}

Function Get-SetupConfigPath {
    $ConfigPath = Get-ConfigPath
    return (Join-Path $ConfigPath "prod.json")
}

Function Get-SetupConfig {
    $Config = Get-Content -Path (Get-SetupConfigPath) -ErrorAction Stop | ConvertFrom-Json
    return $Config
}

Function Confirm-AWSIdentity {
    Param(
        [Parameter(Mandatory=$True)]
        [ValidateNotNullOrEmpty()]
        $Credential,
        [Parameter(Mandatory=$True)]
        [ValidateNotNullOrEmpty()]
        $Region
    )
    $Config = Get-SetupConfig
    if([string]::IsNullOrEmpty($Region)) {
        throw "`$env:AWS_REGION is empty, perhaps aws environment is not set correctly."
    }
    $Account = (Get-STSCallerIdentity -Credential $Credential -Region $Region).Account
    if($Config.AWSAccount -ne $Account) {
        throw "Calling with incorrect AWSIdentity, expecting $($Config.AWSAccount), got $Account."
    }
    if($Config.AWSRegion -ne $Region) {
        throw "Calling with incorrect AWS Region, expecting $($Config.AWSRegion), got $Region."
    }
}

Function Get-AWSCredentialAndRegion {
    if([string]::IsNullOrEmpty($env:AWS_PROFILE)) {
        $Credential = [Amazon.Runtime.BasicAWSCredentials]::new($env:AWS_ACCESS_KEY_ID, $env:AWS_SECRET_ACCESS_KEY)
    }
    else {
        $Credential = Get-AWSCredential -ProfileName $env:AWS_PROFILE
    }

    if(![string]::IsNullOrEmpty($env:AWS_REGION)) {
        $Region = $env:AWS_REGION
    }
    else {
        $Region = $env:AWS_DEFAULT_REGION
    }

    if(!$Credential) {
        Write-Error "No valid AWS Credential"
    }

    if([string]::IsNullOrEmpty($Region)) {
        Write-Error "No valid Region set."
    }

    [void](Confirm-AWSIdentity -Credential $Credential -Region $Region)

    return $Credential, $Region
}

Function Wait-EC2Instance {
    Param(
        [Parameter(Mandatory=$True)]
        [ValidateNotNullOrEmpty()]
        $InstanceId,
        [Parameter(Mandatory=$True)]
        [ValidateNotNullOrEmpty()]
        $Credential,
        [Parameter(Mandatory=$True)]
        [ValidateNotNullOrEmpty()]
        $Region
    )
    while((Get-EC2Instance -InstanceId $InstanceId -Region $Region -Credential $Credential).Instances[0].State.Name -ne 'running') {
        Start-Sleep -s 5
    }
}

Function Wait-EC2InstanceStopped {
    Param(
        [Parameter(Mandatory=$True)]
        [ValidateNotNullOrEmpty()]
        $InstanceId,
        [Parameter(Mandatory=$True)]
        [ValidateNotNullOrEmpty()]
        $Credential,
        [Parameter(Mandatory=$True)]
        [ValidateNotNullOrEmpty()]
        $Region
    )
    while((Get-EC2Instance -InstanceId $InstanceId -Region $Region -Credential $Credential).Instances[0].State.Name -ne 'stopped') {
        Start-Sleep -s 5
    }
}

Function Wait-EC2Image {
    Param(
        [Parameter(Mandatory=$True)]
        [ValidateNotNullOrEmpty()]
        $AMIID,
        [Parameter(Mandatory=$True)]
        [ValidateNotNullOrEmpty()]
        $Credential,
        [Parameter(Mandatory=$True)]
        [ValidateNotNullOrEmpty()]
        $Region
    )
    while((Get-EC2Image $AMIID -Credential $Credential -Region $Region).State.Value -ne 'available') {
        Start-Sleep -s 5
    }
}



Function Get-TTGImagesConfig {
    $ConfigPath = Confirm-Dir (Join-Path $PSScriptRoot "..\config\")
    $ImageConfigPath = (Join-Path $ConfigPath "images.json")
    $ImageList = @()

    try {
        $ImageJson = Get-Content -Path $ImageConfigPath -ErrorAction Stop | ConvertFrom-Json
        $ImageList = $ImageJson
    }
    catch {
    }

    return $ImageList
}

Function Add-TTGImageConfig {
    Param(
        [string] $Name,
        [DateTime] $Date,
        [string] $Image
    )

    $ConfigPath = Confirm-Dir (Join-Path $PSScriptRoot "..\config\")
    $ImageConfigPath = (Join-Path $ConfigPath "images.json")

    $ImageList = (Get-TTGImagesConfig).Images

    $ImageInfo = [PSCustomObject]@{
        Name = $Name
        Date = $Date
        Image = $Image
    }

    $ImageList += $ImageInfo

    @{Images = $ImageList} | ConvertTo-Json -Depth 12 | Set-Content -Path $ImageConfigPath -Force
}

Function Get-CloudConfigPath {
    return (Join-Path (Get-ConfigPath) "cloud.json")
}

Function Get-TTGCloudConfig {
    $CloudConfigPath = Get-CloudConfigPath

    $DefaultCloudConfig = [PSCustomObject]@{
        Artifacts = [PSCustomObject]@{
            BucketName = ""
            PublishInstanceProfile = ""
            PublishRole = ""
        }
        Builders = [PSCustomObject]@{
            SecurityGroupId = ""
            SubnetId = ""
            IamInstanceProfile = ""
            KeyPair = ""
        }
        Cluster = [PSCustomObject]@{
            Name = ""
        }
        DevDomain = [PSCustomObject]@{
            ZoneId = ""
            Nameservers = ""
        }
        Images = [PSCustomObject]@{
            WindowsBuilder = [PSCustomObject]@{
                Version = ""
                ImageId = ""
            }
            NixOS = [PSCustomObject]@{
                Version = ""
                ImageId = ""
            }
        }
        Network = [PSCustomObject]@{
            IntDev = [PSCustomObject]@{
                Vpc = ""
                Subnet = ""
                SecurityGroup = ""
            }
            Workstation = [PSCustomObject]@{
                Vpc = ""
                Subnet = ""
                SecurityGroup = ""
            }
            Images = [PSCustomObject]@{
                Vpc = ""
                Subnet = ""
                SecurityGroup = ""
            }
        }
    }

    $CloudConfig = @{}

    try {
        $CloudConfig = Get-Content -Path $CloudConfigPath -ErrorAction Stop | ConvertFrom-Json
    }
    catch {
    }

    Merge-PSObjectDefaults $CloudConfig $DefaultCloudConfig
    Merge-PSObjectDefaults $CloudConfig.Artifacts $DefaultCloudConfig.Artifacts
    Merge-PSObjectDefaults $CloudConfig.Builders $DefaultCloudConfig.Builders
    Merge-PSObjectDefaults $CloudConfig.Cluster $DefaultCloudConfig.Cluster
    Merge-PSObjectDefaults $CloudConfig.DevDomain $DefaultCloudConfig.DevDomain
    Merge-PSObjectDefaults $CloudConfig.Network $DefaultCloudConfig.Network

    return $CloudConfig
}

Function Set-TTGCloudConfig {
    Param(
        $CloudConfig
    )

    $CloudConfigPath = Get-CloudConfigPath
    $CloudConfig | ConvertTo-Json -Depth 12 | Set-Content -Path $CloudConfigPath -Force
}

Function Get-ACMCertificate {
    Param(
        [Parameter(Mandatory=$True)]
        [ValidateNotNullOrEmpty()]
        $Credential,
        [Parameter(Mandatory=$True)]
        [ValidateNotNullOrEmpty()]
        $Domain
    )

    $AcmArn = (Get-ACMCertificateList -Credential $Credential -Region 'us-east-1' | where -Property DomainName -EQ $Domain).CertificateArn | Select-Object -First 1

    if($AcmArn -eq $Null) {
        # Cert has to be in us-east-1 for cloudfront
        $AcmArn = New-ACMCertificate -Credential $Credential -Region 'us-east-1' -DomainName $Domain -ValidationMethod DNS
        Write-Host "Need to manually verify ACM cert for now. https://console.aws.amazon.com/acm/home?region=us-east-1#/"
    }

    Write-Host "AcmArn: $AcmArn"
    return $AcmArn
}

Function Get-CloudKeyPair {
    Param(
        [string] $KeyName,
        [switch] $CreateKeyPair,
        $Credential,
        $Region
    )

    # This is a secret we probally want to persist, how do we do that?
    $PemFile = (Join-Path $PSScriptRoot "..\config\${KeyName}.pem")
    try {
        $KeyPair = Get-EC2KeyPair -KeyName $KeyName -Credential $Credential -Region $Region
    }
    catch {
        if($CreateKeyPair) {
            $KeyPair = New-EC2KeyPair -KeyName $KeyName -Credential $Credential -Region $Region
            Set-Content -Path $PemFile -Value $KeyPair.KeyMaterial -Force
        }
        else {
            Write-Error "Missing ${KeyName}.pem secret, if this is the initalization of the stack you may use -CreateKeyPair to create it. Back it up, it cannot be recovered."
            exit 1
        }
    }
    return $KeyPair
}