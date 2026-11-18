<#
.SYNOPSIS
	Lists all storage volumes including labels and sizes.
#>
Get-CimInstance -ClassName Win32_LogicalDisk |
    Sort-Object -Property DeviceID |
    Select-Object `
        DeviceID,
        VolumeName,
        DriveType,
        FileSystem,
        @{
            Name       = 'SizeGB'
            Expression = {
                if ($null -ne $_.Size) {
                    [math]::Round($_.Size / 1GB, 2)
                }
            }
        },
        @{
            Name       = 'FreeGB'
            Expression = {
                if ($null -ne $_.FreeSpace) {
                    [math]::Round($_.FreeSpace / 1GB, 2)
                }
            }
        }