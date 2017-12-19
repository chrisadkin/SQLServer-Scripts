function Refresh-TestDbFromProd
{
    param(
          [parameter(mandatory=$true)][string] $Database          
         ,[parameter(mandatory=$true)][string] $SourceSqlInstance 
         ,[parameter(mandatory=$true)][string] $DestSqlInstance   
         ,[parameter(mandatory=$true)][string] $PfaEndpoint       
         ,[parameter(mandatory=$true)][string] $PfaUser           
         ,[parameter(mandatory=$true)][string] $PfaPassword       
    )

    <#
      A simple PowerShell function  to refresh one SQL Server database from another,
      this example assumes that all the database files including the transaction log
      for the source  database reside on the same FlashArray volume and that all the 
      database files including the transaction log for the destination database also
      reside on a single volume.
      
      This function depends on two PowerShell modules:
      
      1. dbatools
      
      This can be downloaded and installed from the PowerShell gallery as follows:
      
      PS> Save-Module -Name dbatools -Path <path>
      
      PS> Install-Module -Name dbatools
      
      2. Pure Storage PowerShell SDK
      
      This is also available via the PowerShell gallery, download and install this
      as follows:
      
      PS> Save-Module -Name PureStoragePowerShellSDK -Path <path>
      
      PS> Install-Module -Name PureStoragePowerShellSDK
      
      Disclaimer
      ~~~~~~~~~~
      
      Anyone wishing to use this script does so at their own risk, testing this script
      using none-rpoduction databases is recommended.
    #>
    
    $FlashArray = New-PfaArray –EndPoint $PfaEndpoint -UserName $PfaUser -Password (ConvertTo-SecureString -AsPlainText $PfaPassword -Force) -IgnoreCertificateError

    $DestDb            = Get-DbaDatabase -sqlinstance $DestSqlInstance  -Database $Database
    $DestDisk          = get-partition -DriveLetter $DestDb.PrimaryFilePath.Split(':')[0]| Get-Disk
    $DestVolume        = Get-PfaVolumes -Array $FlashArray | Where-Object { $_.serial -eq $DestDisk.SerialNumber } | Select name

    $SourceDb          = Get-DbaDatabase -sqlinstance $SourceSqlInstance -Database $Database
    $SourceDisk        = Get-Partition -DriveLetter $SourceDb.PrimaryFilePath.Split(':')[0] | Get-Disk
    $SourceVolume      = Get-PfaVolumes -Array $FlashArray | Where-Object { $_.serial -eq $SourceDisk.SerialNumber } | Select name

    try {
        $DestDb.SetOffline()
    }
    catch {
        $ExceptionMessage = $_.Exception.Message
        Write-Warning "Failed to offline database $Database with: $ExceptionMessage"
        Return
    }

    try {
        Set-Disk -Number $DestDisk.Number -IsOffline $True
    }
    catch {
        $ExceptionMessage = $_.Exception.Message
        Write-Warning "Failed to offline disk with : $ExceptionMessage" 
        Return
    }

    try {
        New-PfaVolume -Array $FlashArray -VolumeName $DestVolume.name -Source $SourceVolume.name -Overwrite
    }
    catch {
        $ExceptionMessage = $_.Exception.Message
        Write-Warning "Failed to refresh test database volume with : $ExceptionMessage" 
        Set-Disk -Number $DestDisk.Number -IsOffline $False
        $DestDb.SetOnline()
        Return
    }

    try {
        Set-Disk -Number $DestDisk.Number -IsOffline $False
    }
    catch {
        $ExceptionMessage = $_.Exception.Message
        Write-Warning "Failed to online disk with : $ExceptionMessage" 
        Return
    }

    try {
        $DestDb.SetOnline()
    }
    catch {
        $ExceptionMessage = $_.Exception.Message
        Write-Warning "Failed to online database $Database with: $ExceptionMessage"
        Return
    }
}
